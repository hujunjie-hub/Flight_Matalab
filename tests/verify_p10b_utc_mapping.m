function report=verify_p10b_utc_mapping
%VERIFY_P10B_UTC_MAPPING UTC discipline reached through the injected PPS/RECTIMEA.
%   The adapter dumps the firmware time service state at shutdown; the MIL
%   snapshot is copied aside before the replay runs overwrite it. This gate
%   checks that the service actually accepted the UTC pairing rather than only
%   that the submissions returned OK.
root=fileparts(fileparts(mfilename('fullpath')));
statsFile=fullfile(root,'work','validation','p10b_time_service_mil.json');
assert(isfile(statsFile),'Flight:P10bUtc', ...
    'The MIL run did not produce p10b_time_service_mil.json.');
s=jsondecode(fileread(statsFile));

pps=double(s.pps_events);
frames=double(s.rectime_frames);
gnss=double(s.gnss_observations);
utcValid=double(s.utc_valid)==1;
mappingEpoch=double(s.utc_mapping_epoch)>=1;
uncertainty=double(s.utc_uncertainty_ns);
discipline=double(s.discipline_valid)==1;
intervals=double(s.accepted_intervals);
lastPps=double(s.last_valid_pps_us);
now=double(s.monotonic_now_us);
ppsRecent=lastPps>0 && now>=lastPps && (now-lastPps)<=2500000;

report=struct('scope','P10B_UTC_MAPPING','status','PASS', ...
    'pps_events',pps,'rectime_frames',frames,'gnss_observations',gnss, ...
    'utc_valid',utcValid,'utc_mapping_epoch',double(s.utc_mapping_epoch), ...
    'utc_uncertainty_ns',uncertainty,'discipline_valid',discipline, ...
    'accepted_intervals',intervals,'last_valid_pps_us',lastPps, ...
    'pps_recent',ppsRecent, ...
    'utc_discipline','PASS');
ok=utcValid && mappingEpoch && discipline && ppsRecent && uncertainty<1000000 && intervals>=1;
if ~ok
    report.status='FAIL';
    report.utc_discipline='FAIL';
end
file=fullfile(root,'work','validation','p10b_utc_mapping_report.json');
fid=fopen(file,'w'); cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));
disp(report);
assert(ok,'Flight:P10bUtc', ...
    'UTC mapping not established: utc_valid=%d mapping_epoch=%u intervals=%d uncertainty=%.0f ns.', ...
    double(s.utc_valid),double(s.utc_mapping_epoch),intervals,uncertainty);
end
