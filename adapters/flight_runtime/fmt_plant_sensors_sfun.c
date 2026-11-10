#define S_FUNCTION_NAME fmt_plant_sensors_sfun
#define S_FUNCTION_LEVEL 2
#include "simstruc.h"
#include <math.h>
#include <stdint.h>
#include <string.h>
#include "fmt_flight_runtime.h"
#include "../../models/plant/fmt_rotation.h"
#include "../../models/plant/fmt_plant_validation.h"

/* SensorParameters (19):
 * gravity, magnetic_NED(3), earth_rate_NED(3), initial_velocity_NED(3),
 * initial_rate_FRD(3), imu_to_cg_FRD(3), antenna_from_imu_FRD(3).
 *
 * SensorModelParameters (54):
 * seed, imu_installation(9 row-major), mag_installation(9 row-major),
 * gyro_bias(3), accel_bias(3), mag_bias(3), gyro_scale_error(3),
 * accel_scale_error(3), mag_scale_error(3), gyro_noise_std(3),
 * accel_noise_std(3), mag_noise_std(3), gnss_position_noise_std(3),
 * gnss_velocity_noise_std(3), baro_noise_std, baro_bias.
 *
 * Bias/scale/noise values are residual errors at the M2 standard-sample exit.
 * Installation matrices map sensor axes into body FRD. Random samples are
 * stateless functions of seed/source/sample-index/axis, never RK4 call count. */
enum {
    SENSOR_PARAMETER_COUNT = 19,
    SENSOR_MODEL_PARAMETER_COUNT = 54,
    SENSOR_STATE_COUNT = 8,
    PARAM_GRAVITY = 0,
    PARAM_MAGNETIC_NED = 1,
    PARAM_EARTH_RATE_NED = 4,
    PARAM_INITIAL_VELOCITY = 7,
    PARAM_INITIAL_RATE = 10,
    PARAM_IMU_TO_CG = 13,
    PARAM_ANTENNA_FROM_IMU = 16
};

enum {
    MODEL_SEED = 0,
    MODEL_IMU_INSTALLATION = 1,
    MODEL_MAG_INSTALLATION = 10,
    MODEL_GYRO_BIAS = 19,
    MODEL_ACCEL_BIAS = 22,
    MODEL_MAG_BIAS = 25,
    MODEL_GYRO_SCALE = 28,
    MODEL_ACCEL_SCALE = 31,
    MODEL_MAG_SCALE = 34,
    MODEL_GYRO_NOISE = 37,
    MODEL_ACCEL_NOISE = 40,
    MODEL_MAG_NOISE = 43,
    MODEL_GNSS_POSITION_NOISE = 46,
    MODEL_GNSS_VELOCITY_NOISE = 49,
    MODEL_BARO_NOISE = 52,
    MODEL_BARO_BIAS = 53
};

enum {
    NOISE_GYRO = 1,
    NOISE_ACCEL = 2,
    NOISE_MAG = 3,
    NOISE_GNSS_POSITION = 4,
    NOISE_GNSS_VELOCITY = 5,
    NOISE_BARO = 6
};

static uint64_t fmt_mix64(uint64_t value)
{
    value += UINT64_C(0x9e3779b97f4a7c15);
    value = (value ^ (value >> 30)) * UINT64_C(0xbf58476d1ce4e5b9);
    value = (value ^ (value >> 27)) * UINT64_C(0x94d049bb133111eb);
    return value ^ (value >> 31);
}

static double fmt_uniform_open(uint64_t key)
{
    const uint64_t mantissa = fmt_mix64(key) >> 11;
    return ((double)mantissa + 0.5) * (1.0 / 9007199254740992.0);
}

