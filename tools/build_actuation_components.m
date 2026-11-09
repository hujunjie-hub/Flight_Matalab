function build_actuation_components
%BUILD_ACTUATION_COMPONENTS Build pure allocation and code/packet components.
root=fileparts(fileparts(mfilename('fullpath')));
for file={'fmt_x4_allocate_sfun','fmt_frame_encode_sfun'}
    mex('-R2018a','-silent',fullfile(root,'models','core',[file{1} '.c']),'-outdir',fullfile(root,'work','mex'));
end
make(root,'FMT_X4_ControlAllocation','fmt_x4_allocate_sfun','AllocationGeometry', ...
    {'RequestedWrench','ForceBounds'},[4 8], ...
    {'AllocatedForceN','AllocatedWrench','TorqueResidualNm','RollPitchScale','AllocationValid'});
make(root,'FMT_M7_FrameQuantizer','fmt_frame_encode_sfun','FrameQuantizerParameters', ...
    {'DemandForceN','LastCommittedForceN','FrameIntervalS'},[4 4 1], ...
    {'DshotCodes','DshotPackets','CodeRestoredForceN','QuantizationValid'});
end

function make(root,model,sfun,parameters,inputs,widths,outputs)
assert(~bdIsLoaded(model)&&~isfile(fullfile(root,'models','core',[model '.slx'])),'Flight:Exists','Actuation component already exists.');
new_system(model);open_system(model);save_system(model,fullfile(root,'models','core',[model '.slx']));
ops={struct('op','configure','target',['config:' model],'params',struct('SolverType','Fixed-step', ...
    'Solver','FixedStepDiscrete','FixedStep','auto','EnableMultiTasking','off','DataDictionary','Flight_Parameters.sldd', ...
    'SaveFormat','Dataset','ReturnWorkspaceOutputs','on','StopTime','2', ...
    'Description','Pure SIM_ONLY numerical component; lifecycle/Permit validation is a separate M6/M7 boundary.')), ...
    struct('op','add_block','type','S-Function','name','BoundedNumericalKernel','ref','kernel', ...
    'params',struct('Parameters',parameters,'FunctionName',sfun))};
for k=1:numel(inputs)
    ref=sprintf('u%d',k);
    ops{end+1}=struct('op','add_block','type','Inport','name',inputs{k},'ref',ref,'params',struct('Port',num2str(k),'PortDimensions',num2str(widths(k)),'OutDataTypeStr','double'));
    ops{end+1}=struct('op','connect','target',sprintf('#%s.y1 -> #kernel.u%d',ref,k));
end
for k=1:numel(outputs)
    ref=sprintf('y%d',k);
    ops{end+1}=struct('op','add_block','type','Outport','name',outputs{k},'ref',ref,'params',struct('Port',num2str(k)));
    ops{end+1}=struct('op','connect','target',sprintf('#kernel.y%d -> #%s.u1',k,ref));
end
fmt_edit(model,'root',ops);
result=char(model_check(model,'root','["all"]'));assert(contains(result,'status: healthy'),'Flight:ActuationStructure','%s',result);
save_system(model);
end
