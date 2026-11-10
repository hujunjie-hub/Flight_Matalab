function ds = fmt_default_input(entry)
%FMT_DEFAULT_INPUT Load the default recording or create the MIL command tape.
root = fileparts(fileparts(mfilename('fullpath')));
if strcmp(entry,'FMT_MILSIM')
    t = (0:0.0005:26)';
    commands = zeros(numel(t),2);
    % Each command is a one-tick pulse. Submit after the same upstream owner turns.
    % ARM completes only after the 2 s ground-confirmation dwell has declared
    % LANDED, and TAKEOFF must be accepted while that LANDED evidence still
    % holds; the pulses are spaced so both preconditions are satisfied.
    ticks = [8400 12000 28000 46000];
    commands(ticks,:) = [1 0; 3 2; 4 0; 2 0];
    ds = Simulink.SimulationData.Dataset;
    ds{1} = sample(t,commands);
else
    path = fullfile(root,'scenarios','flight_sil_recording.mat');
    data = load(path);
    meta = fmt_flight_metadata;
    assert(strcmp(data.revision,meta.product_contract_revision) && ...
        size(data.navigation,2)==meta.navigation_frame_bytes, ...
        'Flight:ReplayABI','Recording does not match the Flight navigation ABI.');
    ds = Simulink.SimulationData.Dataset;
    ds{1} = sample(data.t,data.sensor);
    ds{2} = sample(data.t,data.commands);
    if strcmp(entry,'FMT_ExtINS_DataSIM')
        ds{3} = sample(data.t,data.navigation);
    end
end
end

function signal = sample(t,data)
signal = timeseries(data,t);
signal = setinterpmethod(signal,'zoh');
end