static double fmt_gaussian(uint64_t seed, uint64_t source,
                           uint64_t sample_index, uint64_t axis)
{
    const uint64_t key = seed ^
        (source * UINT64_C(0xd6e8feb86659fd93)) ^
        (sample_index * UINT64_C(0xa0761d6478bd642f)) ^
        (axis * UINT64_C(0xe7037ed1a0b428db));
    const double u1 = fmt_uniform_open(key);
    const double u2 = fmt_uniform_open(key ^ UINT64_C(0x8ebc6af09c88c6e3));
    return sqrt(-2.0 * log(u1)) * cos(6.28318530717958647692 * u2);
}

static uint64_t fmt_sample_index(double time_s, double rate_hz)
{
    const double index = floor(time_s * rate_hz + 1e-9);
    if (!isfinite(index) || index <= 0.0) return 0;
    return (uint64_t)index;
}

/* True only on a configured IMU sample boundary (time in seconds, period in us).
 * The Plant advances every 500 us, but the sensor history must advance only
 * when a new physical IMU sample is produced. */
static int fmt_is_imu_sample_epoch(double time_s, double period_us)
{
    double time_us, sample_index;

    if (!isfinite(time_s) || time_s < 0.0 ||
        !isfinite(period_us) || period_us < 1.0)
        return 0;

    time_us = time_s * 1000000.0;
    if (!isfinite(time_us)) return 0;
    sample_index = floor(time_us / period_us + 0.5);
    return sample_index >= 1.0 &&
           fabs(time_us - sample_index * period_us) <= 1e-2;
}

static int fmt_rotation_matrix_valid(const double *m)
{
    double determinant;
    for (int row = 0; row < 3; ++row) {
        for (int column = 0; column < 3; ++column) {
            double dot = 0.0;
            for (int k = 0; k < 3; ++k)
                dot += m[3 * k + row] * m[3 * k + column];
            if (fabs(dot - (row == column ? 1.0 : 0.0)) > 1e-6)
                return 0;
        }
    }
    determinant =
        m[0] * (m[4] * m[8] - m[5] * m[7]) -
        m[1] * (m[3] * m[8] - m[5] * m[6]) +
        m[2] * (m[3] * m[7] - m[4] * m[6]);
    return isfinite(determinant) && fabs(determinant - 1.0) <= 1e-6;
}

static int fmt_sensor_timing_parameters_valid(const double *p)
{
    if (!fmt_finite_vector(p, FMT_SENSOR_SIM_PARAMETER_COUNT)) return 0;
    for (int i = 0; i < 4; ++i) {
        const double minimum = i == 0 ? 1000.0 : 500.0;
        const double alignment = i == 0 ? 1000.0 : 500.0;
        if (p[i] < minimum || floor(p[i]) != p[i] || fmod(p[i], alignment) != 0.0)
            return 0;
    }
    for (int i = 4; i < FMT_SENSOR_SIM_PARAMETER_COUNT; ++i) {
        if (p[i] < 0.0 || floor(p[i]) != p[i]) return 0;
    }
    return 1;
}

static int fmt_sensor_model_parameters_valid(const double *p)
{
    if (!fmt_finite_vector(p, SENSOR_MODEL_PARAMETER_COUNT) ||
        p[MODEL_SEED] < 1.0 || p[MODEL_SEED] > 4294967295.0 ||
        floor(p[MODEL_SEED]) != p[MODEL_SEED] ||
        !fmt_rotation_matrix_valid(p + MODEL_IMU_INSTALLATION) ||
        !fmt_rotation_matrix_valid(p + MODEL_MAG_INSTALLATION))
        return 0;

    for (int i = MODEL_GYRO_SCALE; i < MODEL_GYRO_NOISE; ++i) {
        if (p[i] <= -1.0 || fabs(p[i]) > 0.5) return 0;
    }
    for (int i = MODEL_GYRO_NOISE; i <= MODEL_BARO_NOISE; ++i) {
        if (p[i] < 0.0) return 0;
    }
    return 1;
}

/* R_bi maps sensor-frame vectors into body FRD. */
static void fmt_body_to_sensor(const double *r_bi, const double *body, double *sensor)
{
    for (int axis = 0; axis < 3; ++axis) {
        sensor[axis] = 0.0;
        for (int i = 0; i < 3; ++i)
            sensor[axis] += r_bi[3 * i + axis] * body[i];
    }
}

