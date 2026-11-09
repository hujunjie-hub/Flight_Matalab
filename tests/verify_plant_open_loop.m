function report=verify_plant_open_loop
%VERIFY_PLANT_OPEN_LOOP Run implemented Plant physics and numerical gates.
root=fileparts(fileparts(mfilename('fullpath')));
cfg=generate_parameters;
g=cfg.derived.GravityMps2;
initial=cfg.derived.PlantState0;
environment=[zeros(1,9),0,0,ones(1,4)];
contactEnvironment=environment;
contactEnvironment(10)=1;
results={};

% P-02: four equal rotor forces create only body-down force.
out=run('FMT_RotorWrench',{ones(1,4)},0.001,struct,0.0005);
wrench=out.yout{1}.Values.Data(end,:);
assert(norm(wrench-[0 0 -4 0 0 0],inf)<1e-10, ...
    'Flight:P02','Symmetric rotor wrench failed.');
results{end+1}=passed('P-02','Symmetric force and zero net torque');

% P-03: motor 1 force/torque signs come from Flight motor geometry.
out=run('FMT_RotorWrench',{[1 0 0 0]},0.001,struct,0.0005);
wrench=out.yout{1}.Values.Data(end,:);
expected=cfg.derived.WrenchMatrix(:,1)';
assert(norm(wrench-expected,inf)<1e-10, ...
    'Flight:P03','Front-left motor torque signs failed.');
results{end+1}=passed('P-03','Flight motor numbering and torque signs');

% P-04: free fall with drag and ground disabled matches the analytical solution.
out=run('FMT_QuadPlant',{zeros(1,4),environment},0.1, ...
    struct('PlantState0',initial),0.0005);
state=out.yout{1}.Values.Data(end,:);
assert(abs(state(3)-0.5*g*0.1^2)<1e-6 && abs(state(6)-g*0.1)<1e-6, ...
    'Flight:P04','Free-fall analytical solution failed.');
results{end+1}=passed('P-04','Free fall without drag/contact');

% P-05: initialized rotor speed at mg/4 must balance gravity.
hover=cfg.vehicle_model.mass_kg*g/4;
initialHover=initial;
initialHover(14:17)=sqrt(hover/cfg.derived.MotorKf);
out=run('FMT_QuadPlant',{hover*ones(1,4),environment},2, ...
    struct('PlantState0',initialHover),0.0005);
hoverState=out.yout{1}.Values.Data;
assert(max(abs(hoverState(:,4:6)),[],'all')<1e-6, ...
    'Flight:P05','Constant mg thrust did not balance gravity.');
results{end+1}=passed('P-05','Hover force with initialized motor speed');

% P-01: first-order motor response is monotonic and reaches its 5-tau bound.
out=run('FMT_QuadPlant',{5*ones(1,4),environment},1, ...
    struct('PlantState0',initial),0.0005);
omega=out.yout{1}.Values.Data(:,14:17);
assert(all(diff(omega)>=-1e-10,'all'), ...
    'Flight:P01','Motor response was not monotone.');
index=find(out.tout>=5*cfg.derived.MotorTau,1);
target=sqrt(5/cfg.derived.MotorKf);
assert(max(abs(omega(index,:)-target))/target<0.01, ...
    'Flight:P01','Motor speed failed the 5-tau bound.');
results{end+1}=passed('P-01','First-order rotor speed step');

% P-06: q and -q must represent the same physical attitude and trajectory.
rotated=initial;
rotated(7:10)=[cos(pi/6);0;0;sin(pi/6)];
rotated(11:13)=[0.3;0.2;0.1];
positive=run('FMT_QuadPlant',{zeros(1,4),environment},0.2, ...
    struct('PlantState0',rotated),0.0005);
rotated(7:10)=-rotated(7:10);
negative=run('FMT_QuadPlant',{zeros(1,4),environment},0.2, ...
    struct('PlantState0',rotated),0.0005);
pos=positive.yout{1}.Values.Data;
neg=negative.yout{1}.Values.Data;
assert(max(abs(pos(:,1:6)-neg(:,1:6)),[],'all')<1e-12 && ...
       max(abs(pos(:,7:10)+neg(:,7:10)),[],'all')<1e-12, ...
    'Flight:P06','q/-q physical equivalence failed.');
