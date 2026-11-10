/* Reuse Flight's RT-Thread host device/clock stubs and real task translation
 * units. The standalone SIL scenario and its UDP helpers are never called. */
#define main flight_standalone_sil_main
#include "sil_flight.c"
#undef main
#include "fmt_flight_runtime.h"
#include "fmt_sensor_simulation.h"
#include "calibration/sensor_calibration.h"
#include "sample_normalization/sensor_sample.h"

typedef struct {
    NavigationSnapshot snapshot;
    NavigationCapability capability;
} NavFrame;

static NavFrame external_frame;
static unsigned elapsed_ticks;
static int mode_active, attached;
static uint32_t last_request;
static uint16_t last_ack, last_reason, last_command_code;
static FmtSensorSimState sensor_simulation;
static int sensor_simulation_ready;
static uint64_t sensor_simulation_epoch_us;
static double sensor_model_parameters[FMT_SENSOR_MODEL_PARAMETER_COUNT];
static double sensor_timing_parameters[FMT_SENSOR_SIM_PARAMETER_COUNT];
static sensor_imu_config_t simulated_imu_config;
static sensor_context_t simulated_imu_context;
/* Host SIL must emulate RTOS semaphore wakeups for the GNSS-origin handshake. */
static uint32_t last_origin_candidate_sequence;
static uint64_t last_origin_candidate_sample_us;
static uint32_t origin_auth_attempts, origin_auth_successes;
static uint32_t origin_reset_attempts, origin_reset_successes;
static int origin_auth_last_status, origin_reset_last_status;
static uint16_t origin_reset_last_type;
static uint32_t origin_reset_last_origin_id;
static uint32_t gnss_submit_attempts, gnss_submit_successes;
static int gnss_submit_last_status;
static uint32_t gnss_push_attempts, gnss_push_successes;
static int gnss_push_last_status;
static uint32_t origin_poll_attempts, origin_poll_successes;
static int origin_poll_last_status;
static uint32_t origin_poll_last_sequence, origin_poll_last_next_id;
static uint32_t sensor_turn_count, mission_turn_count, origin_wake_count, candidate_observed_count;
static uint32_t candidate_last_sequence, candidate_last_next_id;
static uint64_t candidate_last_sample_us, candidate_last_valid_until_us, candidate_last_age_us;
static uint32_t mil_gnss_gate_released, mil_gnss_gate_wait_steps;
static uint32_t mil_gnss_first_fix_sequence;
static uint64_t mil_gnss_gate_ready_time_us, mil_gnss_first_fix_sample_us;
static uint32_t gnss_push_not_ready_count, gnss_push_not_permitted_count, gnss_push_other_failures;
static uint32_t candidate_first_sequence;
static uint64_t candidate_first_sample_us, candidate_first_age_us;

static int external_mode(void);

Status __real_estimator_init(const ProductEstimatorConfig *);
Status __real_estimator_push_imu(const ImuSample *);
Status __real_estimator_update(uint64_t);
Status __real_estimator_get_snapshot(NavigationSnapshot *);
Status __real_estimator_get_capability(NavigationCapability *);
Status __real_ins_get_pending_origin(ContractHeader *, uint32_t *);
Status __real_estimator_push_measurement(const SensorMeasurement *);
Status __real_fms_authorize_origin_reset(const ContractHeader *, uint32_t, EstimatorResetRequest *);
Status __real_estimator_reset(const EstimatorResetRequest *);

Status __wrap_estimator_init(const ProductEstimatorConfig *config)
{
    if (!config)
        return __real_estimator_init(config);
    ProductEstimatorConfig mil_config = *config;
    /* Exercise the real late-first-fix/FMS Origin Reset path only in MIL.
     * DataSIM and ExtINS retain the complete anchored Host SIL bench origin. */
    if (mode_active == FMT_MIL_SIM || mode_active == FMT_DATA_SIM)
        mil_config.payload.initial_origin_valid_mask = 1u;
    return __real_estimator_init(&mil_config);
}

Status __wrap_ins_get_pending_origin(ContractHeader *candidate, uint32_t *next_origin_id)
{
    ++origin_poll_attempts;
    Status result;
    if (external_mode()) {
        if (candidate)
            memset(candidate, 0, sizeof(*candidate));
        if (next_origin_id)
            *next_origin_id = 0u;
        result = STATUS_NOT_READY;
    } else {
        result = __real_ins_get_pending_origin(candidate, next_origin_id);
    }
    origin_poll_last_status = (int)result;
    if (result == STATUS_OK)
        ++origin_poll_successes;
    if (candidate)
        origin_poll_last_sequence = candidate->sequence;
    if (next_origin_id)
        origin_poll_last_next_id = *next_origin_id;
    return result;
}

