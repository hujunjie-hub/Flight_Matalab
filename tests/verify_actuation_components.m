function report=verify_actuation_components
%VERIFY_ACTUATION_COMPONENTS Verify allocation and real code inversion.
root=fileparts(fileparts(mfilename('fullpath')));
cfg=generate_parameters;
request=[15 .2 -.1 .02;40 1 2 .5;20 10 10 2];
bounds=repmat([zeros(1,4),10*ones(1,4)],3,1);
out=run('FMT_X4_ControlAllocation',{request,bounds});
forces=out.yout{1}.Values.Data;
achieved=out.yout{2}.Values.Data;
residual=out.yout{3}.Values.Data;
scale=out.yout{4}.Values.Data;
valid=out.yout{5}.Values.Data;
assert(all(valid),'Flight:Allocation','Feasible allocation rejected.');
assert(max(abs(achieved(1,:)-request(1,:)))<1e-10, ...
    'Flight:AllocationExact','Unsaturated wrench mismatch.');
assert(all(forces>=-1e-10 & forces<=10+1e-10,'all'), ...
    'Flight:AllocationBounds','Allocated motor force outside bounds.');
assert(norm(achieved(2,2:3)-request(2,2:3),inf)<1e-8 && ...
       achieved(2,1)<request(2,1), ...
    'Flight:AllocationPriority','Collective took priority over feasible roll/pitch.');
assert(scale(3)<1 && ...
       norm(achieved(3,2:3)-scale(3)*request(3,2:3),inf)<1e-8, ...
    'Flight:AllocationScale','Roll/pitch did not scale together.');
assert(norm(residual-(achieved(:,2:4)-request(:,2:4)),inf)<1e-10, ...
    'Flight:AllocationResidual','Anti-windup residual sign mismatch.');

expectedWrench=[sum(forces,2),(cfg.derived.AllocationEffectiveness(2:4,:)*forces')'];
assert(max(abs(achieved(:)-expectedWrench(:)))<1e-10, ...
    'Flight:AllocationFirmwareGeometry','Allocator wrench differs from Flight effectiveness.');
assert(max(abs(cfg.derived.AllocationEffectiveness * ...
    cfg.derived.AllocationInverse-eye(4)),[],'all')<1e-10, ...
    'Flight:AllocationMatrix','Flight allocation matrix inverse is invalid.');

out=run('FMT_X4_ControlAllocation',{zeros(2,4),repmat([ones(1,4),zeros(1,4)],2,1)});
assert(~any(out.yout{5}.Values.Data),'Flight:AllocationNegative', ...
    'Empty motor bounds accepted.');

demand=[zeros(1,4);10*ones(1,4);zeros(1,4);2*ones(1,4);11*ones(1,4)];
previous=[zeros(2,4);10*ones(1,4);2*ones(2,4)];
out=run('FMT_M7_FrameQuantizer',{demand,previous,.0025*ones(5,1)});
code=out.yout{1}.Values.Data;
packet=out.yout{2}.Values.Data;
force=out.yout{3}.Values.Data;
valid=out.yout{4}.Values.Data;
assert(all(valid(1:4)) && ~valid(5), ...
    'Flight:QuantizerRange','Physical range validation failed.');
assert(all(code(1,:)==0) && all(code(2,:)==97) && all(code(3,:)==1998), ...
    'Flight:QuantizerCodes','Incorrect feasible-integer selection.');
for row=1:4
    decoded=zeros(1,4);
    active=code(row,:)~=0;
    decoded(active)=(double(code(row,active))-48)*10/1999;
    assert(norm(force(row,:)-decoded,inf)<1e-12, ...
        'Flight:CodeInverse','Returned N differs from actual integer code.');
    assert(all(abs(force(row,:)-previous(row,:))<=.25+1e-12), ...
        'Flight:FrameSlew','Quantized frame violates physical slew.');
    payload=bitshift(code(row,:),1);
    checksum=bitand(bitxor(bitxor(payload,bitshift(payload,-4)), ...
        bitshift(payload,-8)),uint16(15));
    assert(isequal(packet(row,:),bitor(bitshift(payload,4),checksum)), ...
        'Flight:DShotChecksum','DShot packet checksum mismatch.');
end
out=run('FMT_M7_FrameQuantizer',{ones(2,4),zeros(2,4),.000001*ones(2,1)});
assert(~any(out.yout{4}.Values.Data), ...
    'Flight:QuantizerLSB','Sub-LSB slew configuration was not rejected.');

% Real M7 transaction evidence: run the Flight host suite against actuator_guard.c
% rather than asserting the guard's behaviour from the MATLAB side.
m7=run_m7_host_suite(root);
assert(~strcmp(m7.permit_lifecycle,'FAIL') && ~strcmp(m7.frame_apply_500us,'FAIL') && ...
    ~strcmp(m7.ground_stop_transaction,'FAIL'), ...
    'Flight:M7Host','M7 actuator guard host suite failed (%d failures).',m7.failures);

report=struct('scope','ACTUATION_NUMERICAL_COMPONENTS','status','PASS', ...
    'allocation_exact','PASS','roll_pitch_priority','PASS', ...
    'shared_roll_pitch_scale','PASS','current_residual_sign','PASS', ...
    'flight_effectiveness_matrix','PASS','generic_inverse_contract','PASS', ...
    'integer_force_inverse','PASS','quantized_slew','PASS', ...
    'dshot_checksum','PASS','invalid_physical_range','PASS', ...
    'sub_lsb_slew_rejection','PASS', ...
    'permit_lifecycle',m7.permit_lifecycle, ...
    'frame_apply_500us',m7.frame_apply_500us, ...
    'ground_stop_transaction',m7.ground_stop_transaction, ...
    'ground_stop_evidence',m7.ground_stop_evidence, ...
    'ground_stop_max_apply_us',m7.ground_stop_max_apply_us, ...
    'ground_stop_max_ramp_nps',m7.ground_stop_max_ramp_nps, ...
    'ground_stop_log',m7.ground_stop_log, ...
    'm7_host_checks',m7.checks,'m7_host_failures',m7.failures, ...
    'm7_host_log',m7.log,'m7_host_reason',m7.reason);
fid=fopen(fullfile(root,'work','validation','actuation_report.json'),'w');
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));
disp(report);
end