assert(max(abs(vecnorm(pos(:,7:10),2,2)-1))<1e-6, ...
    'Flight:P06','Quaternion normalization failed.');
results{end+1}=passed('P-06','Quaternion sign invariance and normalization');

% P-12: compare the 500-us Simulink Plant against an independent 250-us RK4
% reference while keeping the same input hold, environment and initial state.
stepInitial=initial;
stepInitial(7:10)=[cos(pi/6);0;0;sin(pi/6)];
stepInitial(11:13)=[0.3;0.2;0.1];
coarse=run('FMT_QuadPlant',{zeros(1,4),environment},0.5, ...
    struct('PlantState0',stepInitial),0.0005);
coarseState=coarse.yout{1}.Values.Data;
referenceState=reference_integrate(stepInitial,zeros(1,4),environment, ...
    cfg.derived,0.00025,0.5);
assert(size(coarseState,1)==size(referenceState,1), ...
    'Flight:P12','Simulink/reference Plant outputs do not share the same sample times.');
positionError=max(abs(coarseState(:,1:3)-referenceState(:,1:3)),[],'all');
quaternionDot=abs(sum(coarseState(:,7:10).*referenceState(:,7:10),2));
quaternionDot=min(1,max(0,quaternionDot));
attitudeError=max(2*acos(quaternionDot));
assert(positionError<1e-3 && attitudeError<1e-4, ...
    'Flight:P12','RK4 step-halving convergence failed: p=%g m, q=%g rad.', ...
    positionError,attitudeError);
results{end+1}=struct('id','P-12','status','PASS', ...
    'position_error_m',positionError,'attitude_error_rad',attitudeError, ...
    'reference_step_s',0.00025);

% P-13: loss of effectiveness is applied once between rotor force and rigid body.
effectState=initial;
effectState(14:17)=sqrt(5/cfg.derived.MotorKf);
effectEnvironment=environment;
effectEnvironment(12)=0.5; % MATLAB index 12 is motor 1 effectiveness.
out=run('FMT_PlantRHS',{effectState,5*ones(1,4),effectEnvironment}, ...
    0.001,struct,0.0005);
derivative=out.yout{1}.Values.Data(end,:);
expectedDownAcceleration=g-sum([2.5 5 5 5])/cfg.vehicle_model.mass_kg;
assert(abs(derivative(6)-expectedDownAcceleration)<1e-9, ...
    'Flight:P13','Rotor loss-of-effectiveness was not reflected in Plant acceleration.');
results{end+1}=passed('P-13','Rotor loss-of-effectiveness enters physical dynamics');

% P-15: a contact point 1 cm above ground has no spring/damper force,
% even while descending at 1 m/s.
aboveGround=initial;
aboveGround(3)=-0.01;
aboveGround(6)=1;
out=run('FMT_GroundRHS',{aboveGround,contactEnvironment},0.001,struct,0.0005);
assert(all(out.yout{3}.Values.Data==0,'all'), ...
    'Flight:P15','Contact damping acted above ground.');
results{end+1}=passed('P-15','No normal force above ground while descending');

% P-16: at static spring compression mg/k, total normal force balances weight.
staticContact=initial;
staticContact(3)=cfg.vehicle_model.mass_kg*g/cfg.vehicle_model.ground_stiffness_npm;
out=run('FMT_GroundRHS',{staticContact,contactEnvironment},0.001,struct,0.0005);
normalForce=out.yout{3}.Values.Data(end);
signedGap=out.yout{2}.Values.Data(end);
assert(abs(normalForce-cfg.vehicle_model.mass_kg*g)<1e-8 && signedGap<0, ...
    'Flight:P16','Static ground compression does not balance vehicle weight.');
results{end+1}=passed('P-16','Static spring compression balances gravity');

% P-11: baseline drop test must remain finite with bounded penetration.
dropState=initial;
dropState(3)=-0.1;
out=run('FMT_QuadPlant',{zeros(1,4),contactEnvironment},2, ...
    struct('PlantState0',dropState),0.0005);
gap=out.yout{3}.Values.Data;
normal=out.yout{2}.Values.Data;
assert(all(isfinite(out.yout{1}.Values.Data),'all') && ...
       all(isfinite(normal),'all') && all(normal>=0) && all(isfinite(gap),'all'), ...
    'Flight:P11','Invalid contact response.');
