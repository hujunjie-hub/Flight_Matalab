function report=verify_m6_jobs(root)
%VERIFY_M6_JOBS Validate the real MPC job set and its complete per-job evidence.
%   Coverage remains measured over the whole MIL duration. The gate fails
%   closed when no jobs ran, counters disagree, or the per-job evidence is
%   missing/incomplete. No acceptance threshold or denominator is changed.
if nargin<1 || isempty(root)
    root=fileparts(fileparts(mfilename('fullpath')));
end
root=char(root);
report=struct('scope','M6_MPC_JOBS','status','IN_PROGRESS');
write_report(root,report);
try
    statsFile=fullfile(root,'work','validation','m6_runtime_stats_mil.json');
    assert(isfile(statsFile),'Flight:M6Jobs', ...
        'The MIL run did not produce m6_runtime_stats_mil.json; MPC accounting is missing.');
    stats=jsondecode(fileread(statsFile));
    assert(isfield(stats,'schema') && strcmp(char(stats.schema),'fmat-m6-runtime-stats/1.0'), ...
        'Flight:M6JobsSchema','MPC runtime statistics schema is missing or unsupported.');

    jobs=nonnegative_integer(stats,'jobs');
    solved=nonnegative_integer(stats,'solved');
    rejected=nonnegative_integer(stats,'rejected');
    coveredUs=nonnegative_integer(stats,'covered_us');
    declaredRecords=nonnegative_integer(stats,'job_record_count');

    entriesFile=fullfile(root,'work','validation','flight_entries.json');
    assert(isfile(entriesFile),'Flight:M6Jobs', ...
        'flight_entries.json is required to weight MPC coverage by run duration.');
    entries=jsondecode(fileread(entriesFile));
    assert(isfield(entries,'duration_s') && isscalar(entries.duration_s) && ...
        isfinite(double(entries.duration_s)) && double(entries.duration_s)>0, ...
        'Flight:M6Duration','MIL duration must be a finite positive scalar.');
    durationUs=round(double(entries.duration_s)*1e6);
    assert(isfinite(durationUs) && durationUs>0, ...
        'Flight:M6Duration','MIL duration is outside the supported microsecond range.');
    assert(coveredUs<=durationUs,'Flight:M6CoverageRange', ...
        'MPC covered_us (%g) exceeds the full MIL duration (%g).',coveredUs,durationUs);
    assert(solved+rejected==jobs,'Flight:M6Jobs', ...
        'MPC counters are inconsistent: jobs=%d solved=%d rejected=%d.',jobs,solved,rejected);

    if jobs==0
        blocked=blocked_counters(stats);
        report=struct('scope','M6_MPC_JOBS','status','NOT_RUN','jobs',0, ...
            'blocked',blocked,'job_record_count',declaredRecords, ...
            'reason','The required MIL scenario produced no MPC solve jobs; acceptance cannot pass.');
        write_report(root,report);
        error('Flight:M6JobsNotRun', ...
            'MPC job gate was NOT_RUN: the required MIL scenario produced zero solve jobs.');
    end

    assert(declaredRecords==jobs,'Flight:M6JobRecords', ...
        'Runtime reports %d jobs but only declares %d per-job records.',jobs,declaredRecords);
    records=job_records(root,jobs);
    evidence=evidence_summary(records,stats);

    successRate=solved/jobs;
    coverage=coveredUs/durationUs;

    % FMAT-0012 is still blocked on the denominator decision. Keep the
    % existing whole-run denominator and 90% threshold unchanged.
    eligibleTicks=NaN;
    if isfield(stats,'worker_ticks')
        eligibleTicks=double(stats.worker_ticks);
        if isfield(stats,'blocked_mode')
            eligibleTicks=max(0,eligibleTicks-double(stats.blocked_mode));
        end
    end
    coverageBasis=struct('duration_s',entries.duration_s, ...
        'coverage_over_total_run',coverage, ...
        'gate_denominator','whole run (unchanged; FMAT-0012 decision pending)', ...
        'worker_ticks',double(field_or(stats,'worker_ticks',NaN)), ...
        'blocked_mode_ticks',double(field_or(stats,'blocked_mode',NaN)), ...
        'trajectory_eligible_ticks',eligibleTicks, ...
        'note','coverage_over_eligible_window is informational only; it is never used for the verdict.');
    if ~isnan(eligibleTicks) && eligibleTicks>0
        coverageBasis.eligible_window_us=eligibleTicks*20000;
        coverageBasis.coverage_over_eligible_window=min(1,coveredUs/coverageBasis.eligible_window_us);
    end

    jobsGate=jobs>=100;
    successGate=successRate>=0.99;
    coverageGate=coverage>=0.90;

    report=struct('scope','M6_MPC_JOBS','status','PASS', ...
        'jobs',jobs,'solved',solved,'rejected',rejected, ...
        'job_record_count',numel(records),'job_records_complete',true, ...
        'success_rate',successRate,'time_weighted_coverage',coverage, ...
        'duration_s',entries.duration_s, ...
        'coverage_basis',coverageBasis, ...
        'minimum_jobs_100',ternary(jobsGate,'PASS','FAIL'), ...
        'success_rate_99',ternary(successGate,'PASS','FAIL'), ...
        'coverage_90',ternary(coverageGate,'PASS','FAIL'), ...
        'fallback_counted_as_uncovered',true, ...
        'evidence',evidence);
    if ~(jobsGate && successGate && coverageGate)
        report.status='FAIL';
    end
    write_report(root,report);
    assert(strcmp(report.status,'PASS'),'Flight:M6Jobs', ...
        'MPC job set misses an acceptance threshold: jobs=%d success=%.4f coverage=%.4f; %s.', ...
        jobs,successRate,coverage,evidence.verdict);
