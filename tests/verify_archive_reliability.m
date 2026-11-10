function report=verify_archive_reliability
%VERIFY_ARCHIVE_RELIABILITY Prove the fingerprints separate source from build output.
%   Runs against a throw-away git fixture so the checks are fast, deterministic
%   and independent of whatever the developer currently has uncommitted:
%
%     A-01  identical source gives an identical digest (determinism)
%     A-02  a clean worktree reports clean and no dirty files
%     A-03  a local edit is reported as dirty and never enters the committed digest
%     A-04  regenerating a Simulink model leaves the source digest untouched
%     A-05  rebuilding and re-running is stable: the artifact digest is repeatable
%
%   The fixture also exercises the classification used by the archive manifest.
root=flight_startup;
fixture=fullfile(root,'work','archive_fixture');
if isfolder(fixture), rmdir(fixture,'s'); end
mkdir(fixture);
mkdir(fullfile(fixture,'tools'));
mkdir(fullfile(fixture,'config'));
mkdir(fullfile(fixture,'models','plant'));
mkdir(fullfile(fixture,'dictionaries'));
for name={'fingerprint_sources.py','fingerprint_artifacts.py','git_state.py'}
    copyfile(fullfile(root,'tools',name{1}),fullfile(fixture,'tools',name{1}));
end
write_text(fullfile(fixture,'.gitignore'),'work/');
write_text(fullfile(fixture,'config','vehicle.yaml'),'mass_kg: 1.0' + eol);
write_text(fullfile(fixture,'models','plant','FMT_Demo.slx'),'model-v1');
write_text(fullfile(fixture,'dictionaries','Flight.sldd'),'dictionary-v1');

git(fixture,'init','-q','-b','main');
git(fixture,'config','user.name','flight-acceptance');
git(fixture,'config','user.email','acceptance@example.invalid');
git(fixture,'add','-A');
git(fixture,'commit','-q','-m','fixture-baseline');

validation=fullfile(fixture,'work','validation');
if ~isfolder(validation), mkdir(validation); end

cases={};
sourceA=sources(fixture,fullfile(validation,'source_a.json'));
sourceB=sources(fixture,fullfile(validation,'source_b.json'));
cases{end+1}=check_case('A-01','identical source gives an identical digest', ...
    strcmp(sourceA.sha256,sourceB.sha256) && ...
    strcmp(sourceA.committed_sha256,sourceB.committed_sha256), ...
    sprintf('sha256=%s',sourceA.sha256));

cases{end+1}=check_case('A-02','clean worktree reports clean', ...
    sourceA.clean && isempty(sourceA.dirty_files), ...
    sprintf('dirty=%d untracked=%d',numel(sourceA.dirty_files),numel(sourceA.untracked_files)));

write_text(fullfile(fixture,'config','vehicle.yaml'),'mass_kg: 2.0' + eol);
sourceDirty=sources(fixture,fullfile(validation,'source_dirty.json'));
cases{end+1}=check_case('A-03','local edit is dirty and stays out of the committed digest', ...
    ~sourceDirty.clean && any(strcmp(sourceDirty.dirty_files,'config/vehicle.yaml')) && ...
    strcmp(sourceDirty.committed_sha256,sourceA.committed_sha256), ...
    sprintf('dirty=%s committed_stable=%d',strjoin(sourceDirty.dirty_files,','), ...
    strcmp(sourceDirty.committed_sha256,sourceA.committed_sha256)));

git(fixture,'checkout','--','config/vehicle.yaml');
cleanGit=fullfile(validation,'git_state_clean.json');
run_python(fixture,'git_state.py',{'before',cleanGit,'--root=' + string(fixture)});
artifactBefore=artifacts(fixture,fullfile(validation,'artifact_before.json'));
write_text(fullfile(fixture,'models','plant','FMT_Demo.slx'),'model-v2-regenerated');
sourceAfterModel=sources(fixture,fullfile(validation,'source_after_model.json'));
artifactAfterModel=artifacts(fixture,fullfile(validation,'artifact_after_model.json'));
cases{end+1}=check_case('A-04','regenerating a model leaves the source digest untouched', ...
    strcmp(sourceAfterModel.sha256,sourceA.sha256) && ...
    ~strcmp(artifactAfterModel.sha256,artifactBefore.sha256) && ...
    artifactAfterModel.group_counts.simulink_model==artifactBefore.group_counts.simulink_model, ...
    sprintf('source_stable=%d artifact_changed=%d', ...
    strcmp(sourceAfterModel.sha256,sourceA.sha256), ...
    ~strcmp(artifactAfterModel.sha256,artifactBefore.sha256)));

