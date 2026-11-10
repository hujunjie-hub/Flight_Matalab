function report=run_component_checks(gccDir)
%RUN_COMPONENT_CHECKS Rebuild the Host SIL/model ABI and run current-branch MATLAB acceptance gates.
if nargin<1, gccDir='D:\STM32CubeCLT\mingw64\bin'; end
root=flight_startup;
file=fullfile(root,'work','validation','component_checks.json');
report=struct('scope','IMPLEMENTED_COMPONENTS_AND_ENTRY_REPLAY','status','IN_PROGRESS', ...
    'acceptance_profile','CURRENT_BRANCH_MATLAB_HOST_MIL', ...
    'checks',struct);
report.environment=struct('matlab_version',version, ...
    'matlab_release',version('-release'),'computer',computer);
write(file,report);
try
    % Record the pre-run tree: committed source digest, worktree digest and the
    % artifact hashes of the previous build, so the archive can separate what
    % was under test from what this run regenerated.
    report.pre_run=flight_acceptance_snapshot(root,'before');
    % Rebuild the upstream Host SIL DLL and every affected Simulink/MEX ABI.
    runtimeScript=fullfile(root,'tools','build_flight_runtime.ps1');
    [runtimeStatus,runtimeMessage]=system(sprintf('pwsh -File "%s" -GccDir "%s"', ...
        runtimeScript,gccDir));
    assert(runtimeStatus==0,'Flight:RuntimeBuild','%s',runtimeMessage);
    build_native_kernels;
    generate_parameters;
    build_plant_models(8);
    build_flight_models;
    build_actuation_components;
    build_pid_allocation_probe;
    % Refresh the tracked replay tape from this exact MIL build before hashing inputs.
    report.checks.flight_entries=verify_flight_entries(true);
    report.source_fingerprint=fingerprint(root);
    report.checks.native_kernels='PASS';
    % Prove the evidence pipeline itself: source/artifact separation, classification
    % and the repeated-run determinism the archive manifest relies on.
    report.checks.archive_reliability=verify_archive_reliability;
    report.checks.time_service=verify_time_service_sync;
    report.checks.gnss_time_recovery=verify_gnss_time_recovery;
    report.checks.rectime_time_mapping=verify_rectime_time_mapping;
    report.checks.parameters=verify_parameter_view;
    report.checks.osqp=verify_osqp_gate;
    report.checks.execution=verify_execution_gate;
    report.checks.plant=verify_plant_open_loop;
    report.checks.sensor_event_timing=report.checks.plant.sensor_timing;
    report.checks.truth_isolation=verify_truth_isolation;
    report.checks.pid=verify_rate_pid_transaction;
    report.checks.pid_allocator_feedback=verify_pid_allocator_feedback;
    report.checks.actuation=verify_actuation_components;
    report.checks.p10b=verify_p10b_pps_rectime;
    report.checks.p10b_utc=verify_p10b_utc_mapping;
    % The MPC job gate runs last: a failure there must not hide the evidence of
    % the other gates, and its numbers belong in the same archive.
    report.checks.m6_jobs=verify_m6_jobs;
    assert(strcmp(report.source_fingerprint,fingerprint(root)),'Flight:InputsChanged','Model/code/configuration changed during the checks.');
    report.post_run=flight_acceptance_snapshot(root,'after');
    report.status='PARTIAL_PASS';
    report.plant_coverage=report.checks.plant.coverage;
catch exception
    report.status='FAIL';
    report.error=struct('identifier',exception.identifier,'message',exception.message);
    % A failing run must still explain what it changed, otherwise the archive
    % cannot distinguish a broken build from a dirty worktree.
    try
        report.post_run=flight_acceptance_snapshot(root,'after');
    catch snapshotException
        report.post_run=struct('stage','after','error',snapshotException.message);
    end
    write(file,report);
    rethrow(exception);
end
write(file,report);
fprintf('MATLAB acceptance gates completed; Plant P-10 Host MIL integration remains partial.\n');
end

function value=fingerprint(root)
[status,message]=system(sprintf('python -B "%s"',fullfile(root,'tools','fingerprint_sources.py')));
assert(status==0,'Flight:Fingerprint','%s',message);
record=jsondecode(fileread(fullfile(root,'work','validation','current_source_fingerprint.json')));
value=record.sha256;
end

function write(file,report)
fid=fopen(file,'w');cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));
end

