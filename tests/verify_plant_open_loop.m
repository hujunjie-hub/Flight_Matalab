function report=verify_plant_open_loop
%VERIFY_PLANT_OPEN_LOOP Run implemented Plant physics and numerical gates.
root=flight_startup;
cfg=generate_parameters;
sensorModelFile=fullfile(root,'models','plant','FMT_PlantSensors.slx');
assert(isfile(sensorModelFile),'Flight:SensorModel', ...
    'Run build_plant_models(8) to create FMT_PlantSensors before Plant verification.');
load_system(sensorModelFile);
g=cfg.derived.GravityMps2;
initial=cfg.derived.PlantState0;
environment=[zeros(1,9),0,0,ones(1,4)];
contactEnvironment=environment;
contactEnvironment(10)=1;
quietSensorModelParameters=cfg.derived.SensorModelParameters;
quietSensorModelParameters(20:37)=0;
quietSensorModelParameters(38:54)=0;
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

% P-07: nonzero IMU and GNSS antenna lever arms follow rigid-body point kinematics.
% Earth rate is zeroed in this isolated geometry test; P-08 verifies it separately.
sensorParameters=cfg.derived.SensorParameters;
sensorParameters(5:7)=0;
sensorParameters(14:16)=[0.10;0;0];  % IMU->CG; CG->IMU is the negative vector.
sensorParameters(17:19)=[0.20;0;0];  % IMU->GNSS antenna.
rotationRate=2.0;
profileInitial=initial;
profileInitial(1:6)=0;
profileInitial(7:10)=[1;0;0;0];
profileInitial(11:13)=[0;0;rotationRate];
profileTimes=(0:0.0005:0.02)';
profileStates=repmat(profileInitial',numel(profileTimes),1);
for k=1:numel(profileTimes)
    angle=rotationRate*profileTimes(k);
    profileStates(k,7:10)=[cos(angle/2),0,0,sin(angle/2)];
end
profileGap=ones(size(profileTimes));
sensorRun=run_profile('FMT_PlantSensors',{profileStates,profileGap},profileTimes, ...
    profileTimes(end),struct('SensorParameters',sensorParameters, ...
    'SensorModelParameters',quietSensorModelParameters),0.0005);
sensorFrame=sensorRun.yout{1}.Values.Data(end,:);
leverImu=-sensorParameters(14:16);
leverAntenna=leverImu+sensorParameters(17:19);
omegaBody=[0;0;rotationRate];
expectedImuAcceleration=cross(omegaBody,cross(omegaBody,leverImu));
finalRotation=reference_rotation(profileStates(end,7:10));
expectedAntennaPosition=profileStates(end,1:3)'+finalRotation*leverAntenna;
expectedAntennaVelocity=profileStates(end,4:6)'+finalRotation*cross(omegaBody,leverAntenna);
assert(norm(sensorFrame(4:6)'-[expectedImuAcceleration(1);expectedImuAcceleration(2); ...
    expectedImuAcceleration(3)-g],inf)<1e-6 && ...
    norm(sensorFrame(7:9)'-expectedAntennaPosition,inf)<1e-6 && ...
    norm(sensorFrame(10:12)'-expectedAntennaVelocity,inf)<1e-6, ...
    'Flight:P07','IMU/antenna lever-arm kinematics differ from rigid-body reference.');
results{end+1}=passed('P-07','IMU acceleration and GNSS antenna position/velocity lever arms');

% P-08: a stationary level IMU reports specific force -g on body Z and Earth rate.
staticState=initial;
staticState(1:6)=0;
staticState(7:10)=[1;0;0;0];
staticState(11:13)=0;
staticRun=run('FMT_PlantSensors',{staticState,1},0.001, ...
    struct('SensorModelParameters',quietSensorModelParameters),0.0005);
staticFrame=staticRun.yout{1}.Values.Data(end,:);
assert(abs(staticFrame(4))<1e-10 && abs(staticFrame(5))<1e-10 && ...
       abs(staticFrame(6)+g)<1e-10 && ...
       norm(staticFrame(1:3)'-cfg.derived.EarthRateNedRadps,inf)<1e-12 && ...
       bitand(uint32(staticFrame(17)),uint32(1))==1, ...
    'Flight:P08','Static IMU specific force or fixed-N0 Earth-rate term is incorrect.');
movingParameters=cfg.derived.SensorParameters;
movingParameters(8:10)=[1;0;0]; % Match the initial NED velocity to avoid a synthetic derivative impulse.
movingState=staticState;
movingState(4:6)=[1;0;0];
movingRun=run('FMT_PlantSensors',{movingState,1},0.001, ...
    struct('SensorParameters',movingParameters, ...
    'SensorModelParameters',quietSensorModelParameters),0.0005);
movingFrame=movingRun.yout{1}.Values.Data(end,:);
expectedCoriolis=2*cross(cfg.derived.EarthRateNedRadps,[1;0;0]);
assert(norm(movingFrame(1:3)'-cfg.derived.EarthRateNedRadps,inf)<1e-12 && ...
       norm(movingFrame(4:6)'-[expectedCoriolis(1);expectedCoriolis(2);-g],inf)<1e-10, ...
    'Flight:P08','Fixed-N0 Earth-rate or Coriolis compensation is incorrect.');
results{end+1}=passed('P-08','Static specific force, Earth-rate gyro and Coriolis compensation');

% P-09: seeded sensor noise is repeatable, independent by axis and has the configured STD.
noiseTimes=(0:0.0005:10)';
noiseStates=repmat(staticState',numel(noiseTimes),1);
noiseParameters=cfg.derived.SensorModelParameters;
noiseRunA=run_profile('FMT_PlantSensors',{noiseStates,ones(size(noiseTimes))}, ...
    noiseTimes,noiseTimes(end),struct('SensorParameters',cfg.derived.SensorParameters, ...
    'SensorModelParameters',noiseParameters),0.0005);
noiseRunB=run_profile('FMT_PlantSensors',{noiseStates,ones(size(noiseTimes))}, ...
    noiseTimes,noiseTimes(end),struct('SensorParameters',cfg.derived.SensorParameters, ...
    'SensorModelParameters',noiseParameters),0.0005);
noiseDataA=noiseRunA.yout{1}.Values.Data;
noiseDataB=noiseRunB.yout{1}.Values.Data;
assert(isequaln(noiseDataA,noiseDataB), ...
    'Flight:P09','Identical random seeds did not reproduce the sensor sequence.');
noiseParametersOther=noiseParameters;
noiseParametersOther(1)=noiseParametersOther(1)+1;
noiseRunOther=run_profile('FMT_PlantSensors',{noiseStates,ones(size(noiseTimes))}, ...
    noiseTimes,noiseTimes(end),struct('SensorParameters',cfg.derived.SensorParameters, ...
    'SensorModelParameters',noiseParametersOther),0.0005);
noiseDataOther=noiseRunOther.yout{1}.Values.Data;
assert(max(abs(noiseDataA(:)-noiseDataOther(:)))>0, ...
    'Flight:P09','Changing the seed did not change the sensor noise sequence.');

% Take one sample per 1 kHz IMU epoch; the 500-us Plant calls must not
% create extra independent IMU noise samples.
sampleRows=3:2:numel(noiseTimes);
gyroResidual=noiseDataA(sampleRows,1:3)- ...
    repmat(cfg.derived.EarthRateNedRadps',numel(sampleRows),1);
accelResidual=noiseDataA(sampleRows,4:6)- ...
    repmat([0 0 -g],numel(sampleRows),1);
for axis=1:3
    assert(within_chi_square95(gyroResidual(:,axis),noiseParameters(38+axis-1)) && ...
           within_chi_square95(accelResidual(:,axis),noiseParameters(41+axis-1)), ...
        'Flight:P09','IMU noise STD fell outside the 95%% chi-square interval on axis %d.',axis);
end
gyroCorrelation=corrcoef(gyroResidual);
assert(max(abs(gyroCorrelation([2 3 6])))<0.05, ...
    'Flight:P09','Independent gyro axes show excessive sample correlation.');

% Bias and scale errors are residuals after the M2 calibration boundary.
biasScaleParameters=quietSensorModelParameters;
biasScaleParameters(20:22)=[0.01;-0.02;0.03];
biasScaleParameters(23:25)=[0.10;-0.20;0.30];
biasScaleParameters(26:28)=[0.40;-0.30;0.20];
biasScaleParameters(29:31)=[0.01;-0.02;0.03];
biasScaleParameters(32:34)=[-0.01;0.02;0.03];
biasScaleParameters(35:37)=[0.02;0.01;-0.01];
biasRun=run('FMT_PlantSensors',{staticState,1},0.001, ...
    struct('SensorModelParameters',biasScaleParameters),0.0005);
biasFrame=biasRun.yout{1}.Values.Data(end,:);
expectedGyro=cfg.derived.EarthRateNedRadps.*(1+biasScaleParameters(29:31))+ ...
    biasScaleParameters(20:22);
expectedAccel=[0;0;-g].*(1+biasScaleParameters(32:34))+biasScaleParameters(23:25);
expectedMag=cfg.derived.MagneticFieldNedUt.*(1+biasScaleParameters(35:37))+ ...
    biasScaleParameters(26:28);
assert(norm(biasFrame(1:3)'-expectedGyro,inf)<1e-9 && ...
       norm(biasFrame(4:6)'-expectedAccel,inf)<1e-9 && ...
       norm(biasFrame(13:15)'-expectedMag,inf)<1e-9, ...
    'Flight:P09','Configured sensor bias/scale errors were not applied in the sensor frame.');
badSensorModel=quietSensorModelParameters;
badSensorModel(38)=-0.01;
expect_error(@()run('FMT_PlantSensors',{staticState,1},0.001, ...
    struct('SensorModelParameters',badSensorModel),0.0005), ...
    'Sensor parameters contain nonfinite or physically invalid values.','Flight:P09');
results{end+1}=passed('P-09','Seeded repeatable Gaussian noise, axis independence, bias/scale injection and invalid-config rejection');

% P-10a: physical sample/capture/arrival and fixed-step firmware release are distinct.
sensorTimingReport=verify_sensor_event_timing(cfg);
results{end+1}=passed('P-10a','Multi-rate sample/capture/arrival/release queue, counters and missing-sample sequence gaps');

% P-12: compare 5 s of 500-us Simulink RK4 against an independent 250-us RK4
% reference while keeping command, environment and initial state identical.
stepInitial=initial;
stepInitial(7:10)=[cos(pi/6);0;0;sin(pi/6)];
stepInitial(11:13)=[0;0;0.3];
hoverCommand=cfg.vehicle_model.mass_kg*g/4;
stepInitial(14:17)=sqrt(hoverCommand/cfg.derived.MotorKf);
coarse=run('FMT_QuadPlant',{hoverCommand*ones(1,4),environment},5.0, ...
    struct('PlantState0',stepInitial),0.0005);
coarseState=coarse.yout{1}.Values.Data;
referenceState=reference_integrate(stepInitial,hoverCommand*ones(1,4),environment, ...
    cfg.derived,0.00025,5.0);
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
externalForceEnvironment=environment;
externalForceEnvironment(4)=1.25; % NED north force in newtons.
out=run('FMT_RigidBodyRHS',{initial,zeros(1,6),zeros(1,6),externalForceEnvironment}, ...
    0.001,struct,0.0005);
derivative=out.yout{1}.Values.Data(end,:);
assert(abs(derivative(4)-1.25/cfg.vehicle_model.mass_kg)<1e-10, ...
    'Flight:P13','External NED force did not enter rigid-body translation.');
results{end+1}=passed('P-13','Rotor effectiveness and external force enter physical dynamics');

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
contactWrench=out.yout{1}.Values.Data(end,:);
assert(abs(normalForce-cfg.vehicle_model.mass_kg*g)<1e-8 && signedGap<0 && ...
       norm(contactWrench(4:6),inf)<1e-8, ...
    'Flight:P16','Static ground compression does not balance weight or creates a net contact torque.');
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
Jflight=reshape(cfg.vehicle_model.inertia_frd_kgm2,3,3);
expectedTorqueAcceleration=Jflight\[0.01;0;0];
assert(norm(derivative(11:13)-expectedTorqueAcceleration',inf)<1e-10, ...
    'Flight:P18','FRD external torque was not applied using the full inertia matrix.');
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
% in both angular momentum and the gyroscopic term, not reduced to its diagonal.
customParameters=cfg.derived.PlantParameters;
Jfull=[.03 .002 .001;.002 .04 .003;.001 .003 .05];
customParameters(2:10)=Jfull(:);
angularState=initial;
angularState(11:13)=[0.3;0.2;0.1];
testTorque=[.1;-.2;.3];
out=run('FMT_RigidBodyRHS',{angularState, [0 0 0 testTorque'], zeros(1,6),environment}, ...
    0.001,struct('PlantParameters',customParameters),0.0005);
derivative=out.yout{1}.Values.Data(end,:);
omega=angularState(11:13);
expectedAngularAcceleration=Jfull\(testTorque- ...
    cfg.derived.PlantParameters(16)*omega-cross(omega,Jfull*omega));
assert(norm(derivative(11:13)-expectedAngularAcceleration,inf)<1e-9, ...
    'Flight:P20','Full inertia/gyroscopic coupling was not applied correctly.');
results{end+1}=passed('P-20','Full non-diagonal inertia and gyroscopic coupling');

% P-17: first-version contact has no horizontal friction, even while sliding.
staticContact=cfg.derived.PlantState0;
staticContact(3)=cfg.vehicle_model.mass_kg*g/cfg.vehicle_model.ground_stiffness_npm;
staticContact(4)=1;
out=run('FMT_GroundRHS',{staticContact,contactEnvironment},0.001,struct,0.0005);
wrench=out.yout{1}.Values.Data(end,:);
expectedNormal=cfg.vehicle_model.mass_kg*g;
assert(norm(wrench-[0 0 -expectedNormal 0 0 0],inf)<1e-8, ...
    'Flight:P17','First-version Plant unexpectedly applied horizontal ground friction.');
results{end+1}=passed('P-17','No horizontal ground friction in first-version Plant');

% P-21: invalid environment flags/effectiveness, states and inertia fail closed.
badEnvironment=environment;
badEnvironment(12)=1.01;
expect_error(@()run('FMT_RigidBodyRHS',{initial,zeros(1,6),zeros(1,6),badEnvironment}, ...
    0.001,struct,0.0005),'Invalid Plant Environment','Flight:P21');
badFlagEnvironment=environment;
badFlagEnvironment(10)=0.5;
expect_error(@()run('FMT_RigidBodyRHS',{initial,zeros(1,6),zeros(1,6),badFlagEnvironment}, ...
    0.001,struct,0.0005),'Invalid Plant Environment','Flight:P21');
badState=initial;
badState(1)=NaN;
expect_error(@()run('FMT_RigidBodyRHS',{badState,zeros(1,6),zeros(1,6),environment}, ...
    0.001,struct,0.0005),'Invalid PlantState','Flight:P21');
badState=initial;
badState(14)=-1;
expect_error(@()run('FMT_RigidBodyRHS',{badState,zeros(1,6),zeros(1,6),environment}, ...
    0.001,struct,0.0005),'Invalid PlantState','Flight:P21');
badParameters=cfg.derived.PlantParameters;
badParameters(3)=badParameters(3)+0.01; % Break J21/J12 symmetry.
expect_error(@()run('FMT_RigidBodyRHS',{initial,zeros(1,6),zeros(1,6),environment}, ...
    0.001,struct('PlantParameters',badParameters),0.0005), ...
    'Invalid PlantParameters','Flight:P21');
badParameters=cfg.derived.PlantParameters;
badParameters(2)=-badParameters(2); % Negative J11 violates positive definiteness.
expect_error(@()run('FMT_RigidBodyRHS',{initial,zeros(1,6),zeros(1,6),environment}, ...
    0.001,struct('PlantParameters',badParameters),0.0005), ...
    'Invalid PlantParameters','Flight:P21');
results{end+1}=passed('P-21','Invalid environment, state and inertia rejected');

implemented=cellfun(@(item)item.id,results,'UniformOutput',false);
remaining={'P-10b_PPS_UTC_EPOCH_MAPPING'};
coverage=struct('status','PARTIAL','implemented_tests',{implemented}, ...
    'remaining_tests',{remaining},'implemented_count',numel(results), ...
    'required_plant_test_count',21);
report=struct('scope','PLANT_COMPONENT_OPEN_LOOP', ...
    'status','PARTIAL','implemented_gate_status','PASS', ...
    'tests',{results},'coverage',coverage,'remaining_tests',{remaining}, ...
    'sensor_timing',sensorTimingReport, ...
    'all_plant_P01_P09_P10a_P11_P13_P15_P21_accepted',true, ...
    'P10b_pps_utc_epoch_mapping','NOT_IMPLEMENTED','truth_isolation_P14','SEPARATE_GATE', ...
    'system_closed_loop','NOT_RUN', ...
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
    sample=reshape(signals{k},1,[]);
    ds{k}=timeseries([sample;sample],[0;stop]);
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


function out=run_profile(model,signals,times,stop,variables,step)
ds=Simulink.SimulationData.Dataset;
for k=1:numel(signals)
    ds{k}=timeseries(signals{k},times);
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
    'Flight:PlantEarlyStop','Sensor kinematics run ended early.');
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

function ok=within_chi_square95(samples,sigma)
n=numel(samples);
if n<100 || ~(sigma>0), ok=false; return; end
degrees=n-1;
chi_square=sum((samples-mean(samples)).^2)/(sigma^2);
z=1.95996398454005;
lower=degrees*(1-2/(9*degrees)-z*sqrt(2/(9*degrees)))^3;
upper=degrees*(1-2/(9*degrees)+z*sqrt(2/(9*degrees)))^3;
ok=chi_square>=lower && chi_square<=upper;
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
