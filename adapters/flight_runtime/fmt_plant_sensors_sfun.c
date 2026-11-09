#define S_FUNCTION_NAME fmt_plant_sensors_sfun
#define S_FUNCTION_LEVEL 2
#include "simstruc.h"
#include <math.h>
#include <string.h>
#include "fmt_flight_runtime.h"
#include "../../models/plant/fmt_rotation.h"

/* SensorParameters (19):
 * gravity, magnetic_NED(3), earth_rate_NED(3), initial_velocity_NED(3),
 * initial_rate_FRD(3), imu_to_cg_FRD(3), antenna_from_imu_FRD(3).
 * The configured IMU lever arm is CG->IMU = -imu_to_cg. */
enum {
    SENSOR_PARAMETER_COUNT = 19,
    SENSOR_STATE_COUNT = 7,
    PARAM_GRAVITY = 0,
    PARAM_MAGNETIC_NED = 1,
    PARAM_EARTH_RATE_NED = 4,
    PARAM_INITIAL_VELOCITY = 7,
    PARAM_INITIAL_RATE = 10,
    PARAM_IMU_TO_CG = 13,
    PARAM_ANTENNA_FROM_IMU = 16
};

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
    /* Previous CG velocity (3), previous body rate (3), first-difference-valid. */
    ssSetNumDiscStates(S, SENSOR_STATE_COUNT);
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
    double *state = ssGetRealDiscStates(S);
    const double *p;

    if (!mxIsDouble(parameter) || mxIsComplex(parameter) || mxIsSparse(parameter) ||
        mxGetNumberOfElements(parameter) != SENSOR_PARAMETER_COUNT ||
        !(p = mxGetPr(parameter))) {
        ssSetErrorStatus(S, "SensorParameters must contain exactly 19 doubles.");
        return;
    }
    if (!fmt_finite_vector(p, SENSOR_PARAMETER_COUNT) || !(p[PARAM_GRAVITY] > 0.0)) {
        ssSetErrorStatus(S, "SensorParameters contain nonfinite values or invalid gravity.");
        return;
    }

    memcpy(state, p + PARAM_INITIAL_VELOCITY, 3 * sizeof(double));
    memcpy(state + 3, p + PARAM_INITIAL_RATE, 3 * sizeof(double));
    state[6] = 0.0;
}

static void mdlOutputs(SimStruct *S, int_T tid)
{
    (void)tid;
    const mxArray *parameterArray = ssGetSFcnParam(S, 0);
    const double *parameter;
    const double *x = ssGetInputPortRealSignal(S, 0);
    const double *previous = ssGetRealDiscStates(S);
    const double gap = *ssGetInputPortRealSignal(S, 1);
    const double dt = ssGetSampleTime(S, 0);
    const double *field_ned_ut;
    const double *earth_rate_ned;
    double gravity, rotation[9], omega_cross_imu[3], omega_cross_ant[3];
    double alpha_cross_imu[3], centripetal_imu[3], accel_imu_body[3];
    double accel_cg_ned[3], velocity_imu_ned[3], accel_imu_ned[3];
    double coriolis[3], specific_force_ned[3], lever_imu[3], lever_ant[3];
    double *sensor = ssGetOutputPortRealSignal(S, 0);
    int imu_derivative_valid;

    if (!mxIsDouble(parameterArray) || mxIsComplex(parameterArray) ||
        mxIsSparse(parameterArray) ||
        mxGetNumberOfElements(parameterArray) != SENSOR_PARAMETER_COUNT ||
        !(parameter = mxGetPr(parameterArray)) ||
        !fmt_finite_vector(parameter, SENSOR_PARAMETER_COUNT)) {
        ssSetErrorStatus(S, "SensorParameters must contain exactly 19 finite doubles.");
        return;
    }
    if (!isfinite(dt) || dt <= 0.0 || !isfinite(gap)) {
        ssSetErrorStatus(S, "Invalid sensor sample interval or ground gap.");
        return;
    }
    if (!fmt_finite_vector(x, 17) || !fmt_rotation(x + 6, rotation)) {
        ssSetErrorStatus(S, "Plant state or attitude is invalid for SensorKinematics.");
        return;
    }

    gravity = parameter[PARAM_GRAVITY];
    field_ned_ut = parameter + PARAM_MAGNETIC_NED;
    earth_rate_ned = parameter + PARAM_EARTH_RATE_NED;
    imu_derivative_valid = previous[6] > 0.5;

    for (int i = 0; i < 3; ++i) {
        lever_imu[i] = -parameter[PARAM_IMU_TO_CG + i];
        lever_ant[i] = lever_imu[i] + parameter[PARAM_ANTENNA_FROM_IMU + i];
        accel_cg_ned[i] = imu_derivative_valid
            ? (x[3 + i] - previous[i]) / dt : 0.0;
    }

    /* Rigid-body point kinematics at the IMU and GNSS antenna. */
    fmt_cross(x + 10, lever_imu, omega_cross_imu);
    fmt_cross(x + 10, lever_ant, omega_cross_ant);
    {
        double alpha_body[3];
        for (int i = 0; i < 3; ++i) {
            alpha_body[i] = imu_derivative_valid
                ? (x[10 + i] - previous[3 + i]) / dt : 0.0;
        }
        fmt_cross(alpha_body, lever_imu, alpha_cross_imu);
    }
    fmt_cross(x + 10, omega_cross_imu, centripetal_imu);
    for (int i = 0; i < 3; ++i) {
        accel_imu_body[i] = alpha_cross_imu[i] + centripetal_imu[i];
        velocity_imu_ned[i] = x[3 + i];
        accel_imu_ned[i] = accel_cg_ned[i];
        for (int j = 0; j < 3; ++j) {
            velocity_imu_ned[i] += rotation[3 * i + j] * omega_cross_imu[j];
            accel_imu_ned[i] += rotation[3 * i + j] * accel_imu_body[j];
        }
    }

    /* Specific force includes the fixed-N0 Coriolis term and gravity removal. */
    fmt_cross(earth_rate_ned, velocity_imu_ned, coriolis);
    for (int i = 0; i < 3; ++i) {
        specific_force_ned[i] = accel_imu_ned[i] + 2.0 * coriolis[i];
    }
    specific_force_ned[2] -= gravity;

    for (int axis = 0; axis < 3; ++axis) {
        double accel_body = 0.0;
        double gyro_body = x[10 + axis];
        double mag_body = 0.0;
        double antenna_position = x[axis];
        double antenna_velocity = x[3 + axis];
        for (int i = 0; i < 3; ++i) {
            const double c_body_from_ned = rotation[3 * i + axis];
            accel_body += c_body_from_ned * specific_force_ned[i];
            gyro_body += c_body_from_ned * earth_rate_ned[i];
            mag_body += c_body_from_ned * field_ned_ut[i];
            antenna_position += rotation[3 * axis + i] * lever_ant[i];
            antenna_velocity += rotation[3 * axis + i] * omega_cross_ant[i];
        }
        sensor[FMT_SENSOR_ACCEL + axis] = accel_body;
        sensor[FMT_SENSOR_GYRO + axis] = gyro_body;
        sensor[FMT_SENSOR_MAG + axis] = mag_body;
        sensor[FMT_SENSOR_POSITION + axis] = antenna_position;
        sensor[FMT_SENSOR_VELOCITY + axis] = antenna_velocity;
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
    memcpy(state + 3, x + 10, 3 * sizeof(double));
    state[6] = 1.0;
}

static void mdlTerminate(SimStruct *S) { (void)S; }

#include "simulink.c"
