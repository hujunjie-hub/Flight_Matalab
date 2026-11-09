function report=verify_pid_allocator_feedback
%VERIFY_PID_ALLOCATOR_FEEDBACK Same-tick allocation/validation is causal.
root=fileparts(fileparts(mfilename('fullpath')));
model='FMT_PIDAllocationProbe';in=Simulink.SimulationInput(model);
in=in.setModelParameter('AlgebraicLoopMsg','error');out=sim(in);
assert(all(out.yout{4}.Values.Data),'Flight:AWFeedback','Positive allocation failed.');
assert(all(isfinite(out.yout{1}.Values.Data),'all') && ...
    max(abs(out.yout{2}.Values.Data),[],'all')<=.08+1e-12,'Flight:AWFeedback','Invalid closed feedback trajectory.');
assert(out.yout{3}.Values.Data(end)>0,'Flight:AWFeedback','Numeric state never committed.');
ids=jsondecode(fileread(fullfile(root,'tests','g2','pid_feedback_probe_ids.json')));
path=Simulink.ID.getFullName([model ':' extractAfter(ids.bounds,'blk_')]);
in=Simulink.SimulationInput(model);
in=in.setModelParameter('AlgebraicLoopMsg','error');
in=in.setBlockParameter(path,'Value','[ones(4,1);zeros(4,1)]');out=sim(in);
assert(~any(out.yout{4}.Values.Data) && all(out.yout{3}.Values.Data==0),'Flight:AWFeedbackReject','Rejected allocation advanced numeric state.');
assert(all(out.yout{2}.Values.Data==0,'all'),'Flight:AWFeedbackReject','Rejected allocation polluted I.');
report=struct('scope','PID_ALLOCATOR_SAME_TRANSACTION_FEEDBACK','status','PASS', ...
    'same_tick_residual_and_validation','PASS','no_algebraic_loop','PASS','failed_allocation_no_commit','PASS');
fid=fopen(fullfile(root,'work','validation','pid_allocator_feedback_report.json'),'w');cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));disp(report);
end
