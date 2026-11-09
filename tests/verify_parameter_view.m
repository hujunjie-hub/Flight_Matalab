function report=verify_parameter_view
%VERIFY_PARAMETER_VIEW Check derived configuration against independent inputs.
root=fileparts(fileparts(mfilename('fullpath')));
cfg=generate_parameters;
runtime=fileread(fullfile(root,'..','Flight','applications','runtime','runtime.c'));
token=regexp(runtime,'out->guidance\.payload\.gravity_mps2\s*=\s*([0-9.]+)f','tokens','once');
assert(~isempty(token),'Flight:GravitySource','Flight runtime gravity assignment was not found.');
expected=str2double(token{1});
assert(cfg.derived.GravityMps2==expected,'Flight:SharedGravity','Plant gravity differs from Flight Host SIL.');
assert(isequal(size(cfg.derived.EstimatorP0),[22 22]) && isequal(size(cfg.derived.EstimatorQc),[19 19]),'Flight:NoiseShape','Wrong covariance/noise dimensions.');
assert(abs(cfg.derived.EstimatorQc(1,1)-4e-7)<1e-18 && ...
       abs(cfg.derived.EstimatorQc(4,4)-1e-9)<1e-18 && ...
       abs(cfg.derived.EstimatorQc(19,19)-1e-4)<1e-18,'Flight:NoiseUnits','STD to PSD conversion failed.');
assert(abs(cfg.derived.EstimatorP0(10,10)-1e-6)<1e-18 && ...
    abs(cfg.derived.EstimatorQc(7,7)-2e-8/3600)<1e-20,'Flight:NoiseSeparation','Initial and stationary bias STD were mixed.');
report=struct('scope','GENERATED_PARAMETER_VIEW','status','PASS', ...
    'shared_flight_runtime_gravity','PASS','gravity_mps2',expected, ...
    'P0_22_Qc_19','PASS','white_STD_to_PSD','PASS','initial_and_stationary_STD_separate','PASS');
fid=fopen(fullfile(root,'work','validation','parameter_view_report.json'),'w');
closeFile=onCleanup(@()fclose(fid));fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));
disp(report);
end

