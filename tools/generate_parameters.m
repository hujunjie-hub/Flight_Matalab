function cfg=generate_parameters
%GENERATE_PARAMETERS Derive the SIM_ONLY parameter view from explicit sources.
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

% Flight owns the physical geometry, motor limits and yaw convention.
% SIM_ONLY owns only the plant effects that are absent from the firmware.
simVehicle=cfg.vehicle_model;
v=simVehicle;
p=cfg.profile_manifest;
e=cfg.estimator_tuning;
flight=jsondecode(fileread(fullfile(root,'..','Flight','config','vehicle_model.yaml')));
assert(strcmp(flight.profile,'QUAD_X4') && strcmp(flight.status,'SIM_ONLY'), ...
    'Flight:PlantProfile','Expected the Flight SIM_ONLY QUAD_X4 vehicle.');

vehicleFields={'mass_kg','inertia_frd_kgm2','motor_position_frd_m', ...
    'motor_yaw_torque_ratio_m','motor_min_thrust_n','motor_max_thrust_n'};
for k=1:numel(vehicleFields)
    field=vehicleFields{k};
    v.(field)=flight.(field);
end
position=flight.motor_position_frd_m';
assert(isequal(size(position),[3 4]),'Flight:MotorGeometry', ...
    'The X4 allocator requires four FRD motor positions.');
radial=hypot(position(1,:),position(2,:));
armLength=mean(radial);
assert(all(isfinite(radial)) && max(abs(radial-armLength))<1e-10 && armLength>0, ...
    'Flight:MotorGeometry','Flight motor positions do not form a symmetric X4 layout.');
armComponent=armLength/sqrt(2);
expectedX=[armComponent armComponent -armComponent -armComponent];
expectedY=[-armComponent armComponent armComponent -armComponent];
assert(max(abs(position(1,:)-expectedX))<1e-10 && ...
       max(abs(position(2,:)-expectedY))<1e-10, ...
    'Flight:MotorGeometry','The native X4 allocator does not support this motor ordering.');

yaw=v.motor_yaw_torque_ratio_m(:);
assert(numel(yaw)==4 && all(isfinite(yaw)) && abs(yaw(1))>1e-12 && ...
       max(abs(yaw-yaw(1)*[1;-1;1;-1]))<1e-10, ...
    'Flight:YawGeometry','Flight yaw coefficients do not match the X4 allocator motor ordering.');
assert(all(flight.motor_time_constant_s==flight.motor_time_constant_s(1)), ...
    'Flight:MotorDynamics','The current plant uses a shared rotor time constant.');
v.arm_length_m=armLength;
v.motor_time_constant_s=flight.motor_time_constant_s(1);
cfg.vehicle_model=v;

assert(p.gnss_installed && p.gnss_enabled && p.pps_installed && p.pps_enabled, ...
    'Flight:RequiredGNSS','GNSS and PPS must be installed and enabled.');
assert(v.mass_kg>0 && all(v.motor_max_thrust_n>v.motor_min_thrust_n), ...
    'Flight:PhysicalParameters','Invalid vehicle parameters.');
assert(e.error_state_rank==22 && e.noise_rank==19, ...
    'Flight:FilterRank','Expected Project22/Qc19.');
J=reshape(v.inertia_frd_kgm2,3,3);
[~,failure]=chol(J);
assert(failure==0,'Flight:Inertia','Inertia must be SPD.');

