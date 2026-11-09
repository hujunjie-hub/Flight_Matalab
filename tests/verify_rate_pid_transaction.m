function report=verify_rate_pid_transaction
%VERIFY_RATE_PID_TRANSACTION Verify actual native block state transactions.
root=fileparts(fileparts(mfilename('fullpath')));
t=(0:7)'*.001;
desired=repmat([1 0 0],8,1);measured=zeros(8,3);measured(4,1)=.5;
dt=.001*ones(8,1);dt([1 3 6 8])=0;
numeric=logical([0 1 0 1 1 0 1 0]');
reset=logical([1 0 0 0 0 1 0 0]');
valid=true(8,1);valid(4)=false;
ds=Simulink.SimulationData.Dataset;
data={desired,measured,dt,numeric,reset,valid,zeros(8,3)};
for k=1:7,ds{k}=timeseries(data{k},t);end
in=Simulink.SimulationInput('FMT_RatePIDTransaction');in=in.setExternalInput(ds);
in=in.setModelParameter('StopTime','0.007','FixedStep','0.001');out=sim(in);
tau=out.yout{1}.Values.Data;integral=out.yout{2}.Values.Data;derivative=out.yout{3}.Values.Data;count=out.yout{4}.Values.Data;
assert(abs(tau(2,1)-.16)<1e-12,'Flight:PIDOrder','Torque used next integral instead of current integral.');
assert(abs(integral(3,1)-.00008)<1e-12,'Flight:PIDCommit','Numeric integral was not committed once.');
assert(integral(4,1)==integral(3,1) && count(4)==count(3),'Flight:PIDDuplicate','Same-Nav evaluation changed state.');
assert(integral(5,1)==integral(4,1) && count(5)==count(4),'Flight:PIDRejected','Rejected transaction changed state.');
assert(abs(tau(5,1)-(.16+.00008))<1e-12 && all(derivative==0,'all'),'Flight:PIDHistory','Rejected measurement polluted derivative history.');
assert(abs(tau(6,1)-.16)<1e-12 && integral(7,1)==0 && count(7)==2,'Flight:PIDReset','Context reset or high-watermark preservation failed.');
assert(abs(integral(8,1)-.00008)<1e-12 && count(8)==3,'Flight:PIDResume','Numeric commit after reset failed.');

t=(0:2000)'*.001;N=numel(t);
ds=Simulink.SimulationData.Dataset;
data={ones(N,3),zeros(N,3),.001*ones(N,1),true(N,1),[true;false(N-1,1)],true(N,1),repmat([-.016 -.016 -.016],N,1)};
for k=1:7,ds{k}=timeseries(data{k},t);end
in=Simulink.SimulationInput('FMT_RatePIDTransaction');in=in.setExternalInput(ds);
in=in.setModelParameter('StopTime','2','FixedStep','0.001');out=sim(in);
integral=out.yout{2}.Values.Data;
assert(max(abs(integral(:,1:2)),[],'all')<1e-12,'Flight:PIDAW','Current allocation residual did not cancel integral error.');
assert(max(abs(integral(:,3)))<=.05+1e-12,'Flight:PIDLimit','Integral exceeded physical Nm limit.');
report=struct('scope','RATE_PID_COMPONENT_TRANSACTION','status','PASS', ...
    'read_current_I','PASS','same_nav_no_commit','PASS','failed_transaction_atomic','PASS', ...
    'reset_retains_commit_count','PASS','current_allocation_aw','PASS','integral_limit','PASS', ...
    'complete_M6_time_context_guard','NOT_RUN','closed_loop_rate_step','NOT_RUN');
fid=fopen(fullfile(root,'work','validation','rate_pid_report.json'),'w');
cleanup=onCleanup(@()fclose(fid));fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));disp(report);
end
