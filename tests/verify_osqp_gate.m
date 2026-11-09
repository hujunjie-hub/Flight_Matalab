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
report=struct('scope','G0_OSQP_MEX','status','PASS','version','1.0.0', ...
    'mode',2,'variables',15,'constraints',190,'P_nnz',45,'A_nnz',702, ...
    'known_optimum','PASS','independent_KKT','PASS','matrix_update','PASS', ...
    'strict_candidate_accepted',strictCandidateAccepted, ...
    'strict_validation_in_model','NOT_RUN', ...
    'invalid_bounds','PASS','qp_assembly_in_model','NOT_RUN');
fid=fopen(fullfile(root,'work','validation','osqp_mex_report.json'),'w');
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));
disp(report);
end
