function build_native_kernels
%BUILD_NATIVE_KERNELS Rebuild only this project's numerical gateways.
root=fileparts(fileparts(mfilename('fullpath')));
[status,message]=system(sprintf('python -B "%s"',fullfile(root,'tools','verify_inputs.py')));
assert(status==0,'Flight:InputPreflight','%s',message);
clear fmt_ground_sfun fmt_rigid_sfun fmt_normalize_sfun fmt_plant_sensors_sfun fmt_sensor_sim_probe fmt_x4_allocate_sfun fmt_frame_encode_sfun fmt_osqp_mex
sources={'plant/fmt_ground_sfun','plant/fmt_rigid_sfun','plant/fmt_normalize_sfun', ...
    'core/fmt_x4_allocate_sfun','core/fmt_frame_encode_sfun'};
for k=1:numel(sources)
    mex('-R2018a','-silent',fullfile(root,'models',[sources{k} '.c']),'-outdir',fullfile(root,'work','mex'));
end
mex('-R2018a','-silent',fullfile(root,'adapters','flight_runtime','fmt_plant_sensors_sfun.c'), ...
    '-outdir',fullfile(root,'work','mex'));
mex('-R2018a','-silent',fullfile(root,'adapters','flight_runtime','fmt_sensor_sim_probe.c'), ...
    fullfile(root,'adapters','flight_runtime','fmt_sensor_simulation.c'), ...
    '-outdir',fullfile(root,'work','mex'));
build_osqp;
end
