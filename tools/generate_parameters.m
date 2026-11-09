function cfg=generate_parameters
%GENERATE_PARAMETERS Build a checked SIM_ONLY view from Flight-owned parameters.
root=fileparts(fileparts(mfilename('fullpath')));
folder=fullfile(root,'config','SIM_ONLY','QUAD_X4');
names={'vehicle_model','sensor_alignment','estimator_tuning','controller_tuning','profile_manifest'};
cfg=struct;
for k=1:numel(names)
    if k==5, ext='.json'; else, ext='.yaml'; end
    cfg.(names{k})=jsondecode(fileread(fullfile(folder,[names{k} ext])));
    assert(strcmp(cfg.(names{k}).status,'SIM_ONLY'),'Flight:Profile', ...
        'Only the explicit synthetic fixture is supported.');
end

% Flight owns rigid-body and actuator geometry. This project owns only the
% simulation-only aerodynamic, motor-thrust and contact approximations.
simVehicle=cfg.vehicle_model;
v=simVehicle;
profile=cfg.profile_manifest;
estimator=cfg.estimator_tuning;
flight=jsondecode(fileread(fullfile(root,'..','Flight','config','vehicle_model.yaml')));
assert(strcmp(flight.profile,'QUAD_X4') && strcmp(flight.status,'SIM_ONLY'), ...
    'Flight:PlantProfile','Expected the Flight SIM_ONLY QUAD_X4 vehicle.');

vehicleFields={'mass_kg','inertia_frd_kgm2','motor_position_frd_m', ...
    'motor_yaw_torque_ratio_m','motor_min_thrust_n','motor_max_thrust_n'};
for k=1:numel(vehicleFields)
    field=vehicleFields{k};
    assert(isfield(flight,field),'Flight:VehicleField','Flight vehicle field %s is missing.',field);
    v.(field)=flight.(field);
end
assert(isfield(flight,'motor_time_constant_s') && numel(flight.motor_time_constant_s)==4, ...
    'Flight:MotorDynamics','Flight must define four motor time constants.');
assert(all(isfinite(flight.motor_time_constant_s)) && ...
       all(flight.motor_time_constant_s>0) && ...
       max(flight.motor_time_constant_s)-min(flight.motor_time_constant_s)<1e-12, ...
    'Flight:MotorDynamics','The current plant requires a shared positive motor time constant.');
v.motor_time_constant_s=flight.motor_time_constant_s(1);

position=flight.motor_position_frd_m';
assert(isequal(size(position),[3 4]) && all(isfinite(position),'all'), ...
    'Flight:MotorGeometry','Expected four finite FRD motor positions.');
assert(max(abs(mean(position(1:2,:),2)))<1e-10 && ...
       max(abs(position(3,:)))<1e-10, ...
    'Flight:MotorGeometry','The X4 layout must be centered in the FRD x-y plane.');
radial=hypot(position(1,:),position(2,:));
armLength=mean(radial);
assert(armLength>0 && max(abs(radial-armLength))<1e-10, ...
    'Flight:MotorGeometry','The current X4 plant requires equal radial motor arms.');
v.arm_length_m=armLength;

yaw=v.motor_yaw_torque_ratio_m(:);
assert(numel(yaw)==4 && all(isfinite(yaw)) && ...
       numel(v.motor_min_thrust_n)==4 && numel(v.motor_max_thrust_n)==4 && ...
       all(isfinite(v.motor_min_thrust_n)) && all(isfinite(v.motor_max_thrust_n)) && ...
       all(v.motor_min_thrust_n>=0) && all(v.motor_max_thrust_n>v.motor_min_thrust_n), ...
    'Flight:ActuatorParameters','Invalid Flight motor thrust/yaw parameters.');

