function meta = fmt_flight_metadata
%FMT_FLIGHT_METADATA Contract data of the compiled sibling Flight baseline.
root = fileparts(fileparts(mfilename('fullpath')));
meta = jsondecode(fileread(fullfile(root,'config','flight_baseline.json')));
end