artifactRepeat=artifacts(fixture,fullfile(validation,'artifact_repeat.json'));
sourceRepeat=sources(fixture,fullfile(validation,'source_repeat.json'));
cases{end+1}=check_case('A-05','repeat run after a rebuild is stable', ...
    strcmp(artifactRepeat.sha256,artifactAfterModel.sha256) && ...
    strcmp(sourceRepeat.sha256,sourceA.sha256), ...
    sprintf('artifact_repeatable=%d source_repeatable=%d', ...
    strcmp(artifactRepeat.sha256,artifactAfterModel.sha256), ...
    strcmp(sourceRepeat.sha256,sourceA.sha256)));

% The manifest classification must call a regenerated tracked model drift and a
% newly generated model a commit candidate.
assets=classify(fixture,fullfile(validation,'artifact_before.json'), ...
    cleanGit,fullfile(validation,'assets.json'));
dispositions=containers.Map();
entries=assets.entries;
for k=1:numel(entries)
    entry=entries(k);
    dispositions([entry.path '|' entry.class])=entry.disposition;
end
cases{end+1}=check_case('A-06','classifier separates commit candidates from layout drift', ...
    dispositions.isKey('models/plant/FMT_Demo.slx|model_asset') && ...
    strcmp(dispositions('models/plant/FMT_Demo.slx|model_asset'),'regenerated_by_run'), ...
    ['classified=' char(dispositions('models/plant/FMT_Demo.slx|model_asset'))]);

passed=sum(cellfun(@(c) strcmp(c.status,'PASS'),cases));
report=struct('scope','ARCHIVE_FINGERPRINT_RELIABILITY','status','FAIL', ...
    'fixture',fixture,'cases',{cases},'case_count',numel(cases),'passed_count',passed);
if passed==numel(cases), report.status='PASS'; end
file=fullfile(root,'work','validation','archive_reliability_report.json');
fid=fopen(file,'w'); cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));
for k=1:numel(cases)
    fprintf('%-5s %s  (%s)\n',cases{k}.id,cases{k}.status,cases{k}.detail);
end
assert(strcmp(report.status,'PASS'),'Flight:A06','Archive fingerprint reliability failed.');
end

function case_=check_case(id,title,ok,detail)
case_=struct('id',id,'title',title,'status','FAIL','detail',detail);
if ok, case_.status='PASS'; end
end

function result=sources(fixture,output)
run_python(fixture,'fingerprint_sources.py',{'--root',fixture,'--output',output});
result=jsondecode(fileread(output));
end

function result=artifacts(fixture,output)
run_python(fixture,'fingerprint_artifacts.py',{'--root',fixture,'--output',output});
result=jsondecode(fileread(output));
end

function result=classify(fixture,beforeFile,beforeGitFile,output)
run_python(fixture,'fingerprint_artifacts.py',{'--root',fixture,'--output', ...
    fullfile(fixture,'work','validation','artifact_classified.json'), ...
    '--before',beforeFile,'--before-git',beforeGitFile,'--classification',output});
result=jsondecode(fileread(output));
end

function run_python(fixture,script,arguments)
parts=[{'-B',fullfile(fixture,'tools',script)},arguments];
command=['python ' sprintf('"%s" ',parts{:})];
[status,message]=system(command);
assert(status==0,'Flight:A06','%s failed: %s',script,message);
end

function git(fixture,varargin)
command=['git -C "' fixture '" ' sprintf('%s ',varargin{:})];
[status,message]=system(command);
assert(status==0,'Flight:A06','git failed: %s',message);
end

function write_text(path,text)
fid=fopen(path,'w'); cleanup=onCleanup(@()fclose(fid));
fwrite(fid,text,'char');
end

function value=eol
value=sprintf('\n');
end