Status __wrap_estimator_push_measurement(const SensorMeasurement *measurement)
{
    Status result = __real_estimator_push_measurement(measurement);
    if (measurement && measurement->measurement_kind == PRODUCT_MEASUREMENT_GNSS) {
        ++gnss_push_attempts;
        gnss_push_last_status = (int)result;
        if (result == STATUS_OK)
            ++gnss_push_successes;
        else if (result == STATUS_NOT_READY)
            ++gnss_push_not_ready_count;
        else if (result == STATUS_NOT_PERMITTED)
            ++gnss_push_not_permitted_count;
        else
            ++gnss_push_other_failures;
    }
    return result;
}

Status __wrap_fms_authorize_origin_reset(const ContractHeader *candidate, uint32_t next_origin_id,
                                         EstimatorResetRequest *request)
{
    ++origin_auth_attempts;
    Status result = __real_fms_authorize_origin_reset(candidate, next_origin_id, request);
    origin_auth_last_status = (int)result;
    if (result == STATUS_OK)
        ++origin_auth_successes;
    return result;
}

Status __wrap_estimator_reset(const EstimatorResetRequest *request)
{
    ++origin_reset_attempts;
    if (request) {
        origin_reset_last_type = request->reset_type;
        origin_reset_last_origin_id = request->requested_origin_id;
    }
    Status result = __real_estimator_reset(request);
    origin_reset_last_status = (int)result;
    if (result == STATUS_OK)
        ++origin_reset_successes;
    return result;
}

static int external_mode(void)
{
    return mode_active == FMT_EXTINS_DATA_SIM;
}

Status __wrap_estimator_push_imu(const ImuSample *sample)
{
    return external_mode() ? STATUS_OK : __real_estimator_push_imu(sample);
}

Status __wrap_estimator_update(uint64_t now)
{
    if (!external_mode())
        return __real_estimator_update(now);
    return external_frame.snapshot.header.valid_until_us > now ? STATUS_OK : STATUS_STALE_DATA;
}

Status __wrap_estimator_get_snapshot(NavigationSnapshot *out)
{
    if (!external_mode())
        return __real_estimator_get_snapshot(out);
    *out = external_frame.snapshot;
    return STATUS_OK;
}

Status __wrap_estimator_get_capability(NavigationCapability *out)
{
    if (!external_mode())
        return __real_estimator_get_capability(out);
    *out = external_frame.capability;
    return STATUS_OK;
}

static void inject_imu(const double *s, unsigned sequence)
{
    ImuSample sample = {0};
    sample.header = h(SOURCE_IMU, test_clock.monotonic_us + 5000u);
    sample.header.message_type = MSG_IMU_SAMPLE;
    sample.header.frame_id = FRAME_BODY_FRD;
    sample.header.sequence = sequence;
    sample.header.timestamp_quality = TIMESTAMP_QUALITY_SENSOR_MODEL_CORRECTED;
    sample.sensor_instance_id = 1;
    sample.sample_sequence = sequence;
    sample.calibration_version = 1;
    sample.quality_flags = IMU_Q_GYRO_VALID | IMU_Q_ACCEL_VALID | IMU_Q_CALIBRATED;
    for (unsigned axis = 0; axis < 3; ++axis) {
        sample.gyro_frd_radps[axis] = (float)s[FMT_SENSOR_GYRO + axis];
        sample.accel_frd_mps2[axis] = (float)s[FMT_SENSOR_ACCEL + axis];
    }
    (void)sensor_imu_inject(&sample, test_clock.monotonic_us);
}

static void inject_mag(const double *s, unsigned sequence)
{
    SensorMeasurement m = {0};
    m.header = h(SOURCE_MAG, test_clock.monotonic_us + 100000u);
    m.header.frame_id = FRAME_BODY_FRD;
    m.header.sequence = sequence;
    m.measurement_kind = PRODUCT_MEASUREMENT_MAG;
    m.sensor_instance_id = 2;
    m.payload.mag.header = m.header;
    m.payload.mag.sensor_instance_id = 2;
    m.payload.mag.calibration_version = 1;
    m.payload.mag.quality_flags = MAG_Q_FIELD_VALID | MAG_Q_CALIBRATED;
    for (unsigned axis = 0; axis < 3; ++axis) {
        m.payload.mag.field_frd_ut[axis] = (float)s[FMT_SENSOR_MAG + axis];
        m.payload.mag.variance_ut2[axis] = 1.0f;
    }
    (void)runtime_submit_measurement(&m);
}

