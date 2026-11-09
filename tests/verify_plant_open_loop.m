function report=verify_plant_open_loop
%VERIFY_PLANT_OPEN_LOOP Check signs and physics using the actual Simulink plant.
root=fileparts(fileparts(mfilename('fullpath')));
cfg=generate_parameters; g=cfg.derived.GravityMps2;
initial=cfg.derived.PlantState0;
environment=[zeros(1,9),0,0,ones(1,4)];
results={};

out=run('FMT_RotorWrench',{ones(1,4)},0.001,struct);
wrench=out.yout{1}.Values.Data(end,:);
assert(norm(wrench-[0 0 -4 0 0 0],inf)<1e-10,'Flight:P02','Symmetric rotor wrench failed.');
results{end+1}=passed('P-02','Symmetric force and torque');
out=run('FMT_RotorWrench',{[1 0 0 0]},0.001,struct);
wrench=out.yout{1}.Values.Data(end,:);
expected=cfg.derived.WrenchMatrix(:,1)';
assert(norm(wrench-expected,inf)<1e-10,'Flight:P03','Front-left torque signs failed.');
results{end+1}=passed('P-03','Front-left motor torque signs');

out=run('FMT_QuadPlant',{zeros(1,4),environment},.1,struct('PlantState0',initial));
state=out.yout{1}.Values.Data(end,:);
assert(abs(state(3)-.5*g*.1^2)<1e-6 && abs(state(6)-g*.1)<1e-6,'Flight:P04','Free-fall analytical solution failed.');
results{end+1}=passed('P-04','Free fall without drag/contact');

hover=cfg.vehicle_model.mass_kg*g/4; initial(14:17)=sqrt(hover/cfg.derived.MotorKf);
out=run('FMT_QuadPlant',{hover*ones(1,4),environment},2,struct('PlantState0',initial));
state=out.yout{1}.Values.Data;
assert(max(abs(state(:,4:6)),[],'all')<1e-6,'Flight:P05','Constant mg thrust did not balance gravity.');
results{end+1}=passed('P-05','Hover force with initialized motor speed');

initial=cfg.derived.PlantState0;
out=run('FMT_QuadPlant',{5*ones(1,4),environment},1,struct('PlantState0',initial));
omega=out.yout{1}.Values.Data(:,14:17);
assert(all(diff(omega)>=-1e-10,'all'),'Flight:P01','Motor response was not monotone.');
index=find(out.tout>=5*cfg.derived.MotorTau,1);
target=sqrt(5/cfg.derived.MotorKf);
assert(max(abs(omega(index,:)-target))/target<.01,'Flight:P01','Motor speed failed 5-tau bound.');
results{end+1}=passed('P-01','First-order rotor speed step');

initial(7:10)=[cos(pi/6);0;0;sin(pi/6)]; initial(11:13)=[.3;.2;.1];
positive=run('FMT_QuadPlant',{zeros(1,4),environment},.2,struct('PlantState0',initial));
initial(7:10)=-initial(7:10);
negative=run('FMT_QuadPlant',{zeros(1,4),environment},.2,struct('PlantState0',initial));
pos=positive.yout{1}.Values.Data; neg=negative.yout{1}.Values.Data;
assert(max(abs(pos(:,1:6)-neg(:,1:6)),[],'all')<1e-12 && ...
    max(abs(pos(:,7:10)+neg(:,7:10)),[],'all')<1e-12,'Flight:P06','q/-q physical equivalence failed.');
assert(max(abs(vecnorm(pos(:,7:10),2,2)-1))<1e-6,'Flight:P06','Quaternion normalization failed.');
results{end+1}=passed('P-06','Quaternion sign invariance and norm');

initial=cfg.derived.PlantState0;initial(3)=-.01;initial(6)=1;
contactEnvironment=environment;contactEnvironment(10)=1;
out=run('FMT_GroundRHS',{initial',contactEnvironment},.001,struct);
assert(all(out.yout{3}.Values.Data==0,'all'),'Flight:P15','Contact damping acted above ground.');
results{end+1}=passed('P-15','No normal force 1cm above ground while descending');

initial=cfg.derived.PlantState0;initial(3)=-.1;
out=run('FMT_QuadPlant',{zeros(1,4),contactEnvironment},2,struct('PlantState0',initial));
gap=out.yout{3}.Values.Data; normal=out.yout{2}.Values.Data;
assert(all(isfinite(out.yout{1}.Values.Data),'all') && all(normal>=0),'Flight:P11','Invalid contact response.');
penetration=max(0,-min(gap));
assert(penetration<.02,'Flight:P11','Contact penetration exceeded 2cm: %g.',penetration);
results{end+1}=struct('id','P-11','status','PASS','max_penetration_m',penetration);

report=struct('scope','PLANT_COMPONENT_OPEN_LOOP','status','PASS','tests',{results}, ...
    'all_P01_P16_accepted',false,'system_closed_loop','NOT_RUN','gravity_mps2',g);
fid=fopen(fullfile(root,'work','validation','plant_open_loop_report.json'),'w');
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'%s\n',jsonencode(report,PrettyPrint=true));
disp(report);
end

function out=run(model,signals,stop,variables)
ds=Simulink.SimulationData.Dataset;
for k=1:numel(signals), ds{k}=timeseries([signals{k};signals{k}],[0;stop]); end
in=Simulink.SimulationInput(model);in=in.setExternalInput(ds);
in=in.setModelParameter('StopTime',num2str(stop));
names=fieldnames(variables);
for k=1:numel(names),in=in.setVariable(names{k},variables.(names{k}));end
out=sim(in);
assert(abs(out.tout(end)-stop)<1e-12,'Flight:PlantEarlyStop','Plant run ended early.');
end

function result=passed(id,description)
result=struct('id',id,'status','PASS','description',description);
end

