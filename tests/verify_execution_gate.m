function report=verify_execution_gate
%VERIFY_EXECUTION_GATE Simulate the actual G1 model hierarchy and boundaries.
root=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'tests','g1','models'));
models={'FMT_G1_DataSIM','FMT_G1_MILSIM','FMT_G1_ExtINS_DataSIM'};
results=cell(1,4);
for k=1:4
    if k<=3, model=models{k}; seconds=2; else, model=models{2}; seconds=60; end
    ticks=uint64(seconds*2000);
    in=Simulink.SimulationInput(model);
    in=in.setModelParameter('StopTime',num2str(seconds),'SaveFormat','Dataset');
    in=in.setVariable('stop_ticks',ticks,'Workspace','FMT_G1_ExecutionCore');
    out=sim(in);
    counts=out.yout{1}.Values.Data;
    slots=out.yout{3}.Values.Data;
    % Dimension 1 is time for vector outports saved as timeseries.
    finalCounts=reshape(counts(end,:),[],1);
    finalSlots=reshape(slots(end,:),[],1);
    expected=uint64(ceil(double(ticks)./[1;2;5;20;40;200;2000;2000]));
    assert(all(finalCounts==ticks),'Flight:PhaseCount','Incorrect function-call count.');
    assert(isequal(finalSlots,expected),'Flight:RateCount','Incorrect half-open interval count.');
    assert(isequal(counts(end,:),counts(end-1,:)),'Flight:StopBoundary','A phase executed at StopTime.');
    assert(isequal(slots(end,:),slots(end-1,:)),'Flight:StopBoundary','A rate slot executed at StopTime.');
    assert(abs(out.tout(end)-seconds)<1e-12,'Flight:EarlyStop','Simulation ended early.');
    assert(isempty(out.ErrorMessage),'Flight:SimulationError','%s',out.ErrorMessage);
    results{k}=struct('model',model,'duration_s',seconds,'status','PASS', ...
        'phase_counts',finalCounts,'rate_slot_counts',finalSlots,'stop_boundary','PASS');
end
report=struct('scope','G1_EXECUTION_TOPOLOGY','status','PASS','tests',{results}, ...
    'continuous_states',0,'flight_algorithms_implemented',false, ...
    'three_final_entries_accepted',false);
fid=fopen(fullfile(root,'work','validation','g1_execution_report.json'),'w');
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));
disp(report);
end
