function root = flight_startup
%FLIGHT_STARTUP Add only this project's explicitly selected directories.
persistent savedPath activeRoot
root = fileparts(fileparts(mfilename('fullpath')));
if isempty(activeRoot)
    savedPath = path;
    activeRoot = root;
    setappdata(0, 'FlightMatlabOriginalPath', savedPath);
end
folders = {'tools','interfaces','models/core','models/flight','models/plant','models/lib', ...
    'simulation','dictionaries','work/mex','adapters/kf_gins_matlab','tests','tests/g1/models','tests/g2/models'};
for k = 1:numel(folders)
    folder = fullfile(root, folders{k});
    if isfolder(folder) && ~contains([path pathsep], [folder pathsep])
        addpath(folder);
    end
end
end

