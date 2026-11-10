function report=verify_p10b_pps_rectime
%VERIFY_P10B_PPS_RECTIME Host MIL injection of PPS and UM982 RECTIMEA.
%   The counters come from the MIL run: the adapter submits a PpsCaptureEvent to
%   the firmware time service once per simulated second, feeds a recorded UM982
%   RECTIMEA sentence through unicore_ascii, and submits the paired
%   GnssTimeObservation. Nothing here re-implements the chain - it only checks
%   that the MIL really drove it.
root=fileparts(fileparts(mfilename('fullpath')));
statsFile=fullfile(root,'work','validation','m6_runtime_stats_mil.json');
assert(isfile(statsFile),'Flight:P10b', ...
    'The MIL run did not produce m6_runtime_stats_mil.json.');
stats=jsondecode(fileread(statsFile));
fields={'p10b_pps_ok','p10b_pps_reject','p10b_rectime_frames','p10b_gnss_ok'};
for k=1:numel(fields)
    assert(isfield(stats,fields{k}),'Flight:P10b', ...
        'The runtime statistics are missing %s.',fields{k});
end

pps=double(stats.p10b_pps_ok);
rejected=double(stats.p10b_pps_reject);
frames=double(stats.p10b_rectime_frames);
gnss=double(stats.p10b_gnss_ok);

injection=pps>=20;
rectime=frames>=20;
paired=gnss>=20;
clean=rejected==0;

report=struct('scope','P10B_HOST_MIL_PPS_RECTIME','status','PASS', ...
    'pps_events_accepted',pps,'pps_events_rejected',rejected, ...
    'rectime_frames_decoded',frames,'gnss_time_observations_accepted',gnss, ...
    'pps_capture_injection',ternary(injection,'PASS','FAIL'), ...
    'um982_rectime_parse',ternary(rectime,'PASS','FAIL'), ...
    'gnss_time_pairing',ternary(paired,'PASS','FAIL'), ...
    'no_rejected_edges',ternary(clean,'PASS','FAIL'), ...
    'utc_mapping_verified','NOT_RUN', ...
    'holdover_recovery_verified','NOT_RUN', ...
    'note','PPS/RECTIMEA injection runs on the real systime.c and unicore_ascii; UTC discipline and holdover recovery still need their own fixtures.');
if ~(injection && rectime && paired && clean)
    report.status='FAIL';
end
file=fullfile(root,'work','validation','p10b_report.json');
fid=fopen(file,'w'); cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));
disp(report);
assert(strcmp(report.status,'PASS'),'Flight:P10b', ...
    'PPS/RECTIMEA injection incomplete: pps=%d frames=%d gnss=%d rejected=%d.', ...
    pps,frames,gnss,rejected);
end

function value=ternary(condition,whenTrue,whenFalse)
if condition
    value=whenTrue;
else
    value=whenFalse;
end
end