static void fmt_sensor_to_body(const double *r_bi, const double *sensor, double *body)
{
    for (int axis = 0; axis < 3; ++axis) {
        body[axis] = 0.0;
        for (int i = 0; i < 3; ++i)
            body[axis] += r_bi[3 * axis + i] * sensor[i];
    }
}

static void fmt_measure_vector(const double *ideal_body, const double *installation,
                               const double *bias, const double *scale_error,
                               const double *noise_std, uint64_t seed, uint64_t source,
                               uint64_t sample_index, double *measured_body)
{
    double ideal_sensor[3], measured_sensor[3];
    fmt_body_to_sensor(installation, ideal_body, ideal_sensor);
    for (int axis = 0; axis < 3; ++axis) {
        measured_sensor[axis] = ideal_sensor[axis] * (1.0 + scale_error[axis]) +
            bias[axis] + noise_std[axis] *
            fmt_gaussian(seed, source, sample_index, (uint64_t)axis);
    }
    fmt_sensor_to_body(installation, measured_sensor, measured_body);
}

static void mdlInitializeSizes(SimStruct *S)
{
    ssSetNumSFcnParams(S, 3);
    if (ssGetNumSFcnParams(S) != ssGetSFcnParamsCount(S)) return;
    ssSetSFcnParamTunable(S, 0, 0);
    ssSetSFcnParamTunable(S, 1, 0);
    ssSetSFcnParamTunable(S, 2, 0);
    if (!ssSetNumInputPorts(S, 2) || !ssSetNumOutputPorts(S, 1)) return;
    ssSetInputPortWidth(S, 0, 17);
    ssSetInputPortWidth(S, 1, 1);
    for (int i = 0; i < 2; ++i) {
        ssSetInputPortDirectFeedThrough(S, i, 1);
        ssSetInputPortRequiredContiguous(S, i, 1);
    }
    ssSetOutputPortWidth(S, 0, FMT_SENSOR_WIDTH);
    /* Previous sample CG velocity (3), body rate (3), valid flag, sample time (s). */
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
    const mxArray *modelParameter = ssGetSFcnParam(S, 1);
    const mxArray *timingParameter = ssGetSFcnParam(S, 2);
    double *state = ssGetRealDiscStates(S);
    const double *p;
    const double *m;
    const double *t;

    if (!mxIsDouble(parameter) || mxIsComplex(parameter) || mxIsSparse(parameter) ||
        mxGetNumberOfElements(parameter) != SENSOR_PARAMETER_COUNT ||
        !(p = mxGetPr(parameter))) {
        ssSetErrorStatus(S, "SensorParameters must contain exactly 19 doubles.");
        return;
    }
    if (!mxIsDouble(modelParameter) || mxIsComplex(modelParameter) || mxIsSparse(modelParameter) ||
        mxGetNumberOfElements(modelParameter) != SENSOR_MODEL_PARAMETER_COUNT ||
        !(m = mxGetPr(modelParameter))) {
        ssSetErrorStatus(S, "SensorModelParameters must contain exactly 54 doubles.");
        return;
    }
    if (!mxIsDouble(timingParameter) || mxIsComplex(timingParameter) ||
        mxIsSparse(timingParameter) ||
        mxGetNumberOfElements(timingParameter) != FMT_SENSOR_SIM_PARAMETER_COUNT ||
        !(t = mxGetPr(timingParameter)) || !fmt_sensor_timing_parameters_valid(t)) {
        ssSetErrorStatus(S, "SensorTimingParameters must contain 10 valid timing values.");
        return;
    }
    if (!fmt_finite_vector(p, SENSOR_PARAMETER_COUNT) || !(p[PARAM_GRAVITY] > 0.0) ||
        !fmt_sensor_model_parameters_valid(m)) {
        ssSetErrorStatus(S, "Sensor parameters contain nonfinite or physically invalid values.");
        return;
    }

    memcpy(state, p + PARAM_INITIAL_VELOCITY, 3 * sizeof(double));
    memcpy(state + 3, p + PARAM_INITIAL_RATE, 3 * sizeof(double));
    /* SensorParameters are generated from PlantState0, so t=0 is a valid
     * previous sample for the first configured IMU epoch. */
    state[6] = 1.0;
    state[7] = 0.0;
}

