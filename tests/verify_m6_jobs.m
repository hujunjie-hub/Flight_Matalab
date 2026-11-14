function report=verify_m6_jobs
%VERIFY_M6_JOBS Summarise the real MPC job set produced by the MIL run.
%   The counters are written by the Flight runtime at shutdown
%   (applications/tasks/mpc/task_mpc.c owns them); this gate only aggregates and
%   applies the acceptance thresholds, so a fallback window can never be counted
%   as coverage.
%
%   Since FMAT-0012 the runtime also records one row per job (first failing
%   stage, solver status, unscaled residuals, independent violations and the
%   snapshot timestamps) plus one counter per consumer fallback clause.  The
%   distributions below are therefore measured over every job, not read off the
%   last sample of the run.
root=fileparts(fileparts(mfilename('fullpath')));
statsFile=fullfile(root,'work','validation','m6_runtime_stats_mil.json');
assert(isfile(statsFile),'Flight:M6Jobs', ...
    'The MIL run did not produce m6_runtime_stats_mil.json; MPC accounting is missing.');
stats=jsondecode(fileread(statsFile));

entriesFile=fullfile(root,'work','validation','flight_entries.json');
assert(isfile(entriesFile),'Flight:M6Jobs', ...
    'flight_entries.json is required to weight the MPC coverage by run duration.');
entries=jsondecode(fileread(entriesFile));
durationUs=max(1,round(entries.duration_s*1e6));

% The adapter has used both key sets; accept either so a stale DLL cannot make
% the gate read the wrong field.
if isfield(stats,'jobs')
    jobs=double(stats.jobs); solved=double(stats.solved);
    rejected=double(stats.rejected); coveredUs=double(stats.covered_us);
else
    jobs=double(stats.mpc_updates); solved=double(stats.mpc_solved);
    rejected=double(stats.mpc_rejected); coveredUs=double(stats.mpc_covered_us);
end
assert(solved+rejected==jobs,'Flight:M6Jobs', ...
    'MPC counters are inconsistent: jobs=%d solved=%d rejected=%d.',jobs,solved,rejected);

records=job_records(root);
evidence=evidence_summary(records,stats);
if jobs==0
    % The MIL scenario never entered the trajectory MPC path, so there is no
    % job set to judge. Report NOT_RUN rather than a fake 0 % success rate.
    blocked=struct();
    names={'blocked_uninitialized','blocked_validation','blocked_mode', ...
        'blocked_clock','blocked_stale','blocked_throttle','blocked_lock'};
    for k=1:numel(names)
        if isfield(stats,names{k}), blocked.(names{k})=double(stats.(names{k})); end
    end
    if isfield(stats,'last_validation_status')
        blocked.last_validation_status=double(stats.last_validation_status);
    end
    report=struct('scope','M6_MPC_JOBS','status','NOT_RUN','jobs',0, ...
        'blocked',blocked,'evidence',evidence, ...
        'reason','the 50 Hz MPC worker never reached mpc_solve(); see blocked counters');
    write_report(root,report);
    return;
end

successRate=solved/jobs;
coverage=min(1,coveredUs/durationUs);

% The acceptance threshold is unchanged: covered_us over the whole run. Issue #12
% also asks what the denominator should be, because the worker can only solve
% while guidance is in the trajectory mode. Report both bases so the difference
% is visible instead of being argued about, but keep judging on the same one.
eligibleTicks=NaN;
if isfield(stats,'worker_ticks')
    eligibleTicks=double(stats.worker_ticks);
    if isfield(stats,'blocked_mode')
        eligibleTicks=max(0,eligibleTicks-double(stats.blocked_mode));
    end
end
coverageBasis=struct('duration_s',entries.duration_s, ...
    'coverage_over_total_run',coverage, ...
    'gate_denominator','whole run (unchanged)', ...
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
end

function records=job_records(root)
%Per-job rows, snapshotted right after the MIL (the replays overwrite the live
%file with an empty record set).
records=[];
file=fullfile(root,'work','validation','m6_jobs_mil.json');
if ~isfile(file)
    return;
end
raw=jsondecode(fileread(file));
if ~isfield(raw,'records') || isempty(raw.records)
    return;
end
records=raw.records;
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
    if index>=1 && index<=numel(counts), counts(index)=counts(index)+1; end
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
%Linear interpolation between order statistics; avoids a toolbox dependency.
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
fid=fopen(file,'w'); cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));
disp(report);
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