static int valid_group(const double *values, unsigned count)
{
    for (unsigned k = 0; k < count; ++k)
        if (!isfinite(values[k])) return 0;
    return 1;
}

static void feed_sensors(const double *s, unsigned ms)
{
    const double mask = s[FMT_SENSOR_VALID];
    const unsigned valid = mask >= 0 && mask <= 15 ? (unsigned)mask : 0;
    if (!external_mode()) {
        if ((valid & FMT_BARO_VALID) && ms % 20u == 0u && isfinite(s[FMT_SENSOR_BARO]))
            feed_baro(ms, (float)s[FMT_SENSOR_BARO]);
        if ((valid & FMT_GNSS_VALID) && ms % 100u == 90u &&
            valid_group(s + FMT_SENSOR_POSITION, 6)) {
            for (unsigned axis = 0; axis < 3; ++axis) {
                fmt_state.position_ned_m[axis] = (float)s[FMT_SENSOR_POSITION + axis];
                fmt_state.velocity_ned_mps[axis] = (float)s[FMT_SENSOR_VELOCITY + axis];
            }
            feed_gnss(ms);
        }
        if ((valid & FMT_MAG_VALID) && ms % 10u == 0u && valid_group(s + FMT_SENSOR_MAG, 3))
            inject_mag(s, ms);
    }
    if ((valid & FMT_IMU_VALID) && valid_group(s, 6))
        inject_imu(s, ms);
}

/* Present the separate contact observation through the existing SIL contact
 * hook. The temporary position/velocity above are only used to encode GNSS. */

static void configure_simulated_imu(const double *timing)
{
    memset(&simulated_imu_config, 0, sizeof(simulated_imu_config));
    for (unsigned axis = 0; axis < 3; ++axis) {
        simulated_imu_config.gyro_scale[axis] = 1.0f;
        simulated_imu_config.accel_scale[axis] = 1.0f;
        for (unsigned column = 0; column < 3; ++column) {
            const float identity = axis == column ? 1.0f : 0.0f;
            simulated_imu_config.install_rotation[axis][column] = identity;
            simulated_imu_config.gyro_misalignment[axis][column] = identity;
            simulated_imu_config.accel_misalignment[axis][column] = identity;
        }
    }
    /* SensorModelParameters has already produced calibrated body-FRD values.
     * The M2 builder is used only to attach the physical sample-time contract. */
    simulated_imu_config.pipeline_delay_us = timing[FMT_TIMING_IMU_PIPELINE_DELAY];
    simulated_imu_config.pipeline_delay_uncertainty_us =
        timing[FMT_TIMING_IMU_PIPELINE_UNCERTAINTY];
    simulated_imu_config.calibration_version = 1u;

    memset(&simulated_imu_context, 0, sizeof(simulated_imu_context));
    simulated_imu_context.boot_id = test_clock.boot_id;
    simulated_imu_context.time_epoch = test_clock.time_epoch;
    simulated_imu_context.profile_id = PRODUCT_PROFILE_ID;
    simulated_imu_context.sensor_instance_id = 1u;
    simulated_imu_context.sequence = 1u;
}

static int inject_simulated_imu(const FmtSensorSimEvent *event)
{
    const double rad_to_deg = 57.29577951308232;
    ImuReading reading = {0};
    ImuSample sample;
    for (unsigned axis = 0; axis < 3; ++axis) {
        reading.gyro_dps[axis] = (float)(event->values[axis] * rad_to_deg);
        reading.accel_mps2[axis] = (float)event->values[3u + axis];
    }
    reading.temperature_c = 25.0f;
    reading.sequence = event->sequence;
    reading.diagnostic_clear = true;
    if (sensor_imu_build_sample(&simulated_imu_config, &simulated_imu_context,
                                &reading, event->capture_us, event->release_us,
                                &sample) != SENSOR_OK ||
        sample.header.timestamp_sample_us != event->sample_us ||
        sample.header.timestamp_publish_us != event->release_us ||
        sensor_imu_inject(&sample, event->release_us) != STATUS_OK) {
        ++failures;
        return -1;
    }
    return 0;
}

