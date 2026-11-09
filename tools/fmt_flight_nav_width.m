function n = fmt_flight_nav_width
%FMT_FLIGHT_NAV_WIDTH Width of the native snapshot and capability frame.
meta = fmt_flight_metadata;
n = meta.navigation_frame_bytes;
end