catch exception
    if strcmp(report.status,'IN_PROGRESS')
        report.status='FAIL';
    end
    report.error=struct('identifier',exception.identifier,'message',exception.message);
    write_report(root,report);
    rethrow(exception);
end
end

function value=nonnegative_integer(source,name)
assert(isfield(source,name),'Flight:M6StatsField', ...
    'MPC runtime statistics are missing required field %s.',name);
value=double(source.(name));
assert(isscalar(value) && isfinite(value) && value>=0 && value==fix(value), ...
    'Flight:M6StatsValue','MPC runtime field %s must be a finite nonnegative integer.',name);
end

function blocked=blocked_counters(stats)
blocked=struct();
names={'blocked_uninitialized','blocked_validation','blocked_mode', ...
    'blocked_clock','blocked_stale','blocked_throttle','blocked_lock', ...
    'last_validation_status'};
for k=1:numel(names)
    if isfield(stats,names{k})
        blocked.(names{k})=double(stats.(names{k}));
    end
end
end

function records=job_records(root,expectedCount)
% Per-job rows are captured immediately after MIL, before replay sessions.
file=fullfile(root,'work','validation','m6_jobs_mil.json');
assert(isfile(file),'Flight:M6JobRecords', ...
    'm6_jobs_mil.json is missing; aggregate counters cannot substitute for per-job evidence.');
raw=jsondecode(fileread(file));
assert(isfield(raw,'schema') && strcmp(char(raw.schema),'fmat-m6-jobs/1.0'), ...
    'Flight:M6JobRecordsSchema','Per-job record schema is missing or unsupported.');
assert(isfield(raw,'record_count'),'Flight:M6JobRecordsCount', ...
    'Per-job record file is missing record_count.');
declared=double(raw.record_count);
assert(isscalar(declared) && isfinite(declared) && declared==fix(declared) && ...
    declared==expectedCount,'Flight:M6JobRecordsCount', ...
    'Per-job record file declares %g records; expected %d.',declared,expectedCount);
assert(isfield(raw,'records') && ~isempty(raw.records),'Flight:M6JobRecords', ...
    'Per-job record array is missing or empty.');
records=raw.records;
assert(numel(records)==expectedCount,'Flight:M6JobRecordsCount', ...
    'Per-job record array contains %d records; expected %d.',numel(records),expectedCount);

required={'job','outcome','solver_status','prim_res','dual_res', ...
    'primal_violation','thrust_excess_n','sample_us','eval_us','expires_us'};
jobIds=zeros(1,numel(records));
for k=1:numel(records)
    for j=1:numel(required)
        assert(isfield(records(k),required{j}),'Flight:M6JobRecordField', ...
            'Per-job record %d is missing field %s.',k,required{j});
        value=double(records(k).(required{j}));
        assert(isscalar(value) && isfinite(value),'Flight:M6JobRecordValue', ...
            'Per-job record %d field %s is not finite.',k,required{j});
    end
    jobIds(k)=double(records(k).job);
    outcome=double(records(k).outcome);
    assert(jobIds(k)>=0 && jobIds(k)==fix(jobIds(k)), ...
        'Flight:M6JobRecordId','Per-job record %d has an invalid job ID.',k);
    assert(outcome>=0 && outcome<=10 && outcome==fix(outcome), ...
        'Flight:M6JobRecordOutcome','Per-job record %d has an unknown outcome code.',k);
end
assert(numel(unique(jobIds))==expectedCount,'Flight:M6JobRecordId', ...
    'Per-job record IDs are not unique.');
end

