#include "mex.h"
#include "fmt_sensor_simulation.h"
#include "fmt_flight_runtime.h"

#include <math.h>
#include <stdint.h>
#include <string.h>

static int is_real_dense_double(const mxArray *value)
{
    return mxIsDouble(value) && !mxIsComplex(value) && !mxIsSparse(value);
}

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    const mxArray *truth_array, *parameter_array, *time_array, *epoch_array;
    const double *truth, *parameters, *times, *epoch_value;
    double *frames, *events;
    mwSize rows, columns;
    uint64_t epoch_us;
    FmtSensorSimState state;

    if (nrhs != 4 || nlhs != 2)
        mexErrMsgIdAndTxt("Flight:SensorProbeArguments",
            "Usage: [frames,events]=fmt_sensor_sim_probe(truth18,parameters54,times_us,epoch_us).");
    truth_array = prhs[0];
    parameter_array = prhs[1];
    time_array = prhs[2];
    epoch_array = prhs[3];
    if (!is_real_dense_double(truth_array) ||
        !is_real_dense_double(parameter_array) ||
        !is_real_dense_double(time_array) ||
        !is_real_dense_double(epoch_array))
        mexErrMsgIdAndTxt("Flight:SensorProbeType","All inputs must be real, dense doubles.");

    rows = mxGetM(truth_array);
    columns = mxGetN(truth_array);
    if (columns != 18 || rows == 0 ||
        mxGetNumberOfElements(parameter_array) != FMT_SENSOR_SIM_PARAMETER_COUNT ||
        mxGetNumberOfElements(time_array) != rows ||
        mxGetNumberOfElements(epoch_array) != 1)
        mexErrMsgIdAndTxt("Flight:SensorProbeShape",
            "Expected truth N-by-18, 54 parameters, N times and one epoch.");

    truth = mxGetPr(truth_array);
    parameters = mxGetPr(parameter_array);
    times = mxGetPr(time_array);
    epoch_value = mxGetPr(epoch_array);
    if (!isfinite(*epoch_value) || *epoch_value < 0.0 ||
        floor(*epoch_value) != *epoch_value || *epoch_value > 9.0e15)
        mexErrMsgIdAndTxt("Flight:SensorProbeEpoch","Epoch must be an integer microsecond timestamp.");
    epoch_us = (uint64_t)*epoch_value;
    if (fmt_sensor_sim_init(&state, parameters, epoch_us) != 0)
        mexErrMsgIdAndTxt("Flight:SensorProbeParameters","Sensor simulation parameters are invalid.");

    plhs[0] = mxCreateDoubleMatrix(rows, 18, mxREAL);
    plhs[1] = mxCreateDoubleMatrix(rows, 16, mxREAL);
    frames = mxGetPr(plhs[0]);
    events = mxGetPr(plhs[1]);

    for (mwSize row = 0; row < rows; ++row) {
        double input[18], frame[18] = {0};
        FmtSensorSimEvent due[4];
        const double time_value = times[row];
        if (!isfinite(time_value) || time_value < 0.0 ||
            floor(time_value) != time_value || time_value > 9.0e15)
            mexErrMsgIdAndTxt("Flight:SensorProbeTime","Times must be integer microseconds.");
        for (unsigned column = 0; column < 18; ++column)
            input[column] = truth[row + rows * column];
        if (fmt_sensor_sim_step(&state, input, (uint64_t)time_value, due) != 0)
            mexErrMsgIdAndTxt("Flight:SensorProbeStep","Sensor event queue failed.");

        frame[FMT_SENSOR_CONTACT] = input[FMT_SENSOR_CONTACT];
        for (unsigned channel = 0; channel < 4; ++channel) {
            const FmtSensorSimEvent *event = &due[channel];
            const mwSize event_base = row + rows * (channel * 4u);
            if (!event->valid) continue;
            events[event_base] = 1.0;
            events[row + rows * (channel * 4u + 1u)] = (double)event->sample_us;
            events[row + rows * (channel * 4u + 2u)] = (double)event->capture_us;
            events[row + rows * (channel * 4u + 3u)] = (double)event->arrival_us;
            switch (channel) {
            case FMT_SENSOR_SIM_IMU:
                memcpy(frame + FMT_SENSOR_GYRO, event->values, 3u * sizeof(double));
                memcpy(frame + FMT_SENSOR_ACCEL, event->values + 3, 3u * sizeof(double));
                frame[FMT_SENSOR_VALID] |= FMT_IMU_VALID;
                break;
            case FMT_SENSOR_SIM_GNSS:
                memcpy(frame + FMT_SENSOR_POSITION, event->values, 3u * sizeof(double));
                memcpy(frame + FMT_SENSOR_VELOCITY, event->values + 3, 3u * sizeof(double));
                frame[FMT_SENSOR_VALID] |= FMT_GNSS_VALID;
                break;
            case FMT_SENSOR_SIM_MAG:
                memcpy(frame + FMT_SENSOR_MAG, event->values, 3u * sizeof(double));
                frame[FMT_SENSOR_VALID] |= FMT_MAG_VALID;
                break;
            case FMT_SENSOR_SIM_BARO:
                frame[FMT_SENSOR_BARO] = event->values[0];
                frame[FMT_SENSOR_VALID] |= FMT_BARO_VALID;
                break;
            default:
                mexErrMsgIdAndTxt("Flight:SensorProbeChannel","Unknown sensor channel.");
            }
        }
        for (unsigned column = 0; column < 18; ++column)
            frames[row + rows * column] = frame[column];
    }
}