penetration=max(0,-min(gap));
assert(penetration<0.02, ...
    'Flight:P11','Contact penetration exceeded 2 cm: %g m.',penetration);
results{end+1}=struct('id','P-11','status','PASS','max_penetration_m',penetration);

% P-18: body-frame force rotates into fixed NED; external torque is FRD body torque.
frameState=initial;
frameState(7:10)=[cos(pi/4);0;0;sin(pi/4)];
out=run('FMT_RigidBodyRHS',{frameState,[1 0 0 0 0 0],zeros(1,6),environment}, ...
    0.001,struct,0.0005);
derivative=out.yout{1}.Values.Data(end,:);
assert(abs(derivative(4))<1e-10 && ...
       abs(derivative(5)-1/cfg.vehicle_model.mass_kg)<1e-10, ...
    'Flight:P18','FRD force was not rotated into fixed NED.');
torqueEnvironment=environment;
torqueEnvironment(7)=0.01;
out=run('FMT_RigidBodyRHS',{initial,zeros(1,6),zeros(1,6),torqueEnvironment}, ...
    0.001,struct,0.0005);
derivative=out.yout{1}.Values.Data(end,:);
assert(abs(derivative(11)-0.01/cfg.vehicle_model.inertia_frd_kgm2(1))<1e-10, ...
    'Flight:P18','FRD external torque was not applied about the body X axis.');
results{end+1}=passed('P-18','Body/NED force transform and FRD torque contract');

% P-19: aerodynamic drag uses velocity relative to NED wind.
dragState=initial;
dragState(4)=2;
windEnvironment=environment;
windEnvironment(1)=1;
windEnvironment(11)=1;
out=run('FMT_RigidBodyRHS',{dragState,zeros(1,6),zeros(1,6),windEnvironment}, ...
    0.001,struct,0.0005);
derivative=out.yout{1}.Values.Data(end,:);
expectedDrag=-cfg.vehicle_model.drag_ned_kgps(1)*(2-1)/cfg.vehicle_model.mass_kg;
assert(abs(derivative(4)-expectedDrag)<1e-10, ...
    'Flight:P19','Aerodynamic drag does not use air-relative velocity.');
results{end+1}=passed('P-19','Wind-relative linear drag');

% P-20: a non-diagonal symmetric positive-definite inertia matrix must be used
% in full, rather than silently reduced to its diagonal.
customParameters=cfg.derived.PlantParameters;
Jfull=[.03 .002 .001;.002 .04 .003;.001 .003 .05];
customParameters(2:10)=Jfull(:);
testTorque=[.1;-.2;.3];
out=run('FMT_RigidBodyRHS',{initial, [0 0 0 testTorque'], zeros(1,6),environment}, ...
    0.001,struct('PlantParameters',customParameters),0.0005);
derivative=out.yout{1}.Values.Data(end,:);
expectedAngularAcceleration=(Jfull\testTorque)';
assert(norm(derivative(11:13)-expectedAngularAcceleration,inf)<1e-9, ...
    'Flight:P20','Full non-diagonal inertia matrix was not applied correctly.');
results{end+1}=passed('P-20','Full non-diagonal inertia matrix');

% P-17: invalid environment flags/effectiveness and nonfinite states fail closed.
badEnvironment=environment;
badEnvironment(12)=1.01;
expect_error(@()run('FMT_RigidBodyRHS',{initial,zeros(1,6),zeros(1,6),badEnvironment}, ...
    0.001,struct,0.0005),'Invalid Plant Environment','Flight:P17');
badState=initial;
badState(1)=NaN;
expect_error(@()run('FMT_RigidBodyRHS',{badState,zeros(1,6),zeros(1,6),environment}, ...
    0.001,struct,0.0005),'Invalid PlantState','Flight:P17');
results{end+1}=passed('P-17','Invalid Plant inputs rejected');

remaining={'P-07','P-08','P-09','P-10','P-14'};
report=struct('scope','PLANT_COMPONENT_OPEN_LOOP', ...
    'status','PARTIAL','implemented_gate_status','PASS', ...
    'tests',{results},'remaining_tests',{remaining}, ...
    'all_P01_P20_accepted',false,'system_closed_loop','NOT_RUN', ...
    'tests_executed_count',numel(results),'gravity_mps2',g);
fid=fopen(fullfile(root,'work','validation','plant_open_loop_report.json'),'w');
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));
disp(report);
end

