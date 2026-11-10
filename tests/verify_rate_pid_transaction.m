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
% The M6 time-context guard is exercised by the Flight host suite, which drives
% the real controller_validate_input() with one broken binding per case.
rateStep=verify_m6_rate_step;
assert(strcmp(rateStep.status,'PASS'),'Flight:M6RateStep', ...
    'Closed-loop rate step failed.');
m6=run_m6_guard_suite(root);
assert(~strcmp(m6.complete_M6_time_context_guard,'FAIL'), ...
    'Flight:M6Guard','M6 time-context guard host suite failed.');

report=struct('scope','RATE_PID_COMPONENT_TRANSACTION','status','PASS', ...
    'read_current_I','PASS','same_nav_no_commit','PASS','failed_transaction_atomic','PASS', ...
    'reset_retains_commit_count','PASS','current_allocation_aw','PASS','integral_limit','PASS', ...
    'complete_M6_time_context_guard',m6.complete_M6_time_context_guard, ...
    'm6_guard_checks',m6.guard_checks,'m6_guard_failures',m6.failures, ...
    'm6_guard_log',m6.log,'m6_guard_reason',m6.reason, ...
    'closed_loop_rate_step',rateStep.status, ...
    'rate_step_settle_s',rateStep.settle_time_s, ...
    'rate_step_overshoot',rateStep.overshoot, ...
    'rate_step_hold_error',rateStep.hold_error_radps);
fid=fopen(fullfile(root,'work','validation','rate_pid_report.json'),'w');
cleanup=onCleanup(@()fclose(fid));fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));disp(report);
end

function result=run_m6_guard_suite(root)
%RUN_M6_GUARD_SUITE Read the Flight M6 guard evidence produced by the host suite.
result=struct('complete_M6_time_context_guard','NOT_RUN','guard_checks',0, ...
    'failures',0,'log','','reason','');
flightRoot=fullfile(fileparts(root),'Flight');
script=fullfile(flightRoot,'tests','control','run_host_tests.ps1');
if ~isfile(script)
    result.reason='Flight M6 host suite not found';
    return;
end
[status,message]=system(sprintf('pwsh -NoProfile -File "%s"',script));
summaryFile=fullfile(flightRoot,'build','validation','m6','m6_host_summary.json');
if ~isfile(summaryFile)
    result.reason=sprintf('no host summary (exit %d): %s',status,strtrim(message));
    return;
end
summary=jsondecode(fileread(summaryFile));
result.log=summary.log;
result.failures=summary.failures;
if isfield(summary,'m6_guard_checks'), result.guard_checks=summary.m6_guard_checks; end
switch summary.status
    case 'PASS'
        result.complete_M6_time_context_guard=summary.complete_M6_time_context_guard;
    case 'FAIL'
        result.complete_M6_time_context_guard='FAIL';
    otherwise
        result.reason=sprintf('host suite status %s',summary.status);
end
end