static void mdlOutputs(SimStruct *S, int_T tid)
{
    (void)tid;
    const mxArray *parameterArray = ssGetSFcnParam(S, 0);
    const mxArray *modelParameterArray = ssGetSFcnParam(S, 1);
    const mxArray *timingParameterArray = ssGetSFcnParam(S, 2);
    const double *parameter;
    const double *modelParameter;
    const double *timingParameter;
    const double *x = ssGetInputPortRealSignal(S, 0);
    const double *previous = ssGetRealDiscStates(S);
    const double gap = *ssGetInputPortRealSignal(S, 1);
    const double current_time_s = ssGetT(S);
    const double *field_ned_ut;
    const double *earth_rate_ned;
    double gravity, rotation[9], omega_cross_imu[3], omega_cross_ant[3];
    double alpha_cross_imu[3], centripetal_imu[3], accel_imu_body[3];
    double accel_cg_ned[3], velocity_imu_ned[3], accel_imu_ned[3];
    double coriolis[3], specific_force_ned[3], lever_imu[3], lever_ant[3];
    double gyro_ideal_body[3], accel_ideal_body[3], mag_ideal_body[3];
    double gyro_measured_body[3], accel_measured_body[3], mag_measured_body[3];
    double *sensor = ssGetOutputPortRealSignal(S, 0);
    double imu_interval_s;
    uint64_t seed, imu_index, slow_index, gnss_index, baro_index;
    int imu_derivative_valid;
    uint32_t validity_mask;

    if (!mxIsDouble(parameterArray) || mxIsComplex(parameterArray) ||
        mxIsSparse(parameterArray) ||
        mxGetNumberOfElements(parameterArray) != SENSOR_PARAMETER_COUNT ||
        !(parameter = mxGetPr(parameterArray)) ||
        !mxIsDouble(modelParameterArray) || mxIsComplex(modelParameterArray) ||
        mxIsSparse(modelParameterArray) ||
        mxGetNumberOfElements(modelParameterArray) != SENSOR_MODEL_PARAMETER_COUNT ||
        !(modelParameter = mxGetPr(modelParameterArray)) ||
        !mxIsDouble(timingParameterArray) || mxIsComplex(timingParameterArray) ||
        mxIsSparse(timingParameterArray) ||
        mxGetNumberOfElements(timingParameterArray) != FMT_SENSOR_SIM_PARAMETER_COUNT ||
        !(timingParameter = mxGetPr(timingParameterArray)) ||
        !fmt_finite_vector(parameter, SENSOR_PARAMETER_COUNT) ||
        !fmt_sensor_model_parameters_valid(modelParameter) ||
        !fmt_sensor_timing_parameters_valid(timingParameter)) {
        ssSetErrorStatus(S, "Sensor parameter vectors are invalid.");
        return;
    }
    if (!(parameter[PARAM_GRAVITY] > 0.0) || !isfinite(current_time_s) ||
        current_time_s < 0.0 || !isfinite(gap) ||
        !fmt_finite_vector(previous, SENSOR_STATE_COUNT)) {
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
    seed = (uint64_t)modelParameter[MODEL_SEED];
    /* Rates are tied to physical sensor sample periods, not Plant RK4 stages. */
    imu_index = fmt_sample_index(ssGetT(S), 1000000.0 / timingParameter[FMT_TIMING_IMU_PERIOD]);
    slow_index = fmt_sample_index(ssGetT(S), 1000000.0 / timingParameter[FMT_TIMING_MAG_PERIOD]);
    gnss_index = fmt_sample_index(ssGetT(S), 1000000.0 / timingParameter[FMT_TIMING_GNSS_PERIOD]);
    baro_index = fmt_sample_index(ssGetT(S), 1000000.0 / timingParameter[FMT_TIMING_BARO_PERIOD]);
    imu_interval_s = current_time_s - previous[7];
    imu_derivative_valid = previous[6] > 0.5 &&
        fmt_is_imu_sample_epoch(current_time_s,
            timingParameter[FMT_TIMING_IMU_PERIOD]) &&
        isfinite(imu_interval_s) && imu_interval_s > 0.0;

    for (int i = 0; i < 3; ++i) {
        lever_imu[i] = -parameter[PARAM_IMU_TO_CG + i];
        lever_ant[i] = lever_imu[i] + parameter[PARAM_ANTENNA_FROM_IMU + i];
        accel_cg_ned[i] = imu_derivative_valid
            ? (x[3 + i] - previous[i]) / imu_interval_s : 0.0;
    }

    /* Rigid-body point kinematics at the IMU and GNSS antenna. */
    fmt_cross(x + 10, lever_imu, omega_cross_imu);
    fmt_cross(x + 10, lever_ant, omega_cross_ant);
    {
        double alpha_body[3];
        for (int i = 0; i < 3; ++i) {
            alpha_body[i] = imu_derivative_valid
                ? (x[10 + i] - previous[3 + i]) / imu_interval_s : 0.0;
        }
        fmt_cross(alpha_body, lever_imu, alpha_cross_imu);
    }
    fmt_cross(x + 10, omega_cross_imu, centripetal_imu);
    /* The lever-arm acceleration must be complete before the body-to-NED
     * assembly below reads all three of its components; filling it inside
     * that loop would read uninitialized entries for axes that have not been
     * visited yet. */
    for (int i = 0; i < 3; ++i)
        accel_imu_body[i] = alpha_cross_imu[i] + centripetal_imu[i];
    for (int i = 0; i < 3; ++i) {
        velocity_imu_ned[i] = x[3 + i];
        accel_imu_ned[i] = accel_cg_ned[i];
        for (int j = 0; j < 3; ++j) {
            velocity_imu_ned[i] += rotation[3 * i + j] * omega_cross_imu[j];
            accel_imu_ned[i] += rotation[3 * i + j] * accel_imu_body[j];
        }
    }

    /* Specific force includes the fixed-N0 Coriolis term and gravity removal. */
    fmt_cross(earth_rate_ned, velocity_imu_ned, coriolis);
    for (int i = 0; i < 3; ++i)
        specific_force_ned[i] = accel_imu_ned[i] + 2.0 * coriolis[i];
    specific_force_ned[2] -= gravity;

    for (int axis = 0; axis < 3; ++axis) {
        gyro_ideal_body[axis] = x[10 + axis];
        accel_ideal_body[axis] = 0.0;
        mag_ideal_body[axis] = 0.0;
        for (int i = 0; i < 3; ++i) {
            const double c_body_from_ned = rotation[3 * i + axis];
            gyro_ideal_body[axis] += c_body_from_ned * earth_rate_ned[i];
            accel_ideal_body[axis] += c_body_from_ned * specific_force_ned[i];
            mag_ideal_body[axis] += c_body_from_ned * field_ned_ut[i];
        }
    }

    fmt_measure_vector(gyro_ideal_body, modelParameter + MODEL_IMU_INSTALLATION,
        modelParameter + MODEL_GYRO_BIAS, modelParameter + MODEL_GYRO_SCALE,
        modelParameter + MODEL_GYRO_NOISE, seed, NOISE_GYRO, imu_index, gyro_measured_body);
    fmt_measure_vector(accel_ideal_body, modelParameter + MODEL_IMU_INSTALLATION,
        modelParameter + MODEL_ACCEL_BIAS, modelParameter + MODEL_ACCEL_SCALE,
        modelParameter + MODEL_ACCEL_NOISE, seed, NOISE_ACCEL, imu_index, accel_measured_body);
    fmt_measure_vector(mag_ideal_body, modelParameter + MODEL_MAG_INSTALLATION,
        modelParameter + MODEL_MAG_BIAS, modelParameter + MODEL_MAG_SCALE,
        modelParameter + MODEL_MAG_NOISE, seed, NOISE_MAG, slow_index, mag_measured_body);

    for (int axis = 0; axis < 3; ++axis) {
        double antenna_position = x[axis];
        double antenna_velocity = x[3 + axis];
        for (int i = 0; i < 3; ++i) {
            antenna_position += rotation[3 * axis + i] * lever_ant[i];
            antenna_velocity += rotation[3 * axis + i] * omega_cross_ant[i];
        }
        sensor[FMT_SENSOR_GYRO + axis] = gyro_measured_body[axis];
        sensor[FMT_SENSOR_ACCEL + axis] = accel_measured_body[axis];
        sensor[FMT_SENSOR_MAG + axis] = mag_measured_body[axis];
        sensor[FMT_SENSOR_POSITION + axis] = antenna_position +
            modelParameter[MODEL_GNSS_POSITION_NOISE + axis] *
            fmt_gaussian(seed, NOISE_GNSS_POSITION, gnss_index, (uint64_t)axis);
        sensor[FMT_SENSOR_VELOCITY + axis] = antenna_velocity +
            modelParameter[MODEL_GNSS_VELOCITY_NOISE + axis] *
            fmt_gaussian(seed, NOISE_GNSS_VELOCITY, gnss_index, (uint64_t)axis);
    }

    sensor[FMT_SENSOR_BARO] = -x[2] + modelParameter[MODEL_BARO_BIAS] +
        modelParameter[MODEL_BARO_NOISE] * fmt_gaussian(seed, NOISE_BARO, baro_index, 0);
    validity_mask = FMT_GNSS_VALID | FMT_MAG_VALID | FMT_BARO_VALID;
    if (imu_derivative_valid) validity_mask |= FMT_IMU_VALID;
    sensor[FMT_SENSOR_VALID] = (double)validity_mask;
    /* GroundContact: signed gap <= 1 mm and penetration <= 20 mm. */
    sensor[FMT_SENSOR_CONTACT] = (gap <= 0.001 && gap >= -0.02) ? 1.0 : 0.0;
    if (!fmt_finite_vector(sensor, FMT_SENSOR_WIDTH)) {
        ssSetErrorStatus(S, "Nonfinite sensor output from PlantSensorKinematics.");
    }
}

#define MDL_UPDATE
static void mdlUpdate(SimStruct *S, int_T tid)
{
    const mxArray *timingArray = ssGetSFcnParam(S, 2);
    const double *timing;
    double *state = ssGetRealDiscStates(S);
    const double *x = ssGetInputPortRealSignal(S, 0);
    const double current_time_s = ssGetT(S);

    (void)tid;
    if (!mxIsDouble(timingArray) || mxIsComplex(timingArray) ||
        mxIsSparse(timingArray) ||
        mxGetNumberOfElements(timingArray) != FMT_SENSOR_SIM_PARAMETER_COUNT ||
        !(timing = mxGetPr(timingArray)) ||
        !fmt_sensor_timing_parameters_valid(timing)) {
        ssSetErrorStatus(S, "SensorTimingParameters are invalid during sensor history update.");
        return;
    }

    /* Keep the derivative baseline at the previous physical IMU sample,
     * not at every 500-us Plant integration step. */
    if (!fmt_is_imu_sample_epoch(current_time_s,
            timing[FMT_TIMING_IMU_PERIOD]) ||
        current_time_s <= state[7])
        return;

    memcpy(state, x + 3, 3 * sizeof(double));
    memcpy(state + 3, x + 10, 3 * sizeof(double));
    state[7] = current_time_s;
    state[6] = 1.0;
}

static void mdlTerminate(SimStruct *S) { (void)S; }

#include "simulink.c"
