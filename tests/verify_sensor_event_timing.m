function report=verify_sensor_event_timing
%VERIFY_SENSOR_EVENT_TIMING Verify multirate sample/capture/arrival queues and loss accounting.
root=flight_startup;
cfg=generate_parameters;
timing=cfg.derived.SensorTimingParameters(:);
epochUs=1000000;
timesUs=(epochUs:500:epochUs+1200000)';
truth=zeros(numel(timesUs),18);
truth(:,1:3)=repmat([0.01 0.02 0.03],numel(timesUs),1);
truth(:,4:6)=repmat([0.1 0.2 -cfg.derived.GravityMps2],numel(timesUs),1);
truth(:,7:9)=repmat([1 2 3],numel(timesUs),1);
truth(:,10:12)=repmat([4 5 6],numel(timesUs),1);
truth(:,13:15)=repmat([20 1 40],numel(timesUs),1);
truth(:,16)=10;
truth(:,17)=15; % IMU | GNSS | MAG | BARO valid.
truth(:,18)=1;

[frames,events,stats]=fmt_sensor_sim_probe(truth,timing,timesUs,epochUs);
validColumns=[1 6 11 16];
sampleColumns=[2 7 12 17];
captureColumns=[3 8 13 18];
arrivalColumns=[4 9 14 19];
sequenceColumns=[5 10 15 20];
% The queue's channel order is IMU, GNSS, MAG, BARO; the parameter vector
% stores periods as IMU, MAG, BARO, GNSS and transports in the same order.
periods=timing([1 4 2 3])';
pipeline=timing(5);
transports=timing([6 9 7 8])';
names={'IMU','GNSS','MAG','BARO'};
maxLateness=zeros(1,4);
counts=zeros(1,4);
for channel=1:4
    rows=find(events(:,validColumns(channel))==1);
    assert(numel(rows)>=5,'Flight:SensorTimingCoverage', ...
        '%s did not produce enough timed samples.',names{channel});
    sample=events(rows,sampleColumns(channel));
    capture=events(rows,captureColumns(channel));
    arrival=events(rows,arrivalColumns(channel));
    delivery=timesUs(rows);
    assert(sample(1)==epochUs+periods(channel) && ...
           all(diff(sample)==periods(channel)), ...
        'Flight:SensorSamplePeriod','%s sample epochs do not follow the configured period.',names{channel});
    expectedPipeline=0;
    if channel==1, expectedPipeline=pipeline; end
    assert(all(capture-sample==expectedPipeline), ...
        'Flight:SensorCaptureEpoch','%s capture epochs do not match the configured pipeline delay.',names{channel});
    assert(all(arrival-capture==transports(channel)), ...
        'Flight:SensorArrivalEpoch','%s arrival epochs do not match the configured transport delay.',names{channel});
    assert(all(delivery>=arrival) && all(delivery-arrival<500), ...
        'Flight:SensorDeliveryJitter','%s events were delivered early or more than one fixed step late.',names{channel});
    maxLateness(channel)=max(delivery-arrival);
    counts(channel)=numel(rows);
end

% Conservation for the all-valid run:
% opportunities = generated + suppressed; generated = released + pending;
% every released probe event is accepted by the downstream probe sink.
assert(all(stats(:,1)==stats(:,2)+stats(:,3)+stats(:,7)), ...
    'Flight:SensorOpportunityConservation','Sensor opportunities are not conserved.');
assert(all(stats(:,2)==stats(:,4)+stats(:,6)), ...
    'Flight:SensorQueueConservation','Generated events do not equal released plus pending.');
assert(all(stats(:,4)==stats(:,5)) && all(stats(:,7)==0) && ...
       all(stats(:,6)<32), ...
    'Flight:SensorAcceptanceConservation','Released events were not accepted or queue capacity was exceeded.');
assert(all(stats(:,8)==stats(:,1)), ...
    'Flight:SensorSequenceAccounting','Sensor sequence counters do not include every sample opportunity.');
assert(all(frames(:,17)>=0 & frames(:,17)<=15), ...
    'Flight:SensorFrameMask','Probe returned an invalid delivered-frame mask.');

% Suppress exactly one sample opportunity per source. The next accepted event
% must expose a sequence gap; no source is removed and other channels continue.
dropTruth=truth;
bits=[1 2 4 8];
for channel=1:4
    dropTime=epochUs+2*periods(channel);
    dropRow=find(timesUs==dropTime,1);
    assert(~isempty(dropRow),'Flight:SensorDropFixture','Could not locate the selected suppression epoch.');
    dropTruth(dropRow,17)=15-bits(channel);
