function flight_shutdown
%FLIGHT_SHUTDOWN Restore the path captured when this project was opened.
if isappdata(0, 'FlightMatlabOriginalPath')
    path(getappdata(0, 'FlightMatlabOriginalPath'));
    rmappdata(0, 'FlightMatlabOriginalPath');
end
clear flight_startup
end