% Match Flight control_backend_init: E maps motor thrust to [T, tau_x, tau_y, tau_z].
effectiveness=[ones(1,4);-position(2,:);position(1,:);yaw'];
assert(rcond(effectiveness)>1e-8,'Flight:AllocationRank', ...
    'Flight motor geometry produces a rank-deficient allocation matrix.');
allocationInverse=inv(effectiveness);

cfg.vehicle_model=v;
assert(profile.gnss_installed && profile.gnss_enabled && ...
       profile.pps_installed && profile.pps_enabled, ...
    'Flight:RequiredGNSS','GNSS and PPS must be installed and enabled.');
assert(v.mass_kg>0 && simVehicle.motor_thrust_coefficient_n_s2>0 && ...
       all(simVehicle.drag_ned_kgps(:)>=0) && ...
       simVehicle.rate_damping_nm_s>=0 && ...
       simVehicle.ground_stiffness_npm>0 && ...
       simVehicle.ground_damping_ns_pm>=0 && ...
       simVehicle.ground_friction>=0 && ...
       all(simVehicle.skid_half_span_m(:)>=0), ...
    'Flight:PhysicalParameters','Invalid SIM_ONLY physical parameters.');
assert(estimator.error_state_rank==22 && estimator.noise_rank==19, ...
    'Flight:FilterRank','Expected Project22/Qc19.');

J=reshape(v.inertia_frd_kgm2,3,3);
assert(max(abs(J-J'),'all')<1e-12,'Flight:InertiaSymmetry', ...
    'The Flight inertia tensor must be symmetric.');
[~,failure]=chol(J);
assert(failure==0,'Flight:Inertia','Inertia must be positive definite.');

% Use the same gravity value as the Flight Host SIL runtime; do not duplicate it.
runtimePath=fullfile(root,'..','Flight','applications','runtime','runtime.c');
runtimeSource=fileread(runtimePath);
gravityToken=regexp(runtimeSource, ...
    'out->guidance\.payload\.gravity_mps2\s*=\s*([0-9.]+)f','tokens','once');
assert(~isempty(gravityToken),'Flight:GravitySource', ...
    'Could not find the Flight Host SIL gravity assignment.');
gravity=str2double(gravityToken{1});
assert(isfinite(gravity) && gravity>0,'Flight:GravitySource','Invalid Flight gravity.');

% Earth rotation expressed in the fixed local NED frame at the SIM_ONLY origin.
origin=simVehicle.origin_llh_rad_m(:);
assert(numel(origin)==3 && all(isfinite(origin)) && abs(origin(1))<=pi/2, ...
    'Flight:Origin','Invalid SIM_ONLY origin LLH.');
earthRotationRadps=7.2921150e-5;
earthRateNed=earthRotationRadps*[cos(origin(1));0;-sin(origin(1))];

wrench=[zeros(2,4);-ones(1,4);-position(2,:);position(1,:);yaw'];
magneticField=cfg.sensor_alignment.magnetic_field_ned_ut(:);
assert(numel(magneticField)==3 && all(isfinite(magneticField)), ...
    'Flight:MagneticField','SIM_ONLY NED magnetic field must contain three finite values.');
assert(numel(simVehicle.plant_state0)==17 && all(isfinite(simVehicle.plant_state0)), ...
    'Flight:PlantState','SIM_ONLY initial Plant state must contain 17 finite values.');
assert(norm(simVehicle.plant_state0(7:10))>1e-12 && ...
       all(simVehicle.plant_state0(14:17)>=0), ...
    'Flight:PlantState','Initial quaternion and motor speeds are invalid.');

% PlantParameters schema (26): mass, full J(:), kf, tau, drag(3), rate damping,
% ground stiffness/damping/down, contact lever(3), gravity, skid half-span(2), friction.
plantParameters=[v.mass_kg;J(:);simVehicle.motor_thrust_coefficient_n_s2; ...
    v.motor_time_constant_s;simVehicle.drag_ned_kgps(:);simVehicle.rate_damping_nm_s; ...
    simVehicle.ground_stiffness_npm;simVehicle.ground_damping_ns_pm; ...
    simVehicle.ground_down_m;simVehicle.contact_lever_frd_m(:);gravity; ...
    simVehicle.skid_half_span_m(:);simVehicle.ground_friction];

std=estimator.initial_std;
initialStd=[std.position_m(:);std.velocity_mps(:);deg2rad(std.attitude_deg(:)); ...
    std.gyro_bias_radps(:);std.accel_bias_mps2(:);std.gyro_scale(:); ...
    std.accel_scale(:);std.baro_bias_m];
tau=estimator.bias_correlation_time_s;
qc=[repmat(estimator.accel_rate_white_std_mps2^2*.001,3,1); ...
    repmat(estimator.gyro_rate_white_std_radps^2*.001,3,1); ...
    repmat(2*estimator.gyro_bias_stationary_std_radps^2/tau,3,1); ...
    repmat(2*estimator.accel_bias_stationary_std_mps2^2/tau,3,1); ...
    repmat(2*estimator.gyro_scale_stationary_std^2/tau,3,1); ...
    repmat(2*estimator.accel_scale_stationary_std^2/tau,3,1); ...
    estimator.baro_bias_rw_psd_m2ps];
assert(numel(plantParameters)==26 && numel(qc)==19 && ...
       all(qc>=0) && numel(initialStd)==22, ...
    'Flight:ParameterShape','Invalid Plant/filter parameter schema.');

dictionaryFolder=fullfile(root,'dictionaries');
if ~isfolder(dictionaryFolder), mkdir(dictionaryFolder); end
validationFolder=fullfile(root,'work','validation');
if ~isfolder(validationFolder), mkdir(validationFolder); end
dictionaryFile=fullfile(dictionaryFolder,'Flight_Parameters.sldd');
if isfile(dictionaryFile)
    dictionary=Simulink.data.dictionary.open(dictionaryFile);
else
    dictionary=Simulink.data.dictionary.create(dictionaryFile);
end
section=getSection(dictionary,'Design Data');
values=struct('PlantParameters',plantParameters,'PlantState0',simVehicle.plant_state0(:), ...
    'WrenchMatrix',wrench,'MotorKf',simVehicle.motor_thrust_coefficient_n_s2, ...
    'MotorTau',v.motor_time_constant_s,'MotorMinN',v.motor_min_thrust_n(:), ...
    'MotorMaxN',v.motor_max_thrust_n(:),'PlantStepS',profile.base_step_us*1e-6, ...
    'GravityMps2',gravity,'MagneticFieldNedUt',magneticField, ...
    'EarthRateNedRadps',earthRateNed,'EstimatorP0',diag(initialStd.^2), ...
    'EstimatorQc',diag(qc),'AllocationMatrices',[allocationInverse;effectiveness], ...
    'AllocationInverse',allocationInverse,'AllocationEffectiveness',effectiveness);
c=cfg.controller_tuning;
values.RateKp=c.rate_kp_nm_per_radps(:);
values.RateKi=c.rate_ki_nm_per_rad(:);
values.RateKd=c.rate_kd_nm_per_radps2(:);
values.RateKaw=c.rate_kaw_per_s(:);
values.RateDcutoff=c.rate_d_cutoff_hz;
values.RateIlimit=c.rate_integral_limit_nm(:);
% The independent frame-quantizer fixture follows the SIM_ONLY DShot 0..10 N curve.
values.FrameQuantizerParameters=[profile.dshot_force_curve_n(2);profile.frame_slew_nps];

dictionaryChanged=false;
if exist(section,'AllocationGeometry')
    removeEntry(section,'AllocationGeometry');
    dictionaryChanged=true;
end
fields=fieldnames(values);
for k=1:numel(fields)
    name=fields{k};
    if exist(section,name)
        entry=getEntry(section,name);
        if ~isequal(getValue(entry),values.(name))
            setValue(entry,values.(name));
            dictionaryChanged=true;
        end
    else
        addEntry(section,name,values.(name));
        dictionaryChanged=true;
    end
end
if dictionaryChanged, saveChanges(dictionary); end
cfg.derived=values;
cfg.derived.EarthRotationRadps=earthRotationRadps;
save(fullfile(validationFolder,'generated_parameters.mat'),'cfg');
fprintf('Generated SIM_ONLY parameter view: Plant26, Allocation4x4, P0 22, Qc 19.\n');
end
