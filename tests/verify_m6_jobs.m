function report=verify_m6_jobs
%VERIFY_M6_JOBS Summarise the real MPC job set produced by the MIL run.
%   The counters are written by the Flight runtime at shutdown
%   (applications/tasks/mpc/task_mpc.c owns them); this gate only aggregates and
%   applies the acceptance thresholds, so a fallback window can never be counted
%   as coverage.
root=fileparts(fileparts(mfilename('fullpath')));
statsFile=fullfile(root,'work','validation','m6_runtime_stats.json');
assert(isfile(statsFile),'Flight:M6Jobs', ...
    'The MIL run did not produce m6_runtime_stats.json; MPC accounting is missing.');
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
if jobs==0
    % The MIL scenario never entered the trajectory MPC path, so there is no
    % job set to judge. Report NOT_RUN rather than a fake 0 % success rate.
    report=struct('scope','M6_MPC_JOBS','status','NOT_RUN','jobs',0, ...
        'reason','MIL scenario never entered the trajectory MPC path');
    file=fullfile(root,'work','validation','m6_report.json');
    fid=fopen(file,'w'); cleanup=onCleanup(@()fclose(fid));
    fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));
    disp(report);
    return;
end

successRate=solved/jobs;
coverage=min(1,coveredUs/durationUs);

jobsGate=jobs>=100;
successGate=successRate>=0.99;
coverageGate=coverage>=0.90;

report=struct('scope','M6_MPC_JOBS','status','PASS', ...
    'jobs',jobs,'solved',solved,'rejected',rejected, ...
    'success_rate',successRate,'time_weighted_coverage',coverage, ...
    'duration_s',entries.duration_s, ...
    'minimum_jobs_100',ternary(jobsGate,'PASS','FAIL'), ...
    'success_rate_99',ternary(successGate,'PASS','FAIL'), ...
    'coverage_90',ternary(coverageGate,'PASS','FAIL'), ...
    'fallback_counted_as_uncovered',true);
if ~(jobsGate && successGate && coverageGate)
    report.status='FAIL';
end
file=fullfile(root,'work','validation','m6_report.json');
fid=fopen(file,'w'); cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));
disp(report);
assert(strcmp(report.status,'PASS'),'Flight:M6Jobs', ...
    'MPC job set misses an acceptance threshold: jobs=%d success=%.4f coverage=%.4f.', ...
    jobs,successRate,coverage);
end

function value=ternary(condition,whenTrue,whenFalse)
if condition
    value=whenTrue;
else
    value=whenFalse;
end
end
