% Run the firmware-backed project checks in an independent MATLAB process.
projectRoot=fileparts(fileparts(mfilename('fullpath')));
coldReportFile=fullfile(projectRoot,'work','validation','cold_start_report.json');
coldReport=struct('scope','NEW_MATLAB_PROCESS_FLIGHT_HOST_SIL','status','IN_PROGRESS');
try
    project=openProject(fullfile(projectRoot,'Flight_Matalab.prj'));
    assert(isempty(which('FMT_Model_Init')),'Flight:LegacyPath','Legacy initialization is present on the active path.');
    pathBefore=path;flight_startup;flight_startup;
    assert(strcmp(path,pathBefore),'Flight:StartupIdempotence','Repeated startup changed the MATLAB path.');
    entries={'FMT_DataSIM','FMT_MILSIM','FMT_ExtINS_DataSIM'};
    for k=1:numel(entries)
        model=entries{k};
        assert(~isempty(findFile(project,fullfile(projectRoot,'simulation',[model '.slx']))), ...
            'Flight:ProjectArtifact','%s is absent from the MATLAB project.',model);
        input=Simulink.SimulationInput(model);
        smoke=sim(input.setModelParameter('StopTime','0.05'));
        assert(abs(smoke.tout(end)-.05)<1e-10,'Flight:DefaultInput','%s failed to run with its default input.',model);
    end
    coldReport.entries=verify_flight_entries;
    checks=runChecks(project);
    records=repmat(struct('id','','description','','passed',false),numel(checks),1);
    for k=1:numel(checks)
        records(k)=struct('id',char(checks(k).ID),'description',char(checks(k).Description),'passed',checks(k).Passed);
    end
    assert(all([records.passed]),'Flight:ProjectChecks','MATLAB Project checks failed.');
    coldReport.status='PASS';
    coldReport.matlab_version=version;
    coldReport.project_checks=records;
catch coldException
    coldReport.status='FAIL';
    coldReport.error=struct('identifier',coldException.identifier,'message',coldException.message);
    writeReport(coldReportFile,coldReport);
    rethrow(coldException);
end
writeReport(coldReportFile,coldReport);
fprintf('Cold-process Flight Host SIL verification: PASS.\n');

function writeReport(file,report)
fid=fopen(file,'w');
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));
end