gravity=9.80665;
wrench=[zeros(2,4);-ones(1,4);-position(2,:);position(1,:);yaw'];
magneticField=cfg.sensor_alignment.magnetic_field_ned_ut(:);
assert(numel(magneticField)==3 && all(isfinite(magneticField)), ...
    'Flight:MagneticField','SIM_ONLY NED magnetic field must contain three finite values.');

% p=[mass;Jdiag;kf;tau;drag(3);rateDamping;kGround;cGround;groundD;lever(3);gravity;skidSpan(2);groundFriction].
plantParameters=[v.mass_kg;diag(J);simVehicle.motor_thrust_coefficient_n_s2; ...
    v.motor_time_constant_s;simVehicle.drag_ned_kgps(:);simVehicle.rate_damping_nm_s; ...
    simVehicle.ground_stiffness_npm;simVehicle.ground_damping_ns_pm; ...
    simVehicle.ground_down_m;simVehicle.contact_lever_frd_m(:);gravity; ...
    simVehicle.skid_half_span_m(:);simVehicle.ground_friction];
std=e.initial_std;
initialStd=[std.position_m(:);std.velocity_mps(:);deg2rad(std.attitude_deg(:)); ...
    std.gyro_bias_radps(:);std.accel_bias_mps2(:);std.gyro_scale(:); ...
    std.accel_scale(:);std.baro_bias_m];
tau=e.bias_correlation_time_s;
qc=[repmat(e.accel_rate_white_std_mps2^2*.001,3,1); ...
    repmat(e.gyro_rate_white_std_radps^2*.001,3,1); ...
    repmat(2*e.gyro_bias_stationary_std_radps^2/tau,3,1); ...
    repmat(2*e.accel_bias_stationary_std_mps2^2/tau,3,1); ...
    repmat(2*e.gyro_scale_stationary_std^2/tau,3,1); ...
    repmat(2*e.accel_scale_stationary_std^2/tau,3,1);e.baro_bias_rw_psd_m2ps];
assert(numel(qc)==19 && all(qc>=0) && numel(initialStd)==22, ...
    'Flight:FilterNoise','Invalid filter noise schema.');

dictionaryFolder=fullfile(root,'dictionaries');
if ~isfolder(dictionaryFolder), mkdir(dictionaryFolder); end
validationFolder=fullfile(root,'work','validation');
if ~isfolder(validationFolder), mkdir(validationFolder); end
file=fullfile(dictionaryFolder,'Flight_Parameters.sldd');
if isfile(file)
    dictionary=Simulink.data.dictionary.open(file);
else
    dictionary=Simulink.data.dictionary.create(file);
end
section=getSection(dictionary,'Design Data');
values=struct('PlantParameters',plantParameters,'PlantState0',simVehicle.plant_state0(:), ...
    'WrenchMatrix',wrench,'MotorKf',simVehicle.motor_thrust_coefficient_n_s2, ...
    'MotorTau',v.motor_time_constant_s,'MotorMaxN',v.motor_max_thrust_n(:), ...
    'PlantStepS',p.base_step_us*1e-6,'GravityMps2',gravity, ...
    'MagneticFieldNedUt',magneticField,'EstimatorP0',diag(initialStd.^2), ...
    'EstimatorQc',diag(qc));
c=cfg.controller_tuning;
values.RateKp=c.rate_kp_nm_per_radps(:);
values.RateKi=c.rate_ki_nm_per_rad(:);
values.RateKd=c.rate_kd_nm_per_radps2(:);
values.RateKaw=c.rate_kaw_per_s(:);
values.RateDcutoff=c.rate_d_cutoff_hz;
values.RateIlimit=c.rate_integral_limit_nm(:);
% The native allocator accepts radial arm length and signed motor-1 yaw ratio.
values.AllocationGeometry=[v.arm_length_m;v.motor_yaw_torque_ratio_m(1)];
% The independent frame-quantizer fixture intentionally retains its 0..10 N curve.
values.FrameQuantizerParameters=[simVehicle.motor_max_thrust_n(1);p.frame_slew_nps];
fields=fieldnames(values);
for k=1:numel(fields)
    name=fields{k};
    if exist(section,name)
        entry=getEntry(section,name);
        if ~isequal(getValue(entry),values.(name))
            setValue(entry,values.(name));
        end
    else
        addEntry(section,name,values.(name));
    end
end
saveChanges(dictionary);
cfg.derived=values;
save(fullfile(validationFolder,'generated_parameters.mat'),'cfg');
fprintf('Generated SIM_ONLY parameter view: gravity %.12g m/s^2, P0 22, Qc 19.\n',gravity);
end
