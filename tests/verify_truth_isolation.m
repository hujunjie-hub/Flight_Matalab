function report=verify_truth_isolation
%VERIFY_TRUTH_ISOLATION Ensure Plant truth reaches only sensor synthesis and evaluation.
root=flight_startup;
modelFile=fullfile(root,'simulation','FMT_MILSIM.slx');
assert(isfile(modelFile),'Flight:TruthModel','FMT_MILSIM model is missing.');
load_system(modelFile);

model='FMT_MILSIM';
plant=[model '/plant'];
sensor=[model '/sensor'];
flight=[model '/flight'];
assert(getSimulinkBlockHandle(plant)>0 && getSimulinkBlockHandle(sensor)>0 && ...
       getSimulinkBlockHandle(flight)>0,'Flight:TruthTopology', ...
    'Expected Plant, SimulatedSensors and FlightFirmware blocks.');

plantPorts=get_param(plant,'PortHandles');
sensorPorts=get_param(sensor,'PortHandles');
flightPorts=get_param(flight,'PortHandles');

plantStateSinks=destinations(plantPorts.Outport(1));
gapSinks=destinations(plantPorts.Outport(3));
sensorPlantSources={source(sensorPorts.Inport(1)),source(sensorPorts.Inport(2))};
flightSensorSource=source(flightPorts.Inport(1));

allowedStateSinks={[model '/sensor'],[model '/x']};
assert(all(ismember(plantStateSinks,allowedStateSinks)) && ...
       all(ismember(allowedStateSinks,plantStateSinks)), ...
    'Flight:TruthBypass','PlantState must feed exactly sensor synthesis and the read-only PlantState output.');
assert(all(strcmp(sensorPlantSources,[model '/plant'])), ...
    'Flight:SensorTruthSource','Both sensor-kine input ports must originate at the Plant model.');
assert(all(strcmp(gapSinks,[model '/sensor'])), ...
    'Flight:GapBypass','Ground-gap truth may feed only sensor synthesis.');
assert(strcmp(flightSensorSource,[model '/sensor']), ...
    'Flight:SensorEntry','FlightFirmware SensorFrame must originate from SimulatedSensors.');

% The Plant model may not reference the production Flight core or a controller.
plantModel='FMT_QuadPlant';
load_system(fullfile(root,'models','plant',[plantModel '.slx']));
references=find_system(plantModel,'SearchDepth',inf,'BlockType','ModelReference');
referencedModels=cell(size(references));
for k=1:numel(references)
    referencedModels{k}=get_param(references{k},'ModelName');
end
assert(~any(strcmp(referencedModels,'FMT_FlightCore')) && ...
       ~any(strcmp(referencedModels,'FMT_FlightFirmware')), ...
    'Flight:PlantControlDependency','Plant model contains a Flight/controller model reference.');

report=struct('scope','PLANT_TRUTH_ISOLATION','status','PASS', ...
    'plant_state_sinks',{plantStateSinks},'ground_gap_sinks',{gapSinks}, ...
    'sensor_plant_sources',{sensorPlantSources}, ...
    'flight_sensor_source',flightSensorSource, ...
    'direct_truth_to_navigation_or_control','NONE', ...
    'allowed_truth_consumers',{{'SimulatedSensors','read-only PlantState evaluator'}}, ...
    'plant_model_references',{referencedModels});
file=fullfile(root,'work','validation','truth_isolation_report.json');
if ~isfolder(fileparts(file)), mkdir(fileparts(file)); end
fid=fopen(file,'w');
assert(fid>=0,'Flight:TruthReport','Could not create truth-isolation report.');
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));
disp(report);
end

function names=destinations(port)
line=get_param(port,'Line');
if isempty(line) || line==-1
    names={};
    return;
end
handles=get_param(line,'DstBlockHandle');
handles=handles(handles>0);
names=cell(numel(handles),1);
for k=1:numel(handles)
    names{k}=getfullname(handles(k));
end
end

function name=source(port)
line=get_param(port,'Line');
assert(~isempty(line) && line~=-1,'Flight:TruthLine','Required model input is unconnected.');
handle=get_param(line,'SrcBlockHandle');
assert(handle>0,'Flight:TruthLine','Required model input has no source block.');
name=getfullname(handle);
end
