function build_flight_mex
%BUILD_FLIGHT_MEX Build the MATLAB gateways for the current firmware SIL.
root = flight_startup;
mexFolder = fullfile(root,'work','mex');
assert(isfile(fullfile(mexFolder,'fmt_flight_runtime.dll')), ...
    'Flight:RuntimeMissing','Run tools/build_flight_runtime.ps1 before building the MEX gateways.');
sources = {'models/plant/fmt_ground_sfun','models/plant/fmt_rigid_sfun', ...
    'models/plant/fmt_normalize_sfun','adapters/flight_runtime/fmt_flight_sfun', ...
    'adapters/flight_runtime/fmt_plant_sensors_sfun'};
for k = 1:numel(sources)
    mex('-R2018a','-silent',fullfile(root,[sources{k} '.c']),'-outdir',mexFolder);
end
generate_parameters;
end