end
[~,dropEvents,dropStats]=fmt_sensor_sim_probe(dropTruth,timing,timesUs,epochUs);
for channel=1:4
    assert(dropStats(channel,1)==stats(channel,1) && ...
           dropStats(channel,2)==stats(channel,2)-1 && ...
           dropStats(channel,3)==1, ...
        'Flight:SensorSuppressionAccounting','%s suppressed event was not counted exactly once.',names{channel});
    assert(dropStats(channel,2)==dropStats(channel,4)+dropStats(channel,6) && ...
           dropStats(channel,4)==dropStats(channel,5), ...
        'Flight:SensorDropConservation','%s generated/released/accepted counts do not balance.',names{channel});
    sequence=dropEvents(dropEvents(:,validColumns(channel))==1,sequenceColumns(channel));
    assert(numel(sequence)==dropStats(channel,4) && ...
           sum(diff(sequence)==2)==1 && all(diff(sequence)==1 | diff(sequence)==2), ...
        'Flight:SensorSequenceGap','%s missing sample did not create one observable sequence gap.',names{channel});
end

% Reject unsupported rates, queue-overflow configurations, non-monotonic time,
% skipped fixed steps and malformed validity masks instead of silently drifting.
invalid=timing;
invalid(1)=500;
expect_probe_error(truth(1:20,:),invalid,timesUs(1:20),epochUs, ...
    'Flight:SensorTimingConsumerRate','IMU rate faster than the production consumer was accepted.');
invalid=timing;
invalid(5)=40000;
expect_probe_error(truth,invalid,timesUs,epochUs, ...
    'Flight:SensorTimingQueueBound','A delay exceeding the bounded queue horizon was accepted.');
invalid=timing;
invalid(6)=5000; % IMU pipeline + transport now exceeds its 5-ms validity horizon.
expect_probe_error(truth,invalid,timesUs,epochUs, ...
    'Flight:SensorTimingExpiry','An IMU event that expires before delivery was accepted.');
invalid=timing;
invalid(9)=20000; % GNSS PVT validity horizon.
expect_probe_error(truth,invalid,timesUs,epochUs, ...
    'Flight:SensorTimingExpiry','A GNSS event that expires before delivery was accepted.');
irregularTimes=timesUs(1:20);
irregularTimes(6)=irregularTimes(6)+250;
expect_probe_error(truth(1:20,:),timing,irregularTimes,epochUs, ...
    'Flight:SensorTimingStep','A non-500-us simulation step was accepted.');
reversedTimes=timesUs(1:20);
reversedTimes(6)=reversedTimes(5)-500;
expect_probe_error(truth(1:20,:),timing,reversedTimes,epochUs, ...
    'Flight:SensorTimingMonotonic','A backwards simulation clock was accepted.');
invalidTruth=truth(1:20,:);
invalidTruth(3,17)=1.5;
expect_probe_error(invalidTruth,timing,timesUs(1:20),epochUs, ...
    'Flight:SensorTimingMask','A fractional sensor validity mask was accepted.');

report=struct('scope','SENSOR_SAMPLE_CAPTURE_ARRIVAL_QUEUE','status','PASS', ...
    'overall_P10_status','PARTIAL','channels',{names}, ...
    'sample_period_us',periods,'pipeline_delay_us',pipeline, ...
    'transport_delay_us',transports,'delivered_event_count',counts, ...
    'max_delivery_lateness_us',maxLateness, ...
    'generated_suppressed_released_accepted',stats(:,1:5), ...
    'suppression_gap_sequence_test','PASS', ...
    'counter_conservation','PASS','fixed_step_us',500, ...
    'event_time_order','sample <= capture <= arrival <= delivery', ...
    'queue_overflow_policy','FAIL_CLOSED','consumer_rate_gate','PASS', ...
    'pps_capture_and_utc_epoch_mapping','NOT_IMPLEMENTED');
file=fullfile(root,'work','validation','sensor_event_timing_report.json');
if ~isfolder(fileparts(file)), mkdir(fileparts(file)); end
fid=fopen(file,'w');
assert(fid>=0,'Flight:SensorTimingReport','Could not create sensor timing report.');
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));
disp(report);
end

function expect_probe_error(truth,timing,times,epoch,identifier,message)
failed=false;
try
    fmt_sensor_sim_probe(truth,timing,times,epoch);
catch
    failed=true;
end
assert(failed,identifier,'%s',message);
end