function out=run(model,signals,stop,variables,step)
if nargin<5, step=0.0005; end
ds=Simulink.SimulationData.Dataset;
for k=1:numel(signals)
    ds{k}=timeseries([signals{k};signals{k}],[0;stop]);
end
in=Simulink.SimulationInput(model);
in=in.setExternalInput(ds);
in=in.setModelParameter('StopTime',num2str(stop,17), ...
    'FixedStep',num2str(step,17));
names=fieldnames(variables);
for k=1:numel(names)
    in=in.setVariable(names{k},variables.(names{k}));
end
out=sim(in);
assert(abs(out.tout(end)-stop)<1e-12, ...
    'Flight:PlantEarlyStop','Plant run ended early.');
end


function states=reference_integrate(initial,command,environment,derived,step,stop)
% Independent high-resolution RK4 reference for smooth, no-contact Plant tests.
steps=round(stop/step);
assert(abs(steps*step-stop)<1e-12 && mod(steps,2)==0, ...
    'Flight:P12','Reference duration must contain an even number of fine steps.');
assert(environment(10)==0,'Flight:P12','Reference integrator is limited to no-contact cases.');
x=initial(:);
states=zeros(steps/2+1,17);
states(1,:)=x';
for k=1:steps
    k1=reference_rhs(x,command,environment,derived);
    k2=reference_rhs(x+0.5*step*k1,command,environment,derived);
    k3=reference_rhs(x+0.5*step*k2,command,environment,derived);
    k4=reference_rhs(x+step*k3,command,environment,derived);
    x=x+(step/6)*(k1+2*k2+2*k3+k4);
    qnorm=norm(x(7:10));
    assert(isfinite(qnorm) && qnorm>1e-12,'Flight:P12','Reference quaternion became invalid.');
    x(7:10)=x(7:10)/qnorm;
    if mod(k,2)==0
        states(k/2+1,:)=x';
    end
end
end

function dx=reference_rhs(x,command,environment,derived)
p=derived.PlantParameters(:);
motorMin=derived.MotorMinN(:);
motorMax=derived.MotorMaxN(:);
target=min(max(command(:),motorMin),motorMax);
omegaCommand=sqrt(target/p(11));
omega=x(14:17);
actualForce=p(11)*(omega.^2).*environment(12:15)';
wrench=derived.WrenchMatrix*actualForce;
C=reference_rotation(x(7:10));
forceNed=environment(4:6)'+C*wrench(1:3);
if environment(11)==1
    forceNed=forceNed-p(13:15).*(x(4:6)-environment(1:3)');
end

dx=zeros(17,1);
dx(1:3)=x(4:6);
dx(4:6)=forceNed/p(1)+[0;0;p(23)];
w=x(7); qx=x(8); qy=x(9); qz=x(10);
wx=x(11); wy=x(12); wz=x(13);
dx(7)=-0.5*(qx*wx+qy*wy+qz*wz);
dx(8)= 0.5*(w*wx+qy*wz-qz*wy);
dx(9)= 0.5*(w*wy+qz*wx-qx*wz);
dx(10)=0.5*(w*wz+qx*wy-qy*wx);
J=reshape(p(2:10),3,3);
jw=J*x(11:13);
gyroscopic=cross(x(11:13),jw);
dx(11:13)=J\(wrench(4:6)+environment(7:9)'-p(16)*x(11:13)-gyroscopic);
dx(14:17)=(omegaCommand-omega)/p(12);
end

function C=reference_rotation(q)
q=q(:)/norm(q);
w=q(1); x=q(2); y=q(3); z=q(4);
C=[1-2*(y*y+z*z), 2*(x*y-w*z), 2*(x*z+w*y); ...
   2*(x*y+w*z), 1-2*(x*x+z*z), 2*(y*z-w*x); ...
   2*(x*z-w*y), 2*(y*z+w*x), 1-2*(x*x+y*y)];
end

function expect_error(callback,expectedText,identifier)
failed=false;
try
    callback();
catch exception
    failed=true;
    assert(contains(exception.message,expectedText),identifier, ...
        'Unexpected failure while checking invalid input: %s',exception.message);
end
assert(failed,identifier,'Invalid Plant input was not rejected.');
end

function result=passed(id,description)
result=struct('id',id,'status','PASS','description',description);
end