static int inject_simulated_mag(const FmtSensorSimEvent *event, const double *model_parameters)
{
    SensorMeasurement measurement = {0};
    measurement.header = h(SOURCE_MAG, event->sample_us + 100000u);
    measurement.header.timestamp_sample_us = event->sample_us;
    measurement.header.timestamp_publish_us = event->release_us;
    measurement.header.valid_until_us = event->sample_us + 100000u;
    measurement.header.timestamp_quality = TIMESTAMP_QUALITY_SENSOR_MODEL_CORRECTED;
    measurement.header.sequence = event->sequence;
    measurement.header.frame_id = FRAME_BODY_FRD;
    measurement.measurement_kind = PRODUCT_MEASUREMENT_MAG;
    measurement.sensor_instance_id = 2u;
    measurement.payload.mag.header = measurement.header;
    measurement.payload.mag.sensor_instance_id = 2u;
    measurement.payload.mag.calibration_version = 1u;
    measurement.payload.mag.quality_flags = MAG_Q_FIELD_VALID | MAG_Q_CALIBRATED;
    for (unsigned axis = 0; axis < 3; ++axis) {
        measurement.payload.mag.field_frd_ut[axis] = (float)event->values[axis];
        measurement.payload.mag.variance_ut2[axis] = (float)fmax(0.01, 
            model_parameters[FMT_MODEL_MAG_NOISE + axis] *
            model_parameters[FMT_MODEL_MAG_NOISE + axis]);
    }
    if (runtime_submit_measurement(&measurement) != STATUS_OK) {
        ++failures;
        return -1;
    }
    return 0;
}

static int inject_simulated_baro(const FmtSensorSimEvent *event, const double *model_parameters)
{
    SensorMeasurement measurement = {0};
    measurement.header = h(SOURCE_BARO, event->sample_us + 20000u);
    measurement.header.timestamp_sample_us = event->sample_us;
    measurement.header.timestamp_publish_us = event->release_us;
    measurement.header.valid_until_us = event->sample_us + 20000u;
    measurement.header.timestamp_quality = TIMESTAMP_QUALITY_SENSOR_MODEL_CORRECTED;
    measurement.header.sequence = event->sequence;
    measurement.measurement_kind = PRODUCT_MEASUREMENT_BARO;
    measurement.sensor_instance_id = 3u;
    measurement.payload.baro.header = measurement.header;
    measurement.payload.baro.sensor_instance_id = 3u;
    measurement.payload.baro.calibration_version = 1u;
    measurement.payload.baro.altitude_m = (float)event->values[0];
    measurement.payload.baro.variance_m2 = (float)fmax(0.25,
        model_parameters[FMT_MODEL_BARO_NOISE] * model_parameters[FMT_MODEL_BARO_NOISE]);
    measurement.payload.baro.quality_flags = 7u;
    if (runtime_submit_measurement(&measurement) != STATUS_OK) {
        ++failures;
        return -1;
    }
    return 0;
}

