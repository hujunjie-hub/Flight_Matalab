function report=run_component_checks(gccDir)
%RUN_COMPONENT_CHECKS Rebuild the Host SIL/model ABI and run implemented component gates.
if nargin<1, gccDir='D:\STM32CubeCLT\mingw64\bin'; end
root=flight_startup;
file=fullfile(root,'work','validation','component_checks.json');
report=struct('scope','IMPLEMENTED_COMPONENTS_ONLY','status','IN_PROGRESS', ...
    'checks',struct);
write(file,report);
try
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
    report.source_fingerprint=fingerprint(root);
    report.checks.native_kernels='PASS';
    report.checks.time_service=verify_time_service_sync;
    report.checks.gnss_time_recovery=verify_gnss_time_recovery;
    report.checks.parameters=verify_parameter_view;
    report.checks.osqp=verify_osqp_gate;
    report.checks.execution=verify_execution_gate;
    report.checks.plant=verify_plant_open_loop;
    report.checks.sensor_event_timing=report.checks.plant.sensor_timing;
    report.checks.truth_isolation=verify_truth_isolation;
    report.checks.pid=verify_rate_pid_transaction;
    report.checks.pid_allocator_feedback=verify_pid_allocator_feedback;
    report.checks.actuation=verify_actuation_components;
    assert(strcmp(report.source_fingerprint,fingerprint(root)),'Flight:InputsChanged','Model/code/configuration changed during the checks.');
    report.status='PARTIAL_PASS';
    report.plant_coverage=report.checks.plant.coverage;
catch exception
    report.status='FAIL';
    report.error=struct('identifier',exception.identifier,'message',exception.message);
    write(file,report);
    rethrow(exception);
end
write(file,report);
fprintf('Component checks completed; Plant acceptance coverage remains partial.\n');
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

