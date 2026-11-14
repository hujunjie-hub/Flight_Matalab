function report=verify_m6_jobs_contract
%VERIFY_M6_JOBS_CONTRACT Exercise the M6 evidence gate with isolated fixtures.
%   These tests use a temporary repository-shaped directory and never touch
%   the user's active work/validation reports or generated Simulink artifacts.
tempRoot=tempname;
mkdir(tempRoot);
cleanup=onCleanup(@()remove_tree(tempRoot));
validation=fullfile(tempRoot,'work','validation');
mkdir(validation);

[stats,records]=valid_fixture;
write_fixture(validation,stats,records);
valid=verify_m6_jobs(tempRoot);
assert(strcmp(valid.status,'PASS') && valid.jobs==100 && ...
    valid.job_record_count==100 && valid.job_records_complete, ...
    'Flight:M6ContractValid','A complete 100-job evidence fixture was not accepted.');

% Zero jobs must remain visibly NOT_RUN while making the gate throw.
zeroStats=stats;
zeroStats.jobs=0;
zeroStats.solved=0;
zeroStats.rejected=0;
zeroStats.covered_us=0;
zeroStats.job_record_count=0;
write_fixture(validation,zeroStats,records([]));
expect_failure(tempRoot,'NOT_RUN');

% Aggregate counters may not claim jobs without a complete record for each.
shortRecords=records(1:end-1);
write_fixture(validation,stats,shortRecords);
expect_failure(tempRoot,'FAIL');

% Solved/rejected must reconcile exactly to the job total.
badCounters=stats;
badCounters.solved=99;
write_fixture(validation,badCounters,records);
expect_failure(tempRoot,'FAIL');

% Aggregate counters must also reconcile to the actual per-job outcomes.
badOutcomeRecords=records;
badOutcomeRecords(1).outcome=7; % MPC_OUTCOME_RESIDUAL, not OK
write_fixture(validation,stats,badOutcomeRecords);
expect_failure(tempRoot,'FAIL');

% Job IDs must be the complete 1-based sequence, not merely unique.
badJobIds=records;
badJobIds(1).job=0;
write_fixture(validation,stats,badJobIds);
expect_failure(tempRoot,'FAIL');

% Coverage cannot exceed the actual full-run duration.
badCoverage=stats;
badCoverage.covered_us=2100001;
write_fixture(validation,badCoverage,records);
expect_failure(tempRoot,'FAIL');

% Old or unversioned runtime output must not be silently accepted.
badSchema=stats;
badSchema.schema='legacy-unversioned';
write_fixture(validation,badSchema,records);
expect_failure(tempRoot,'FAIL');

report=struct('scope','M6_JOB_EVIDENCE_CONTRACT','status','PASS', ...
    'valid_100_job_fixture','PASS','zero_job_not_run','PASS', ...
    'missing_record_rejected','PASS','counter_mismatch_rejected','PASS', ...
    'aggregate_outcome_mismatch_rejected','PASS','invalid_job_id_rejected','PASS', ...
    'coverage_overflow_rejected','PASS','legacy_schema_rejected','PASS');
disp(report);
end

function [stats,records]=valid_fixture
stats=struct('schema','fmat-m6-runtime-stats/1.0', ...
    'jobs',100,'solved',100,'rejected',0,'covered_us',1995000, ...
    'job_record_count',100,'worker_ticks',105,'blocked_mode',0);
record=struct('job',0,'outcome',0,'solver_status',1, ...
    'prim_res',1e-4,'dual_res',1e-4,'primal_violation',0, ...
    'thrust_excess_n',0,'sample_us',1000,'eval_us',2000,'expires_us',25000);
records=repmat(record,100,1);
for k=1:numel(records)
    records(k).job=k;
    records(k).sample_us=1000+(k-1)*20000;
    records(k).eval_us=records(k).sample_us+2000;
    records(k).expires_us=records(k).sample_us+23000;
end
end

function write_fixture(validation,stats,records)
entries=struct('duration_s',2.1);
jobs=struct('schema','fmat-m6-jobs/1.0', ...
    'record_count',numel(records),'records',records);
write_json(fullfile(validation,'m6_runtime_stats_mil.json'),stats);
write_json(fullfile(validation,'flight_entries.json'),entries);
write_json(fullfile(validation,'m6_jobs_mil.json'),jobs);
end

function write_json(path,value)
fid=fopen(path,'w');
assert(fid>=0,'Flight:M6ContractFixture','Cannot write fixture %s.',path);
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(value));
end

function expect_failure(root,expectedStatus)
failed=false;
try
    verify_m6_jobs(root);
catch
    failed=true;
end
assert(failed,'Flight:M6ContractExpectedFailure', ...
    'M6 gate unexpectedly accepted a negative evidence fixture.');
path=fullfile(root,'work','validation','m6_report.json');
report=jsondecode(fileread(path));
assert(strcmp(report.status,expectedStatus),'Flight:M6ContractStatus', ...
    'Expected status %s but received %s.',expectedStatus,report.status);
end

function remove_tree(path)
if isfolder(path)
    rmdir(path,'s');
end
end
