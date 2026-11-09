function build_osqp
%BUILD_OSQP Compile the locked solver into the new project's own MEX folder.
root = fileparts(fileparts(mfilename('fullpath')));
[status,message]=system(sprintf('python -B "%s"',fullfile(root,'tools','verify_inputs.py')));
assert(status==0,'Flight:InputPreflight','%s',message);

lock = jsondecode(fileread(fullfile(root,'external_dependencies.lock.json')));
source = fullfile(root,lock.osqp.root,'generated');
assert(lock.osqp.verified_files > 0,'Flight:DependencyLock','Run prepare_sources.py first.');
files = dir(fullfile(source,'src','*.c'));
args = cellfun(@(n)fullfile(source,'src',n),{files.name},UniformOutput=false);
mex('-R2018a','-silent',['-I' source],['-I' fullfile(source,'inc','public')], ...
    ['-I' fullfile(source,'inc','private')],fullfile(root,'tools','fmt_osqp_mex.c'), ...
    fullfile(source,'quad_workspace.c'),args{:},'-outdir',fullfile(root,'work','mex'));
fprintf('Built OSQP 1.0.0 mode 2: %s\n',which('fmt_osqp_mex'));
end