function evidence=evidence_summary(records,stats)
%EVIDENCE_SUMMARY Stage counts, residual distributions and consumer acceptance.
names={'OK','DOMAIN','REFERENCE','BOUNDS','SOLVER_CALL','SOLVER_STATUS', ...
    'NON_FINITE','RESIDUAL','PRIMAL','THRUST','DEADLINE'};
counts=zeros(1,numel(names));
recordCount=numel(records);
prim=zeros(1,recordCount); dual=prim; violation=prim; excess=prim;
life=zeros(1,recordCount); evalAge=prim; expiryAge=prim;
for k=1:recordCount
    index=double(records(k).outcome)+1;
    counts(index)=counts(index)+1;
    prim(k)=double(records(k).prim_res);
    dual(k)=double(records(k).dual_res);
    violation(k)=double(records(k).primal_violation);
    excess(k)=double(records(k).thrust_excess_n);
    life(k)=double(records(k).expires_us)-double(records(k).sample_us);
    evalAge(k)=double(records(k).eval_us)-double(records(k).sample_us);
    expiryAge(k)=double(records(k).expires_us)-double(records(k).eval_us);
end
stages=struct();
for k=1:numel(names)
    stages.(names{k})=counts(k);
end

evidence=struct();
evidence.record_count=recordCount;
evidence.stage_counts=stages;
evidence.solver_statuses=status_counts(records);
evidence.prim_res=distribution(prim);
evidence.dual_res=distribution(dual);
evidence.primal_violation=distribution(violation);
evidence.thrust_excess_n=distribution(excess);
evidence.snapshot_life_us=distribution(life);
evidence.eval_minus_sample_us=distribution(evalAge);
evidence.expires_minus_eval_us=distribution(expiryAge);
if isfield(stats,'consumer')
    evidence.consumer=consumer_summary(stats.consumer);
end
evidence.verdict=sprintf('first failing stage: %s (dual_res median %.3e)', ...
    dominant_stage(stages),median_of(dual));
end

function out=status_counts(records)
out=struct();
for k=1:numel(records)
    key=sprintf('status_%d',double(records(k).solver_status));
    if isfield(out,key), out.(key)=out.(key)+1; else, out.(key)=1; end
end
end

function value=dominant_stage(stages)
value='none';
best=0;
names=fieldnames(stages);
for k=1:numel(names)
    if strcmp(names{k},'OK'), continue; end
    if stages.(names{k})>best
        best=stages.(names{k});
        value=names{k};
    end
end
end

function out=consumer_summary(c)
out=struct();
fields={'samples','used','backup_expired','backup_clock','backup_state_epoch', ...
    'backup_origin','backup_reference','backup_authority','backup_directive', ...
    'backup_envelope','backup_model','backup_envelope_id', ...
    'backup_seed_position','backup_seed_velocity','limit_rejected','bounds_rejected'};
for k=1:numel(fields)
    if isfield(c,fields{k}), out.(fields{k})=double(c.(fields{k})); end
end
if isfield(c,'samples') && double(c.samples)>0
    out.used_fraction=double(c.used)/double(c.samples);
end
lifeFields={'life_bucket_origin_us','life_bucket_us','life_min_us','life_max_us','life_total'};
for k=1:numel(lifeFields)
    if isfield(c,lifeFields{k}), out.(lifeFields{k})=double(c.(lifeFields{k})); end
end
if isfield(c,'life_hist')
    out.life_hist=double(c.life_hist(:))';
end
end

function out=distribution(values)
if isempty(values)
    out=struct('count',0);
    return;
end
sorted=sort(values(:)');
out=struct('count',numel(sorted),'min',sorted(1), ...
    'p25',quantile_of(sorted,0.25),'median',quantile_of(sorted,0.5), ...
    'p75',quantile_of(sorted,0.75),'max',sorted(end));
end

function value=median_of(values)
if isempty(values)
    value=NaN;
else
    value=quantile_of(sort(values(:)'),0.5);
end
end

function value=quantile_of(sorted,q)
% Linear interpolation between order statistics; avoids a toolbox dependency.
n=numel(sorted);
if n==1
    value=sorted(1);
    return;
end
position=q*(n-1)+1;
low=floor(position);
high=ceil(position);
value=sorted(low)+(position-low)*(sorted(high)-sorted(low));
end

function write_report(root,report)
file=fullfile(root,'work','validation','m6_report.json');
folder=fileparts(file);
if ~isfolder(folder), mkdir(folder); end
fid=fopen(file,'w');
assert(fid>=0,'Flight:M6Report','Cannot write M6 report: %s',file);
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));
end

function value=field_or(source,name,default)
value=default;
if isstruct(source) && isfield(source,name) && ~isempty(source.(name))
    value=source.(name);
end
end

function value=ternary(condition,whenTrue,whenFalse)
if condition
    value=whenTrue;
else
    value=whenFalse;
end
end
