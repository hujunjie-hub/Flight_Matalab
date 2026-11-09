#define S_FUNCTION_NAME fmt_plant_sensors_sfun
#define S_FUNCTION_LEVEL 2
#include "simstruc.h"
#include <math.h>
#include <string.h>
#include "fmt_flight_runtime.h"
#include "../../models/plant/fmt_rotation.h"

static void mdlInitializeSizes(SimStruct *S)
{
    ssSetNumSFcnParams(S, 1);
    if (ssGetNumSFcnParams(S) != ssGetSFcnParamsCount(S)) return;
    ssSetSFcnParamTunable(S, 0, 0);
    if (!ssSetNumInputPorts(S, 2) || !ssSetNumOutputPorts(S, 1)) return;
    ssSetInputPortWidth(S, 0, 17);
    ssSetInputPortWidth(S, 1, 1);
    for (int i = 0; i < 2; ++i) {
        ssSetInputPortDirectFeedThrough(S, i, 1);
        ssSetInputPortRequiredContiguous(S, i, 1);
    }
    ssSetOutputPortWidth(S, 0, FMT_SENSOR_WIDTH);
    /* Previous velocity (3) and a first-difference-valid flag (1). */
    ssSetNumDiscStates(S, 4);
    ssSetNumSampleTimes(S, 1);
}

static void mdlInitializeSampleTimes(SimStruct *S)
{
    ssSetSampleTime(S, 0, .0005);
    ssSetOffsetTime(S, 0, 0);
}

#define MDL_INITIALIZE_CONDITIONS
static void mdlInitializeConditions(SimStruct *S)
{
    const mxArray *parameter = ssGetSFcnParam(S, 0);
    const double *p = mxGetPr(parameter);
    double *state = ssGetRealDiscStates(S);
    if (!mxIsDouble(parameter) || mxIsComplex(parameter) || mxIsSparse(parameter) ||
        mxGetNumberOfElements(parameter) != 10 || !p) {
        ssSetErrorStatus(S, "Sensor parameters must be [gravity; mag_NED(3); earth_rate_NED(3); initial_velocity_NED(3)].");
        return;
    }
    for (int i = 0; i < 10; ++i) {
        if (!isfinite(p[i])) {
            ssSetErrorStatus(S, "Sensor parameter contains a nonfinite value.");
            return;
        }
    }
    memcpy(state, p + 7, 3 * sizeof(double));
    state[3] = 0;
}

static void mdlOutputs(SimStruct *S, int_T tid)
{
    (void)tid;
    const mxArray *parameterArray = ssGetSFcnParam(S, 0);
    const double *parameter;
    const double *x = ssGetInputPortRealSignal(S, 0);
    const double *previous_velocity = ssGetRealDiscStates(S);
    const double gap = *ssGetInputPortRealSignal(S, 1);
    const double dt = ssGetSampleTime(S, 0);
    const double *field_ned_ut;
    const double *earth_rate_ned;
    double gravity, rotation[9], specific_force[3], coriolis[3];
    double *sensor = ssGetOutputPortRealSignal(S, 0);
    int imu_derivative_valid;

    if (!mxIsDouble(parameterArray) || mxIsComplex(parameterArray) ||
        mxIsSparse(parameterArray) || mxGetNumberOfElements(parameterArray) != 10 ||
        !(parameter = mxGetPr(parameterArray))) {
        ssSetErrorStatus(S, "Sensor parameters must contain exactly 10 doubles.");
        return;
    }
    if (!isfinite(dt) || dt <= 0 || !isfinite(gap)) {
        ssSetErrorStatus(S, "Invalid sensor sample interval or ground gap.");
        return;
    }
    for (int i = 0; i < 10; ++i) {
        if (!isfinite(parameter[i])) {
            ssSetErrorStatus(S, "Sensor parameter contains a nonfinite value.");
            return;
        }
    }
    for (int i = 0; i < 17; ++i) {
        if (!isfinite(x[i])) {
            ssSetErrorStatus(S, "Plant state contains a nonfinite value.");
            return;
        }
    }
    if (!fmt_rotation(x + 6, rotation)) {
        ssSetErrorStatus(S, "Plant attitude is invalid.");
        return;
    }

    gravity = parameter[0];
    field_ned_ut = parameter + 1;
    earth_rate_ned = parameter + 4;
    imu_derivative_valid = previous_velocity[3] > 0.5;
    for (int i = 0; i < 3; ++i) {
        specific_force[i] = imu_derivative_valid
            ? (x[i + 3] - previous_velocity[i]) / dt : 0.0;
        sensor[FMT_SENSOR_POSITION + i] = x[i];
        sensor[FMT_SENSOR_VELOCITY + i] = x[i + 3];
    }
    fmt_cross(earth_rate_ned, x + 3, coriolis);
    for (int i = 0; i < 3; ++i) specific_force[i] += 2.0 * coriolis[i];
    specific_force[2] -= gravity;

    for (int axis = 0; axis < 3; ++axis) {
        sensor[FMT_SENSOR_ACCEL + axis] = 0;
        sensor[FMT_SENSOR_GYRO + axis] = x[10 + axis];
        sensor[FMT_SENSOR_MAG + axis] = 0;
        for (int i = 0; i < 3; ++i) {
            const double c_body_from_ned = rotation[3 * i + axis];
            sensor[FMT_SENSOR_ACCEL + axis] += c_body_from_ned * specific_force[i];
            sensor[FMT_SENSOR_MAG + axis] += c_body_from_ned * field_ned_ut[i];
            sensor[FMT_SENSOR_GYRO + axis] += c_body_from_ned * earth_rate_ned[i];
        }
    }
    sensor[FMT_SENSOR_BARO] = -x[2];
    sensor[FMT_SENSOR_VALID] = FMT_GNSS_VALID | FMT_MAG_VALID | FMT_BARO_VALID;
    if (imu_derivative_valid) sensor[FMT_SENSOR_VALID] |= FMT_IMU_VALID;
    /* GroundContact: signed gap <= 1 mm and penetration <= 20 mm. */
    sensor[FMT_SENSOR_CONTACT] = (gap <= 0.001 && gap >= -0.02) ? 1.0 : 0.0;
}

#define MDL_UPDATE
static void mdlUpdate(SimStruct *S, int_T tid)
{
    (void)tid;
    double *state = ssGetRealDiscStates(S);
    const double *x = ssGetInputPortRealSignal(S, 0);
    memcpy(state, x + 3, 3 * sizeof(double));
    state[3] = 1;
}

static void mdlTerminate(SimStruct *S) { (void)S; }

#include "simulink.c"