static int inject_simulated_gnss(const FmtSensorSimEvent *event, const double *model_parameters)
{
    const double radians_to_degrees = 57.29577951308232;
    const double meridian_radius_m = 6335439.32729282;
    const double prime_vertical_radius_m = 6378137.0;
    SensorMeasurement measurement = {0};
    measurement.header = h(SOURCE_GNSS, event->sample_us + 20000u);
    measurement.header.timestamp_sample_us = event->sample_us;
    measurement.header.timestamp_publish_us = event->release_us;
    measurement.header.valid_until_us = event->sample_us + 20000u;
    measurement.header.timestamp_quality = TIMESTAMP_QUALITY_SENSOR_MODEL_CORRECTED;
    measurement.header.sequence = event->sequence;
    measurement.header.frame_id = FRAME_WGS84_GEODETIC;
    measurement.measurement_kind = PRODUCT_MEASUREMENT_GNSS;
    measurement.sensor_instance_id = 4u;
    measurement.payload.gnss.header = measurement.header;
    measurement.payload.gnss.sensor_instance_id = 4u;
    measurement.payload.gnss.calibration_version = 1u;
    measurement.payload.gnss.quality_flags = 15u;
    measurement.payload.gnss.fix_type = GNSS_FIX_RTK_FIXED;
    measurement.payload.gnss.latitude_deg =
        ((event->values[0] - fmt_origin.position_ned_m[0]) *
         radians_to_degrees / meridian_radius_m);
    measurement.payload.gnss.longitude_deg =
        ((event->values[1] - fmt_origin.position_ned_m[1]) *
         radians_to_degrees / prime_vertical_radius_m);
    measurement.payload.gnss.altitude_m =
        fmt_origin.position_ned_m[2] - event->values[2];
    for (unsigned axis = 0; axis < 3; ++axis) {
        measurement.payload.gnss.velocity_ned_mps[axis] =
            (float)event->values[3u + axis];
        measurement.payload.gnss.position_variance_m2[axis] = (float)fmax(0.04,
            model_parameters[FMT_MODEL_GNSS_POSITION_NOISE + axis] *
            model_parameters[FMT_MODEL_GNSS_POSITION_NOISE + axis]);
        measurement.payload.gnss.velocity_variance_m2ps2[axis] = (float)fmax(0.01,
            model_parameters[FMT_MODEL_GNSS_VELOCITY_NOISE + axis] *
            model_parameters[FMT_MODEL_GNSS_VELOCITY_NOISE + axis]);
    }
    ++gnss_submit_attempts;
    Status submit_status = runtime_submit_measurement(&measurement);
    gnss_submit_last_status = (int)submit_status;
    if (submit_status != STATUS_OK) {
        ++failures;
        return -1;
    }
    ++gnss_submit_successes;
    if ((mode_active == FMT_MIL_SIM || mode_active == FMT_DATA_SIM) && mil_gnss_first_fix_sequence == 0u) {
        mil_gnss_first_fix_sequence = event->sequence;
        mil_gnss_first_fix_sample_us = event->sample_us;
    }
    return 0;
}

static int feed_simulated_sensor_events(const double *sensor_frame,
                                        const double *model_parameters,
                                        const double *timing,
                                        uint64_t now_us)
{
    FmtSensorSimEvent due[4];
    double gated_sensor_frame[FMT_SENSOR_WIDTH];
    if (!valid_group(sensor_frame, FMT_SENSOR_WIDTH) ||
        !isfinite(sensor_frame[FMT_SENSOR_VALID]) || sensor_frame[FMT_SENSOR_VALID] < 0.0 ||
        sensor_frame[FMT_SENSOR_VALID] > 15.0 || floor(sensor_frame[FMT_SENSOR_VALID]) != sensor_frame[FMT_SENSOR_VALID])
        return -1;
    memcpy(gated_sensor_frame, sensor_frame, sizeof(gated_sensor_frame));
    if ((mode_active == FMT_MIL_SIM || mode_active == FMT_DATA_SIM) && !mil_gnss_gate_released) {
        NavigationSnapshot snapshot = {0};
        Status nav_status = __real_estimator_get_snapshot(&snapshot);
        if (nav_status == STATUS_OK &&
            (snapshot.core.valid_mask & NAV_VALID_ATTITUDE) != 0u &&
            (snapshot.core.valid_mask & NAV_VALID_HORIZONTAL_POSITION) == 0u) {
            mil_gnss_gate_released = 1u;
            mil_gnss_gate_ready_time_us = now_us;
        } else {
            const unsigned mask = (unsigned)gated_sensor_frame[FMT_SENSOR_VALID];
            gated_sensor_frame[FMT_SENSOR_VALID] = (double)(mask & ~FMT_GNSS_VALID);
            ++mil_gnss_gate_wait_steps;
        }
    }
    if (!valid_group(model_parameters, FMT_SENSOR_MODEL_PARAMETER_COUNT)) {
        ++failures;
        return -1;
    }
    if (!sensor_simulation_ready) {
        if (fmt_sensor_sim_init(&sensor_simulation, timing,
                                sensor_simulation_epoch_us) != 0) {
            ++failures;
            return -1;
        }
        memcpy(sensor_model_parameters, model_parameters, sizeof(sensor_model_parameters));
        memcpy(sensor_timing_parameters, timing, sizeof(sensor_timing_parameters));
        configure_simulated_imu(timing);
        sensor_simulation_ready = 1;
    } else if (memcmp(sensor_model_parameters, model_parameters,
                      sizeof(sensor_model_parameters)) != 0 ||
               memcmp(sensor_timing_parameters, timing,
                      sizeof(sensor_timing_parameters)) != 0) {
        ++failures;
        return -1;
    }

    if (fmt_sensor_sim_step_offset(&sensor_simulation, gated_sensor_frame, now_us,
                                   FMT_SENSOR_SIM_FIXED_STEP_US, due) != 0) {
        ++failures;
        return -1;
    }
    if (due[FMT_SENSOR_SIM_IMU].valid) {
        if (inject_simulated_imu(&due[FMT_SENSOR_SIM_IMU]) != 0 ||
            fmt_sensor_sim_mark_accepted(&sensor_simulation, FMT_SENSOR_SIM_IMU) != 0)
            return -1;
    }
    if (due[FMT_SENSOR_SIM_GNSS].valid) {
        if (inject_simulated_gnss(&due[FMT_SENSOR_SIM_GNSS], model_parameters) != 0 ||
            fmt_sensor_sim_mark_accepted(&sensor_simulation, FMT_SENSOR_SIM_GNSS) != 0)
            return -1;
    }
    if (due[FMT_SENSOR_SIM_MAG].valid) {
        if (inject_simulated_mag(&due[FMT_SENSOR_SIM_MAG], model_parameters) != 0 ||
            fmt_sensor_sim_mark_accepted(&sensor_simulation, FMT_SENSOR_SIM_MAG) != 0)
            return -1;
    }
    if (due[FMT_SENSOR_SIM_BARO].valid) {
        if (inject_simulated_baro(&due[FMT_SENSOR_SIM_BARO], model_parameters) != 0 ||
            fmt_sensor_sim_mark_accepted(&sensor_simulation, FMT_SENSOR_SIM_BARO) != 0)
            return -1;
    }
    return 0;
}

