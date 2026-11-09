function ids = fmt_edit(model,scope,operations,mode)
%FMT_EDIT Audited model_edit call; fail immediately on a partial edit.
% All structural changes pass through model_edit and its layout engine.
root = fileparts(fileparts(mfilename('fullpath')));
if nargin < 4, mode = 'full'; end
model_read(model,scope,'0');
payload = jsonencode(operations);
result = char(model_edit(model,scope,payload,mode));
logfile = fullfile(root,'work','validation','model_edit.jsonl');
fid = fopen(logfile,'a');
fprintf(fid,'%s\n',jsonencode(struct('model',model,'scope',scope,'operations',{operations},'result',result)));
fclose(fid);
if ~contains(result,'status: ok')
    disp(model_read(model,scope,'0'));
    disp(model_check(model,scope,'["all"]'));
    error('Flight:EditFailed','%s',result);
end
tokens = regexp(result,'(?m)^\s+(\w+): (blk_\d+|sf_[\d:]+)\s*$','tokens');
ids = struct;
for k = 1:numel(tokens), ids.(tokens{k}{1}) = tokens{k}{2}; end
end
