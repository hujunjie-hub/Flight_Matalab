function report=verify_p10b_summary(injection,utc,holdover)
%VERIFY_P10B_SUMMARY Compose the top-level P-10b verdict from this run's gates.
%   The injection gate used to write p10b_report.json itself and hardcode
%   utc_mapping_verified / holdover_recovery_verified as NOT_RUN. Both gates run
%   later in the same run, so the archived top-level report contradicted the
%   evidence next to it (FMAT-0017).
%
%   The three reports are passed in, not re-read from disk, so a stale file from
%   an earlier run cannot be mixed into this verdict. P-10 stays PARTIAL: the
%   Host MIL chain is injected evidence, not TIM2 capture, UART/DMA or board
%   hardware.
if nargin~=3
    error('Flight:P10bSummary','The summary needs the injection, UTC and holdover reports.');
end
root=fileparts(fileparts(mfilename('fullpath')));

parts={injection,utc,holdover};
names={'pps_capture_injection','utc_mapping_verified','holdover_recovery_verified'};
status=cell(1,numel(parts));
for k=1:numel(parts)
    value='NOT_RUN';
    if isstruct(parts{k}) && isfield(parts{k},'status')
        value=char(parts{k}.status);
    end
    status{k}=value;
end

% The three gates must describe the same PPS/RECTIMEA stream.
pps=double(field(injection,'pps_events_accepted',NaN));
frames=double(field(injection,'rectime_frames_decoded',NaN));
gnss=double(field(injection,'gnss_time_observations_accepted',NaN));
utcPps=double(field(utc,'pps_events',NaN));
holdPps=double(field(holdover,'pps_events',NaN));
consistent=(utcPps==pps) && (holdPps==pps) && (frames==pps) && (gnss==pps);

ok=all(strcmp(status,'PASS')) && consistent;
report=struct('scope','P10B_HOST_MIL_PPS_RECTIME','status','PASS', ...
    'pps_events_accepted',pps,'rectime_frames_decoded',frames, ...
    'gnss_time_observations_accepted',gnss, ...
    'pps_capture_injection',char(status{1}), ...
    'utc_mapping_verified',char(status{2}), ...
    'holdover_recovery_verified',char(status{3}), ...
    'gates_consistent',consistent, ...
    'overall_P10_status','PARTIAL', ...
    'not_validated','physical TIM2 capture ISR, UM982 UART/DMA delivery, sensor_gnss_poll end-to-end, board clock hardware', ...
    'note','Composed from this run''s injection, UTC and holdover reports; Host MIL evidence only.');
if ~ok
    report.status='FAIL';
end
file=fullfile(root,'work','validation','p10b_report.json');
fid=fopen(file,'w'); cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));
disp(report);
assert(ok,'Flight:P10bSummary', ...
    'P-10b summary failed: injection=%s utc=%s holdover=%s consistent=%d.', ...
    status{1},status{2},status{3},consistent);
end

function value=field(source,name,default)
value=default;
if isstruct(source) && isfield(source,name) && ~isempty(source.(name))
    value=source.(name);
end
end