static void feed_contact(double contact)
{
    last_fmt_us = contact == 0 || contact == 1 ? test_clock.monotonic_us : 0;
    fmt_state.position_ned_m[2] = contact == 1 ? 0.0f : -1.0f;
    fmt_state.velocity_ned_mps[2] = 0;
}

__declspec(dllexport) unsigned fmt_flight_nav_width(void)
{
    return sizeof(NavFrame);
}

__declspec(dllexport) int fmt_flight_start(int mode)
{
    if (attached || mode < FMT_DATA_SIM || mode > FMT_EXTINS_DATA_SIM)
        return -1;
    test_clock = (ClockInstant){0x12345678, 1000000, 1, 0};
    test_imu_pending = 0;
    checks = failures = commits = inhibits = 0;
    test_tx_complete = NULL;
    elapsed_ticks = sil_requests = last_request = 0;
    sensor_simulation_ready = 0;
    last_origin_candidate_sequence = 0u;
    last_origin_candidate_sample_us = 0u;
    memset(&sensor_simulation, 0, sizeof(sensor_simulation));
    memset(sensor_model_parameters, 0, sizeof(sensor_model_parameters));
    memset(sensor_timing_parameters, 0, sizeof(sensor_timing_parameters));
    /* mdlUpdate advances the runtime clock before processing the Plant sample.
     * Start event opportunities one tick ahead, then subtract that same fixed
     * offset when stamping the physical sample/capture epochs. */
    sensor_simulation_epoch_us = test_clock.monotonic_us + FMT_SENSOR_SIM_FIXED_STEP_US;
    last_ack = last_reason = 0;
    last_command_code = 0u;
    origin_auth_attempts = origin_auth_successes = 0u;
    origin_reset_attempts = origin_reset_successes = 0u;
    origin_auth_last_status = origin_reset_last_status = 0;
    origin_reset_last_type = 0u;
    origin_reset_last_origin_id = 0u;
    mil_gnss_gate_released = mil_gnss_gate_wait_steps = 0u;
    mil_gnss_first_fix_sequence = 0u;
    mil_gnss_gate_ready_time_us = mil_gnss_first_fix_sample_us = 0u;
    gnss_push_not_ready_count = gnss_push_not_permitted_count = gnss_push_other_failures = 0u;
    candidate_first_sequence = 0u;
    candidate_first_sample_us = candidate_first_age_us = 0u;
    gnss_submit_attempts = gnss_submit_successes = 0u;
    gnss_submit_last_status = 0;
    gnss_push_attempts = gnss_push_successes = 0u;
    gnss_push_last_status = 0;
    origin_poll_attempts = origin_poll_successes = 0u;
    origin_poll_last_status = 0;
    origin_poll_last_sequence = origin_poll_last_next_id = 0u;
    sensor_turn_count = mission_turn_count = origin_wake_count = candidate_observed_count = 0u;
    candidate_last_sequence = candidate_last_next_id = 0u;
    candidate_last_sample_us = candidate_last_valid_until_us = candidate_last_age_us = 0u;
    memset(&external_frame, 0, sizeof(external_frame));
    memset(&fmt_origin, 0, sizeof(fmt_origin));
    memset(&fmt_state, 0, sizeof(fmt_state));
    memset(&plan_bundle, 0, sizeof(plan_bundle));
    memset(&fms_output, 0, sizeof(fms_output));
    fmt_online = 1;
    mode_active = mode;
    if (runtime_start() != RT_EOK)
        return -2;
    sensor_imu_use_external_source(true);
    attached = 1;
    return 0;
}

