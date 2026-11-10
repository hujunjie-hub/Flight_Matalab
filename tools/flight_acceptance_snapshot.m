function report=flight_acceptance_snapshot(root,stage)
%FLIGHT_ACCEPTANCE_SNAPSHOT Capture the inputs and outputs around a validation run.
%   REPORT=FLIGHT_ACCEPTANCE_SNAPSHOT(ROOT,STAGE) records, for STAGE 'before'
%   or 'after':
%
%     source_fingerprint_<stage>.json    committed and worktree source digests
%     git_state_<stage>.json            branch, commit and classified changes
%     artifact_fingerprint_<stage>.json Simulink models, dictionaries, kernels
%
%   The 'after' stage additionally writes current_source_fingerprint.json (the
%   file the archive reads), current_artifact_fingerprint.json and
%   generated_assets.json, which classifies every file the run touched as a
%   commit candidate, temporary build output or recoverable layout drift.
%
%   The run itself only ever generates models, dictionaries, MEX kernels and
%   recordings; fingerprint_sources.py keeps those out of the source digest, so
%   regenerating a model cannot make the source fingerprint drift.
assert(any(strcmp(stage,{'before','after'})),'Flight:Snapshot', ...
    'Snapshot stage must be before or after, got %s.',stage);
validation=fullfile(root,'work','validation');
if ~isfolder(validation), mkdir(validation); end

report=struct('stage',stage);
report.source=run_tool(root,'fingerprint_sources.py',{},validation);
copyfile(fullfile(validation,'current_source_fingerprint.json'), ...
    fullfile(validation,sprintf('source_fingerprint_%s.json',stage)));

report.git=run_tool(root,'git_state.py', ...
    {stage,fullfile(validation,sprintf('git_state_%s.json',stage))},validation);

artifactFile=fullfile(validation,sprintf('artifact_fingerprint_%s.json',stage));
if strcmp(stage,'before')
    report.artifacts=run_tool(root,'fingerprint_artifacts.py',{'--output',artifactFile},validation);
    report.source_fingerprint=read_digest(fullfile(validation,'source_fingerprint_before.json'));
else
    beforeArtifact=fullfile(validation,'artifact_fingerprint_before.json');
    beforeGit=fullfile(validation,'git_state_before.json');
    arguments={'--output',fullfile(validation,'current_artifact_fingerprint.json'), ...
        '--classification',fullfile(validation,'generated_assets.json')};
    if isfile(beforeArtifact) && isfile(beforeGit)
        arguments=[arguments,{'--before',beforeArtifact,'--before-git',beforeGit}];
    end
    report.artifacts=run_tool(root,'fingerprint_artifacts.py',arguments,validation);
    copyfile(fullfile(validation,'current_artifact_fingerprint.json'),artifactFile);
    report.source_fingerprint=read_digest(fullfile(validation,'source_fingerprint_after.json'));
    assetsFile=fullfile(validation,'generated_assets.json');
    if isfile(assetsFile)
        assets=jsondecode(fileread(assetsFile));
        report.generated_assets=assets.summary;
    end
end
end

function summary=run_tool(root,script,arguments,validation)
tool=fullfile(root,'tools',script);
parts=[{'-B',tool},arguments];
command=['python ' sprintf('"%s" ',parts{:})];
[status,message]=system(command);
assert(status==0,'Flight:Snapshot','%s failed: %s',script,message);
if ~isfolder(validation), mkdir(validation); end
try
    summary=jsondecode(strtrim(message));
catch
    summary=struct('raw',strtrim(message));
end
end

function value=read_digest(file)
record=jsondecode(fileread(file));
value=record.sha256;
end
