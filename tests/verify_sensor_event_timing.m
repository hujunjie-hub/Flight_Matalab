function report=verify_sensor_event_timing
%VERIFY_SENSOR_EVENT_TIMING Verify sample/capture/arrival timing and queue delivery.
root=flight_startup;
cfg=generate_parameters;
timing=cfg.derived.SensorTimingParameters(:);
epochUs=1000000;
timesUs=(epochUs:500:epochUs+1000000)';
truth=zeros(numel(timesUs),18);
truth(:,1:3)=repmat([0.01 0.02 0.03],numel(timesUs),1);
truth(:,4:6)=repmat([0.1 0.2 -cfg.derived.GravityMps2],numel(timesUs),1);
truth(:,7:9)=repmat([1 2 3],numel(timesUs),1);
truth(:,10:12)=repmat([4 5 6],numel(timesUs),1);
truth(:,13:15)=repmat([20 1 40],numel(timesUs),1);
truth(:,16)=10;
truth(:,17)=15; % IMU | GNSS | MAG | BARO valid.
truth(:,18)=1;

[~,events]=fmt_sensor_sim_probe(truth,timing,timesUs,epochUs);
validColumns=[1 5 9 13];
sampleColumns=[2 6 10 14];
captureColumns=[3 7 11 15];
arrivalColumns=[4 8 12 16];
periods=[timing(1),timing(4),timing(2),timing(3)];
pipeline=timing(5);
transports=[timing(6),timing(9),timing(7),timing(8)];
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

% IMU sample rate cannot exceed the 1-kHz production sensor task consumer.
invalid=timing;
invalid(1)=500;
rejected=false;
try
    fmt_sensor_sim_probe(truth(1:10,:),invalid,timesUs(1:10),epochUs);
catch
    rejected=true;
end
assert(rejected,'Flight:SensorTimingConsumerRate', ...
    'The timing engine accepted an IMU rate faster than the firmware consumer.');

% Queue bounds fail closed rather than silently dropping delayed samples.
invalid=timing;
invalid(5)=40000;
rejected=false;
try
    fmt_sensor_sim_probe(truth,invalid,timesUs,epochUs);
catch
    rejected=true;
end
assert(rejected,'Flight:SensorTimingQueueBound', ...
    'The timing engine accepted a delay that can overflow its bounded queue.');

report=struct('scope','SENSOR_SAMPLE_CAPTURE_ARRIVAL_TIMING','status','PASS', ...
    'channels',{names},'sample_period_us',periods, ...
    'pipeline_delay_us',pipeline,'transport_delay_us',transports, ...
    'delivered_event_count',counts,'max_delivery_lateness_us',maxLateness, ...
    'fixed_step_us',500,'event_time_order','sample <= capture <= arrival <= delivery', ...
    'queue_overflow_policy','FAIL_CLOSED','consumer_rate_gate','PASS');
file=fullfile(root,'work','validation','sensor_event_timing_report.json');
if ~isfolder(fileparts(file)), mkdir(fileparts(file)); end
fid=fopen(file,'w');
assert(fid>=0,'Flight:SensorTimingReport','Could not create sensor timing report.');
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));
disp(report);
end

