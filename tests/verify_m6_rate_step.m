function report=verify_m6_rate_step
%VERIFY_M6_RATE_STEP Closed-loop 0.5 rad/s rate step on the real rate PID block.
%   Builds a throw-away MIL fixture around the contents of
%   models/core/FMT_RatePIDTransaction.slx (the real rate controller) and a
%   single-axis rigid body, then measures settling, overshoot and hold.
%   The fixture lives under work/ so it never enters the repository.
root=flight_startup;
cfg=generate_parameters;
inertia=cfg.vehicle_model.inertia_frd_kgm2;
Jm=reshape(inertia,3,3);
Jdiag=diag(Jm);
J=Jdiag(1);
damping=0.01;
command=0.5;
settleBand=0.05*command;
stepTime=0.1;
stopTime=3.8;

source='FMT_RatePIDTransaction';
load_system(fullfile(root,'models','core',[source '.slx']));
fixture='FMT_M6RateStep';
if bdIsLoaded(fixture), close_system(fixture,0); end
fixtureFile=fullfile(root,'work','models',[fixture '.slx']);
if isfile(fixtureFile), delete(fixtureFile); end
new_system(fixture);
cleanup=onCleanup(@()close_system(fixture,0));
% The rate PID block parameters are expressions over the derived parameter
% set (e.g. RateKaw), which the fixture has to publish like the real models do.
derivedNames=fieldnames(cfg.derived);
for k=1:numel(derivedNames)
    assignin('base',derivedNames{k},cfg.derived.(derivedNames{k}));
end

% A blank library Subsystem still carries a default inport/outport pair, and
% copyContentsToSubsystem only accepts a target with no blocks at all.
add_block('built-in/Subsystem',[fixture '/RatePID'],'Position',[260 100 400 300]);
Simulink.BlockDiagram.copyContentsToSubsystem(source,[fixture '/RatePID']);

add_block('simulink/Sources/Step',[fixture '/OmegaCmd'],'Time',num2str(stepTime), ...
    'Before','[0 0 0]','After',mat2str([command 0 0]),'Position',[20 100 60 130]);
add_block('simulink/Sources/Constant',[fixture '/Dt'],'Value','0.001', ...
    'Position',[20 160 60 190]);
add_block('simulink/Sources/Constant',[fixture '/Numeric'],'Value','true', ...
    'Position',[20 210 60 240]);
% ResetTransaction is boolean; derive it from the clock instead of a Step block,
% which cannot emit logical values.
add_block('simulink/Sources/Clock',[fixture '/Clock'],'Position',[20 255 60 275]);
add_block('simulink/Sources/Constant',[fixture '/ResetLimit'],'Value','0.001', ...
    'Position',[20 285 60 315]);
add_block('simulink/Logic and Bit Operations/Relational Operator', ...
    [fixture '/ResetPulse'],'Operator','<','Position',[110 260 160 300]);
add_block('simulink/Sources/Constant',[fixture '/Validated'],'Value','true', ...
    'Position',[20 310 60 340]);
add_block('simulink/Sources/Constant',[fixture '/Residual'],'Value','[0 0 0]', ...
    'Position',[20 360 60 390]);

add_block('simulink/Math Operations/Sum',[fixture '/TorqueSum'],'Inputs','+-', ...
    'Position',[470 130 490 170]);
add_block('simulink/Math Operations/Gain',[fixture '/Damping'],'Gain',num2str(damping), ...
    'Position',[470 200 510 230],'Orientation','left');
add_block('simulink/Math Operations/Gain',[fixture '/Inertia'], ...
    'Gain',mat2str((1./Jdiag)',6),'Multiplication','Element-wise(K.*u)', ...
    'Position',[540 130 580 170]);
add_block('simulink/Continuous/Integrator',[fixture '/Omega'], ...
    'InitialCondition','[0 0 0]','Position',[620 130 660 170]);
add_block('simulink/Sinks/Out1',[fixture '/OmegaOut'],'Position',[720 140 750 160]);
add_block('simulink/Sinks/Out1',[fixture '/TorqueOut'],'Position',[460 60 490 80]);

add_line(fixture,'OmegaCmd/1','RatePID/1','autorouting','on');
add_line(fixture,'Omega/1','RatePID/2','autorouting','on');
add_line(fixture,'Dt/1','RatePID/3','autorouting','on');
add_line(fixture,'Numeric/1','RatePID/4','autorouting','on');
add_line(fixture,'Clock/1','ResetPulse/1','autorouting','on');
add_line(fixture,'ResetLimit/1','ResetPulse/2','autorouting','on');
add_line(fixture,'ResetPulse/1','RatePID/5','autorouting','on');
add_line(fixture,'Validated/1','RatePID/6','autorouting','on');
add_line(fixture,'Residual/1','RatePID/7','autorouting','on');
add_line(fixture,'RatePID/1','TorqueSum/1','autorouting','on');
add_line(fixture,'RatePID/1','TorqueOut/1','autorouting','on');
add_line(fixture,'Omega/1','Damping/1','autorouting','on');
add_line(fixture,'Damping/1','TorqueSum/2','autorouting','on');
add_line(fixture,'TorqueSum/1','Inertia/1','autorouting','on');
add_line(fixture,'Inertia/1','Omega/1','autorouting','on');
add_line(fixture,'Omega/1','OmegaOut/1','autorouting','on');

set_param(fixture,'StopTime',num2str(stopTime),'FixedStep','0.001', ...
    'Solver','ode1','SaveOutput','on','SaveFormat','StructureWithTime');
out=sim(fixture);
omega=out.get('yout');
time=omega.time;
values=omega.signals(1).values(:,1);
torque=omega.signals(2).values(:,1);

after=time>=stepTime;
settleIndex=find(after & abs(values-command)>settleBand,1,'last');
if isempty(settleIndex)
    settleTime=0;
else
    settleTime=time(settleIndex)-stepTime;
end
peak=max(values(after));
overshoot=max(0,(peak-command)/command);
holdStart=stepTime+1.5;
holdWindow=time>=holdStart;
holdError=max(abs(values(holdWindow)-command));

report=struct('scope','M6_RATE_STEP_CLOSED_LOOP','status','PASS', ...
    'command_radps',command,'inertia_kgm2',J,'damping_nm_per_radps',damping, ...
    'settle_time_s',settleTime,'overshoot',overshoot,'hold_error_radps',holdError, ...
    'torque_peak_nm',max(abs(torque)));
assert(~isempty(settleIndex) && settleTime<=1.5,'Flight:M6RateStep', ...
    'Rate step did not settle within 1.5 s (settle %.3f s).',settleTime);
assert(overshoot<=0.30,'Flight:M6RateStep','Rate step overshoot %.3f exceeds 30%.',overshoot);
assert(holdError<=settleBand,'Flight:M6RateStep', ...
    'Rate step did not hold within 5%% (error %.4f rad/s).',holdError);
file=fullfile(root,'work','validation','m6_rate_step_report.json');
fid=fopen(file,'w'); fileCleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));
fprintf('rate step: settle=%.3f s overshoot=%.3f hold_err=%.4f\n', ...
    settleTime,overshoot,holdError);
end
