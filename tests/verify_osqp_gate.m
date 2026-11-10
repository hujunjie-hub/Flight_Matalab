function report=verify_osqp_gate
%VERIFY_OSQP_GATE Exercise the compiled solver on independent known optima.
root=fileparts(fileparts(mfilename('fullpath')));
sources=jsondecode(fileread(fullfile(root,'config','firmware_sources.json')));
header=fileread(fullfile(root,sources.qp_pattern_file));
names={'p_ptr','p_row','a_ptr','a_row'};
pattern=struct;
for k=1:numel(names)
    token=regexp(header,['qp_' names{k} '\[\d+\]\s*=\s*\{([^}]+)\}'],'tokens','once');
    pattern.(names{k})=sscanf(strrep(token{1},',',' '),'%d');
end
p=zeros(45,1); a=zeros(702,1);
for col=1:15
    pi=pattern.p_ptr(col)+1:pattern.p_ptr(col+1);
    p(pi(pattern.p_row(pi)==col-1))=2;
    ai=pattern.a_ptr(col)+1:pattern.a_ptr(col+1);
    a(ai(pattern.a_row(ai)==120+col-1))=1;
end
target=(1:15)'/15;
fmt_osqp_mex;
[x,y,info]=fmt_osqp_mex(p,-2*target,a,-100*ones(190,1),100*ones(190,1));
fprintf('Known-QP status=%g primal=%g dual=%g iterations=%g optimum-error=%g\n',info(1:4),norm(x-target,inf));
nativeDualTolerance=1e-3+1e-3*max(norm(2*x,inf),norm(2*target,inf));
assert(info(1)==1 && info(2)<=1e-3 && info(3)<=nativeDualTolerance,'Flight:OSQPSolve','Solver violated its configured tolerance.');
assert(norm(x-target,inf)<nativeDualTolerance/2,'Flight:OSQPOptimum','Incorrect optimizer.');
assert(norm(2*x-2*target,inf)<=nativeDualTolerance && norm(y,inf)<1e-3,'Flight:OSQPKKT','Independent KKT check failed.');
% SOLVED alone is insufficient for the stricter FlightSIM candidate guard.
strictCandidateAccepted=info(2)<=1e-3 && info(3)<=1e-3;
[x,~,info2]=fmt_osqp_mex(2*p,4*target,a,-100*ones(190,1),100*ones(190,1));
assert(info2(1)==1 && norm(x+target,inf)<(1e-3+4e-3)/4,'Flight:OSQPMode2','Matrix update did not change optimizer.');
rejected=false;
try
    [~,~,~]=fmt_osqp_mex(p,zeros(15,1),a,ones(190,1),zeros(190,1));
catch exception
    rejected=strcmp(exception.identifier,'Flight:OSQPBounds');
end
assert(rejected,'Flight:OSQPNegative','Invalid bounds were not rejected.');
% Real model-path evidence: the Flight host suite drives mpc.c, so the QP that
% gets inspected is the one the controller assembles from the model view.
m6=run_m6_host_suite(root);
assert(~strcmp(m6.qp_assembly_in_model,'FAIL') && ~strcmp(m6.strict_validation_in_model,'FAIL'), ...
    'Flight:M6Host','M6 host suite failed (%d failures).',m6.failures);

report=struct('scope','G0_OSQP_MEX','status','PASS','version','1.0.0', ...
    'mode',2,'variables',15,'constraints',190,'P_nnz',45,'A_nnz',702, ...
    'known_optimum','PASS','independent_KKT','PASS','matrix_update','PASS', ...
    'strict_candidate_accepted',strictCandidateAccepted, ...
    'strict_validation_in_model',m6.strict_validation_in_model, ...
    'invalid_bounds','PASS','qp_assembly_in_model',m6.qp_assembly_in_model, ...
    'm6_host_checks',m6.checks,'m6_host_failures',m6.failures, ...
    'm6_host_log',m6.log,'m6_host_reason',m6.reason);
fid=fopen(fullfile(root,'work','validation','osqp_mex_report.json'),'w');
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));
disp(report);
end

function result=run_m6_host_suite(root)
%RUN_M6_HOST_SUITE Compile and run the Flight M6 outer-loop host test.
result=struct('qp_assembly_in_model','NOT_RUN','strict_validation_in_model','NOT_RUN', ...
    'checks',0,'failures',0,'log','','reason','');
flightRoot=fullfile(fileparts(root),'Flight');
script=fullfile(flightRoot,'tests','control','run_host_tests.ps1');
if ~isfile(script)
    result.reason='Flight M6 host suite not found';
    return;
end
[status,message]=system(sprintf('pwsh -NoProfile -File "%s"',script));
summaryFile=fullfile(flightRoot,'build','validation','m6','m6_host_summary.json');
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
        result.qp_assembly_in_model=summary.qp_assembly_in_model;
        result.strict_validation_in_model=summary.strict_validation_in_model;
    case 'FAIL'
        result.qp_assembly_in_model='FAIL';
        result.strict_validation_in_model='FAIL';
    otherwise
        result.reason=sprintf('host suite status %s',summary.status);
end
end