__declspec(dllexport) void fmt_flight_stop(void)
{
    if (attached) {
        telemetry_link_release_radio();
        runtime_shutdown();
        attached = 0;
    }
}

__declspec(dllexport) int fmt_flight_step(const double *s, const double *command,
                                       const uint8_t *nav_in, const double *sensor_model_parameters,
                                       const double *sensor_timing_parameters,
                                       double *force, double *status, uint8_t *nav_out)
{
    if (!attached)
        return -1;
    ++elapsed_ticks;
    test_clock.monotonic_us += 500u;
    unsigned ms = elapsed_ticks / 2u;
    int mission_turned = 0;
    if (external_mode())
        memcpy(&external_frame, nav_in, sizeof(external_frame));
    if ((mode_active == FMT_MIL_SIM || mode_active == FMT_DATA_SIM) &&
        feed_simulated_sensor_events(s, sensor_model_parameters, sensor_timing_parameters,
                                     test_clock.monotonic_us) != 0)
        return -3;

    if (elapsed_ticks % 2u == 0u) {
        if (ms % TASK_MISSION_PERIOD_MS == 0u)
            feed_operator(0, 0);
        if (mode_active == FMT_EXTINS_DATA_SIM)
            feed_sensors(s, ms);
        feed_contact(s[FMT_SENSOR_CONTACT]);
        ++sensor_turn_count;
        turn(task_sensor_entry);
        /*
         * The real RTOS wakes Mission immediately when task_sensor publishes a
         * validated GNSS origin candidate. Host SIL's rt_sem_release is a
         * deterministic no-op, so the periodic 20-ms Mission turn can arrive
         * exactly at (or after) the 20-ms GNSS validity deadline (100-ms sample
         * + 10-ms transport + 20-ms Mission phase). Emulate that event wake
         * explicitly; after authorization, emulate the IMU semaphore wake so
         * task_sensor consumes the queued EstimatorResetRequest immediately.
         */
        {
            ContractHeader candidate = {0};
            uint32_t next_origin = 0u;
            if (runtime_data_lock(0)) {
                candidate = runtime_data.origin_candidate;
                next_origin = runtime_data.next_origin_id;
                runtime_data_unlock();
            }
            candidate_last_sequence = candidate.sequence;
            candidate_last_next_id = next_origin;
            candidate_last_sample_us = candidate.timestamp_sample_us;
            candidate_last_valid_until_us = candidate.valid_until_us;
            candidate_last_age_us = candidate.timestamp_sample_us && test_clock.monotonic_us >= candidate.timestamp_sample_us ?
                test_clock.monotonic_us - candidate.timestamp_sample_us : 0u;
            if (next_origin != 0u && candidate.sequence != 0u) {
                ++candidate_observed_count;
                if (candidate_first_sequence == 0u) {
                    candidate_first_sequence = candidate.sequence;
                    candidate_first_sample_us = candidate.timestamp_sample_us;
                    candidate_first_age_us = candidate_last_age_us;
                }
            }
            if (next_origin == 0u) {
                last_origin_candidate_sequence = 0u;
                last_origin_candidate_sample_us = 0u;
            } else if (candidate.sequence != 0u &&
                       (candidate.sequence != last_origin_candidate_sequence ||
                        candidate.timestamp_sample_us != last_origin_candidate_sample_us)) {
                last_origin_candidate_sequence = candidate.sequence;
                last_origin_candidate_sample_us = candidate.timestamp_sample_us;
                ++origin_wake_count;
                ++mission_turn_count;
                turn(task_mission_entry);
                mission_turned = 1;
                turn(task_sensor_entry);
                ++sensor_turn_count;
            }
        }
        if (ms % TASK_COMMUNICATION_PERIOD_MS == 0u)
            turn(task_communication_entry);
        turn(task_actuator_entry);
    }
    if (elapsed_ticks % 5u == 0u)
        (void)actuator_guard_frame_boundary(test_clock.monotonic_us);
    if (elapsed_ticks % (2u * TASK_MISSION_PERIOD_MS) == 0u && !mission_turned) {
        ++mission_turn_count;
        turn(task_mission_entry);
        mission_turned = 1;
    }
    if (mission_turned) {
        for (unsigned i = 0; i < fms_output.command_result_count; ++i) {
            const CommandAck *ack = &fms_output.command_results[i];
            if (ack->request_id == last_request) {
                last_ack = ack->ack_state;
                last_reason = ack->reason_code;
            }
        }
    }
    if (elapsed_ticks % (2u * TASK_MPC_PERIOD_MS) == 0u)
        turn(task_mpc_entry);
    if (elapsed_ticks % (2u * TASK_SUPERVISOR_PERIOD_MS) == 0u)
        task_supervisor_step();
    if (command[0] >= 1 && command[0] <= UINT16_MAX && floor(command[0]) == command[0] &&
        isfinite(command[1])) {
        uint32_t request = submit_command((uint16_t)command[0], runtime_data.prearm.check_epoch,
                                          (float)command[1]);
        if (request) {
            last_request = request;
            last_ack = last_reason = 0;
            last_command_code = (uint16_t)command[0];
        }
    }

    const int permitted = current_commit();
    for (unsigned i = 0; i < 4; ++i)
        force[i] = permitted ? runtime_data.receipt.committed_demand.motor_thrust_n[i] : 0.0;
    const NavStateCore *nav = &runtime_data.nav.core;
    NavigationOriginSnapshot origin_snapshot = {0};
    Status origin_snapshot_status = estimator_get_origin(&origin_snapshot);
    const double values[FMT_STATUS_WIDTH] = {
        test_clock.monotonic_us, runtime_data.prearm.state, runtime_data.fms.arm_state,
        runtime_data.fms.flight_mode, runtime_data.fms.failsafe_level,
        fms_output.actuation_permit.permit_flags, runtime_data.receipt.result_code,
        permitted, last_request, last_ack, last_reason, nav->valid_mask,
        nav->position_ned_m[0], nav->position_ned_m[1], nav->position_ned_m[2],
        nav->velocity_ned_mps[0], nav->velocity_ned_mps[1], nav->velocity_ned_mps[2],
        runtime_stats.navigation_status, runtime_stats.control_status,
        runtime_stats.planning_status, runtime_stats.mpc_updates, commits, failures,
        runtime_data.prearm.failed_checks_mask,
        runtime_data.prearm.primary_reason_code,
        runtime_data.prearm.failed_count,
        runtime_data.prearm.warning_count,
        runtime_data.prearm.check_epoch,
        runtime_data.fms.authority,
        runtime_data.fms.mission_state,
        last_command_code,
        origin_auth_attempts,
        origin_auth_successes,
        origin_auth_last_status,
        origin_reset_attempts,
        origin_reset_successes,
        origin_reset_last_status,
        origin_reset_last_type,
        origin_reset_last_origin_id,
        gnss_submit_attempts,
        gnss_submit_successes,
        gnss_submit_last_status,
        gnss_push_attempts,
        gnss_push_successes,
        gnss_push_last_status,
        origin_poll_attempts,
        origin_poll_successes,
        origin_poll_last_status,
        origin_poll_last_sequence,
        origin_poll_last_next_id,
        sensor_turn_count,
        mission_turn_count,
        origin_wake_count,
        candidate_observed_count,
        candidate_last_sequence,
        candidate_last_sample_us,
        candidate_last_valid_until_us,
        candidate_last_next_id,
        candidate_last_age_us,
        mil_gnss_gate_released,
        mil_gnss_gate_ready_time_us,
        mil_gnss_gate_wait_steps,
        mil_gnss_first_fix_sequence,
        mil_gnss_first_fix_sample_us,
        gnss_push_not_ready_count,
        gnss_push_not_permitted_count,
        gnss_push_other_failures,
        origin_snapshot_status,
        origin_snapshot.valid_mask,
        origin_snapshot.origin_id,
        candidate_first_sequence,
        candidate_first_sample_us,
        candidate_first_age_us
    };
    memcpy(status, values, sizeof(values));
    NavFrame published = {0};
    published.snapshot = runtime_data.nav;
    published.capability = runtime_data.nav_cap;
    memcpy(nav_out, &published, sizeof(published));
    return 0;
}