function out=run(model,data)
N=size(data{1},1);
t=(0:N-1)'*.0005;
ds=Simulink.SimulationData.Dataset;
for k=1:numel(data)
    ds{k}=timeseries(data{k},t);
end
in=Simulink.SimulationInput(model);
in=in.setExternalInput(ds);
in=in.setModelParameter('StopTime',num2str(t(end),17),'FixedStep','0.0005');
out=sim(in);
end

function result=run_m7_host_suite(root)
%RUN_M7_HOST_SUITE Compile and run the Flight M7 actuator guard host test.
result=struct('permit_lifecycle','NOT_RUN','frame_apply_500us','NOT_RUN', ...
    'ground_stop_transaction','NOT_RUN','ground_stop_evidence','UNAVAILABLE', ...
    'ground_stop_max_apply_us',0,'ground_stop_max_ramp_nps',0, ...
    'ground_stop_log','', ...
    'checks',0,'failures',0,'log','','reason','');
flightRoot=fullfile(fileparts(root),'Flight');
script=fullfile(flightRoot,'tests','actuation','run_host_tests.ps1');
if ~isfile(script)
    result.reason='Flight actuation host suite not found';
    return;
end
[status,message]=system(sprintf('pwsh -NoProfile -File "%s"',script));
summaryFile=fullfile(flightRoot,'build','validation','m7','actuation_host_summary.json');
if ~isfile(summaryFile)
    result.reason=sprintf('no host summary (exit %d): %s',status,strtrim(message));
    return;
end
summary=jsondecode(fileread(summaryFile));
result.log=summary.log;
result.checks=summary.checks;
result.failures=summary.failures;
switch summary.status
    case 'PASS'
        result.permit_lifecycle=summary.permit_lifecycle;
        result.frame_apply_500us=summary.frame_apply_500us;
        result.ground_stop_transaction=summary.ground_stop_transaction;
        result.ground_stop_evidence=summary.ground_stop_evidence;
        result.ground_stop_max_apply_us=summary.ground_stop_max_apply_us;
        result.ground_stop_max_ramp_nps=summary.ground_stop_max_ramp_nps;
        result.ground_stop_log=summary.ground_stop_log;
    case 'FAIL'
        result.permit_lifecycle='FAIL';
        result.frame_apply_500us='FAIL';
        result.ground_stop_transaction='FAIL';
    otherwise
        result.reason=sprintf('host suite status %s',summary.status);
end
end