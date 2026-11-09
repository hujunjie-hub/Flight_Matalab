function report=run_component_checks
%RUN_COMPONENT_CHECKS Run implemented component gates, never full-system acceptance.
root=flight_startup;
file=fullfile(root,'work','validation','component_checks.json');
report=struct('scope','IMPLEMENTED_COMPONENTS_ONLY','status','IN_PROGRESS', ...
    'checks',struct);
write(file,report);
try
    % Rebuild Plant/native gateways so checks cannot silently use stale MEX binaries.
    build_native_kernels;
    generate_parameters;
    sensorModel=fullfile(root,'models','plant','FMT_PlantSensors.slx');
    if ~isfile(sensorModel), build_plant_models(8); end
    build_actuation_components;
    build_pid_allocation_probe;
    report.source_fingerprint=fingerprint(root);
    report.checks.native_kernels='PASS';
    report.checks.parameters=verify_parameter_view;
    report.checks.osqp=verify_osqp_gate;
    report.checks.execution=verify_execution_gate;
    report.checks.plant=verify_plant_open_loop;
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

