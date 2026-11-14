function report=verify_p10b_holdover
%VERIFY_P10B_HOLDOVER PPS outage, holdover growth and re-lock in the Host MIL.
%   The adapter withholds PPS and RECTIMEA for four seconds starting at ten
%   seconds of simulated time, samples the firmware time service during the
%   outage and again after it, so the gate can check that UTC validity dropped,
%   the uncertainty grew and then collapsed once the next PPS arrived.
root=fileparts(fileparts(mfilename('fullpath')));
file=fullfile(root,'work','validation','p10b_holdover_mil.json');
assert(isfile(file),'Flight:P10bHoldover', ...
    'The MIL run did not produce p10b_holdover_mil.json.');
s=jsondecode(fileread(file));

captured=double(s.loss_captured)==1;
lossValid=double(s.loss_utc_valid)==0;
holdover=double(s.loss_holdover_us);
lossUncertainty=double(s.loss_uncertainty_ns);
recoverValid=double(s.recover_utc_valid)==1;
recoverUncertainty=double(s.recover_uncertainty_ns);
lossPps=double(s.loss_last_pps_us);
recoverPps=double(s.recover_last_pps_us);
events=double(s.pps_events);

holdoverGrew=holdover>=1000000;
uncertaintyGrew=lossUncertainty>recoverUncertainty*2;
resumed=recoverPps>lossPps;
eventsOk=events>=20;
ok=captured && lossValid && holdoverGrew && uncertaintyGrew && recoverValid && resumed && eventsOk;

% loss_utc_valid / recover_utc_valid are the values the firmware reported; the
% verdicts live in their own fields.  Writing the derived boolean into the
% measurement field made the archive contradict the MIL snapshot it came from.
report=struct('scope','P10B_HOLDOVER_RECOVERY','status','PASS', ...
    'loss_captured',captured, ...
    'loss_utc_valid',double(s.loss_utc_valid), ...
    'utc_lost_verified',ternary(lossValid), ...
    'holdover_duration_us',holdover, ...
    'loss_uncertainty_ns',lossUncertainty, ...
    'recover_utc_valid',double(s.recover_utc_valid), ...
    'recover_uncertainty_ns',recoverUncertainty, ...
    'loss_last_pps_us',lossPps,'recover_last_pps_us',recoverPps, ...
    'pps_events',events, ...
    'holdover_recovery_verified',ternary(ok));
if ~ok
    report.status='FAIL';
end
out=fullfile(root,'work','validation','p10b_holdover_report.json');
fid=fopen(out,'w'); cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));
disp(report);
assert(ok,'Flight:P10bHoldover', ...
    ['Holdover not verified: captured=%d loss_valid=%d holdover=%llu us ' ...
     'loss_unc=%.0f recover_valid=%d recover_unc=%.0f'], ...
    captured,lossValid,uint64(holdover),lossUncertainty,recoverValid,recoverUncertainty);
end

function value=ternary(condition)
if condition
    value='PASS';
else
    value='FAIL';
end
end
