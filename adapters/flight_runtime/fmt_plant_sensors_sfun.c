#define S_FUNCTION_NAME fmt_plant_sensors_sfun
#define S_FUNCTION_LEVEL 2
#include "simstruc.h"
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
    ssSetNumDiscStates(S, 3);
    ssSetNumSampleTimes(S, 1);
}

static void mdlInitializeSampleTimes(SimStruct *S)
{
    ssSetSampleTime(S, 0, .0005);
    ssSetOffsetTime(S, 0, 0);
}

static void mdlOutputs(SimStruct *S, int_T tid)
{
    (void)tid;
    const double *x = ssGetInputPortRealSignal(S, 0);
    const double *previous_velocity = ssGetRealDiscStates(S);
    const double gap = *ssGetInputPortRealSignal(S, 1);
    const double field[] = {20, 5, 42};
    double rotation[9], specific_force[3];
    double *sensor = ssGetOutputPortRealSignal(S, 0);
    if (!fmt_rotation(x + 6, rotation)) {
        ssSetErrorStatus(S, "Plant attitude is invalid.");
        return;
    }
    for (int i = 0; i < 3; ++i) {
        specific_force[i] = (x[i + 3] - previous_velocity[i]) / .0005;
        sensor[FMT_SENSOR_POSITION + i] = x[i];
        sensor[FMT_SENSOR_VELOCITY + i] = x[i + 3];
        sensor[FMT_SENSOR_GYRO + i] = x[i + 10];
    }
    specific_force[2] -= mxGetScalar(ssGetSFcnParam(S, 0));
    for (int axis = 0; axis < 3; ++axis) {
        sensor[FMT_SENSOR_ACCEL + axis] = 0;
        sensor[FMT_SENSOR_MAG + axis] = 0;
        for (int i = 0; i < 3; ++i) {
            sensor[FMT_SENSOR_ACCEL + axis] += rotation[3*i + axis] * specific_force[i];
            sensor[FMT_SENSOR_MAG + axis] += rotation[3*i + axis] * field[i];
        }
    }
    sensor[FMT_SENSOR_BARO] = -x[2];
    sensor[FMT_SENSOR_VALID] = FMT_IMU_VALID | FMT_GNSS_VALID | FMT_MAG_VALID | FMT_BARO_VALID;
    sensor[FMT_SENSOR_CONTACT] = gap < .06 && fabs(x[5]) < .2;
}

#define MDL_UPDATE
static void mdlUpdate(SimStruct *S, int_T tid)
{
    (void)tid;
    memcpy(ssGetRealDiscStates(S), ssGetInputPortRealSignal(S, 0) + 3, 3 * sizeof(double));
}

static void mdlTerminate(SimStruct *S) { (void)S; }

#include "simulink.c"
