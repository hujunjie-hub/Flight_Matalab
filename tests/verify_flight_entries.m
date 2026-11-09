function report = verify_flight_entries(refreshRecording)
%VERIFY_FLIGHT_ENTRIES Execute closed loop and both replays against one tape.
if nargin == 0, refreshRecording = false; end
root = flight_startup;
mil = 'FMT_MILSIM';
commandTape = fmt_default_input(mil);
closed = run(mil,commandTape);
s = signal(closed,2);
force = signal(closed,1);
x = signal(closed,4);
fprintf('MIL max altitude %.3f m, final down %.3f m, final velocity %.3f m/s\n', ...
    max(-x(:,3)),x(end,3),norm(x(end,4:6)));
fprintf(['MIL diagnostics: armed=%d commit_valid=%d max_nav_mask=0x%02X ' ...
    'max_total_thrust=%.3f N max_motor_thrust=%.3f N last_request=%u ack=%u reason=%u\n'], ...
    any(s(:,3)==2),any(s(:,8)==1),uint32(max(s(:,12))), ...
    max(sum(force,2)),max(force(:)),s(end,9),s(end,10),s(end,11));
assert(all(isfinite(x),'all') && all(isfinite(force),'all'),'Flight:MILFinite','Nonfinite closed-loop output.');
assert(any(s(:,3)==2),'Flight:MILArm','MIL never entered the armed state.');
assert(any(s(:,8)==1),'Flight:MILCommit','MIL never produced a valid actuator commit.');
assert(max(-x(:,3))>=1.8,'Flight:MILTakeoff', ...
    'MIL did not reach the required 1.8 m minimum takeoff altitude.');
assert(all(force(s(:,8)==0,:)==0,'all'),'Flight:Permit','Nonzero thrust without a current commit.');
assert(s(end,3)==0 && s(end,10)==3 && norm(x(end,4:6))<.15 && abs(x(end,3))<.1, ...
    'Flight:MILLanding','The simulated flight did not land and disarm.');
assert(all(s(:,24)==0),'Flight:FirmwareSIL','Flight host fixture checks failed.');

if refreshRecording
    t = closed.tout;
    sensor = signal(closed,5);
    commands = commandTape{1}.Data;
    navigation = signal(closed,3);
    % The core outputs at k+1 the result from step k. External M3 replay
    % must inject that result during step k, with its original contract time.
    navigation = navigation([2:end end],:);
    meta = fmt_flight_metadata;
    revision = meta.product_contract_revision;
    save(fullfile(root,'scenarios','flight_sil_recording.mat'), ...
        't','sensor','commands','navigation','revision','-v7');
end

data = run('FMT_DataSIM',fmt_default_input('FMT_DataSIM'));
ext = run('FMT_ExtINS_DataSIM',fmt_default_input('FMT_ExtINS_DataSIM'));
dataStatus = signal(data,2);
extStatus = signal(ext,2);
assert(isequaln(s,dataStatus) && isequaln(force,signal(data,1)), ...
    'Flight:SensorReplay','Replaying MIL sensors diverged from the closed-loop run.');
assert(isequaln(dataStatus(:,[3:8 12:18]),extStatus(:,[3:8 12:18])) && ...
    isequaln(signal(data,1),signal(ext,1)), ...
    'Flight:ExternalReplay','External navigation replay diverged from the recorded flight.');
assert(all(extStatus(:,24)==0),'Flight:ExternalSIL','Flight host fixture checks failed in ExtINS.');

% Invalid samples remain invalid and must not become actuator commands.
dropout = fmt_default_input('FMT_DataSIM');
bad = dropout{1}.Data;
bad(:,17) = 0;
dropout{1} = setinterpmethod(timeseries(bad,dropout{1}.Time),'zoh');
off = run('FMT_DataSIM',dropout,'4.2');
assert(all(signal(off,1)==0,'all'),'Flight:Dropout','Missing sensors permitted thrust.');

report = struct('status','PASS','duration_s',closed.tout(end), ...
    'maximum_altitude_m',max(-x(:,3)),'final_height_m',-x(end,3), ...
    'final_speed_mps',norm(x(end,4:6)),'mpc_updates',s(end,22), ...
    'actuator_commits',s(end,23),'sensor_replay_identical',true, ...
    'external_navigation_control_identical',true,'invalid_sensors_inhibit',true);
file = fopen(fullfile(root,'work','validation','flight_entries.json'),'w');
cleanup = onCleanup(@()fclose(file));
fprintf(file,'%s\n',jsonencode(report,PrettyPrint=true));
disp(report);
end

function out = run(model,ds,stop)
if nargin < 3, stop = '26'; end
input = Simulink.SimulationInput(model);
input = input.setExternalInput(ds);
input = input.setModelParameter('StopTime',stop);
out = sim(input);
assert(abs(out.tout(end)-str2double(stop))<1e-10,'Flight:EarlyStop','%s stopped early.',model);
end

function data = signal(out,port)
data = out.yout{port}.Values.Data;
end


