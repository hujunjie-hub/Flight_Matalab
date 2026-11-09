function report = generate_contracts
%GENERATE_CONTRACTS Generate Host value buses from the production headers.
root = fileparts(fileparts(mfilename('fullpath')));
sources=jsondecode(fileread(fullfile(root,'config','firmware_sources.json')));
contracts = fullfile(root,sources.contracts_dir);
schemaDir = fullfile(root,'work','schema');
if ~isfolder(schemaDir), mkdir(schemaDir); end
dictionaryFile = fullfile(root,'dictionaries','Flight_Contracts.sldd');
info = Simulink.importExternalCTypes(fullfile(contracts,'messages','common_messages.h'), ...
    'IncludeDirs',{contracts,fullfile(root,sources.product_dir)}, ...
    'DataDictionary',dictionaryFile, ...
    'OutputDir',schemaDir,'Overwrite','on');
dictionary = Simulink.data.dictionary.open(dictionaryFile);
section = getSection(dictionary,'Design Data');
entries = find(section);
buses = struct;
for k = 1:numel(entries)
    value = getValue(entries(k));
    if isa(value,'Simulink.Bus')
        % Host values, not imported ABI objects or memory images.
        value.DataScope = 'Auto';
        value.HeaderFile = '';
        setValue(entries(k),value);
        elements = value.Elements;
        fields = repmat(struct('name','','type','','dimensions',[]),numel(elements),1);
        for j = 1:numel(elements)
            fields(j).name = elements(j).Name;
            fields(j).type = elements(j).DataType;
            fields(j).dimensions = elements(j).Dimensions;
        end
        buses.(entries(k).Name) = fields;
    end
end
required = {'ContractHeader','ImuSample','GnssSample','BaroSample','MagSample', ...
    'PpsCaptureEvent','GnssTimeObservation','TimeServiceStatus', ...
    'LocalTimebaseDisciplineStatus','NavigationSnapshot','NavigationCapability', ...
    'NavigationOriginSnapshot','VehicleDirective','ActuationPermit','SafetyEnvelope', ...
    'MotionReference','PilotControlReference','ActuatorDemand','ActuatorCommitReceipt'};
assert(all(isfield(buses,required)),'Flight:SchemaMissing','Required public bus missing.');
saveChanges(dictionary);
report = struct('scope','HOST_VALUE_TYPES','status','PASS','schema_major',6, ...
    'port_revision',sources.product_port_revision,'firmware_abi_equivalence',false, ...
    'pointer_views_imported',false,'buses',buses,'import_diagnostics',info.failedToImport);
fid = fopen(fullfile(root,'interfaces','contract_schema.json'),'w');
cleanup = onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));
fprintf('Generated %d public value buses.\n',numel(fieldnames(buses)));
end

