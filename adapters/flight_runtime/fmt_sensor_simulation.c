#include "fmt_sensor_simulation.h"
#include "fmt_flight_runtime.h"

#include <math.h>
#include <stddef.h>
#include <string.h>

#define FMT_SENSOR_SIM_PI 3.1415926535897932384626433832795

static int finite_values(const double *values, unsigned count)
{
    for (unsigned i = 0; i < count; ++i)
        if (!isfinite(values[i])) return 0;
    return 1;
}

static int valid_rotation(const double *r)
{
    double determinant;
    if (!finite_values(r, 9)) return 0;
    for (unsigned row = 0; row < 3; ++row) {
        for (unsigned column = 0; column < 3; ++column) {
            double dot = 0.0;
            for (unsigned k = 0; k < 3; ++k)
                dot += r[3 * k + row] * r[3 * k + column];
            if (fabs(dot - (row == column ? 1.0 : 0.0)) > 1e-6)
                return 0;
        }
    }
    determinant =
        r[0] * (r[4] * r[8] - r[5] * r[7]) -
        r[1] * (r[3] * r[8] - r[5] * r[6]) +
        r[2] * (r[3] * r[7] - r[4] * r[6]);
    return fabs(determinant - 1.0) <= 1e-6;
}

static uint32_t next_random(uint32_t *state)
{
    uint32_t x = *state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    if (x == 0u) x = 0x6d2b79f5u;
    *state = x;
    return x;
}

static double uniform_open(uint32_t *state)
{
    return ((double)next_random(state) + 0.5) / 4294967296.0;
}

static double gaussian(uint32_t *state)
{
    const double u1 = uniform_open(state);
    const double u2 = uniform_open(state);
    return sqrt(-2.0 * log(u1)) * cos(2.0 * FMT_SENSOR_SIM_PI * u2);
}

static void rotate_body_to_sensor(const double *sensor_to_body,
                                  const double body[3], double sensor[3])
{
    for (unsigned row = 0; row < 3; ++row) {
        sensor[row] = 0.0;
        for (unsigned column = 0; column < 3; ++column)
            sensor[row] += sensor_to_body[3 * column + row] * body[column];
    }
}

static int queue_push(FmtSensorSimQueue *queue, const FmtSensorSimEvent *event)
{
    uint32_t tail;
    if (queue->count >= FMT_SENSOR_SIM_QUEUE_CAPACITY) return 0;
    tail = (queue->head + queue->count) % FMT_SENSOR_SIM_QUEUE_CAPACITY;
    queue->events[tail] = *event;
    ++queue->count;
    return 1;
}

static int parameter_integer(double value, uint64_t *out)
{
    if (!isfinite(value) || value < 0.0 || value > 1.0e9 || floor(value) != value)
        return 0;
    *out = (uint64_t)value;
    return 1;
}

static int validate_parameters(const double *p)
{
    uint64_t period[4], delay[4], pipeline;
    const unsigned period_index[4] = {
        FMT_SIM_IMU_PERIOD, FMT_SIM_GNSS_PERIOD,
        FMT_SIM_MAG_PERIOD, FMT_SIM_BARO_PERIOD
    };
    const unsigned delay_index[4] = {
        FMT_SIM_IMU_TRANSPORT_DELAY, FMT_SIM_GNSS_TRANSPORT_DELAY,
        FMT_SIM_MAG_TRANSPORT_DELAY, FMT_SIM_BARO_TRANSPORT_DELAY
    };
    if (!p || !finite_values(p, FMT_SENSOR_SIM_PARAMETER_COUNT)) return 0;
    if (!valid_rotation(p + FMT_SIM_IMU_INSTALLATION) ||
        !valid_rotation(p + FMT_SIM_MAG_INSTALLATION)) return 0;
    for (unsigned i = 0; i < 3; ++i) {
        if (!(p[FMT_SIM_SCALE_ERROR + i] > -1.0) ||
            p[FMT_SIM_GYRO_NOISE + i] < 0.0 ||
            p[FMT_SIM_ACCEL_NOISE + i] < 0.0 ||
            p[FMT_SIM_MAG_NOISE + i] < 0.0 ||
            p[FMT_SIM_GNSS_POSITION_NOISE + i] < 0.0 ||
            p[FMT_SIM_GNSS_VELOCITY_NOISE + i] < 0.0) return 0;
    }
    if (p[FMT_SIM_BARO_NOISE] < 0.0) return 0;
    for (unsigned i = 0; i < 4; ++i) {
        if (!parameter_integer(p[period_index[i]], &period[i]) ||
            period[i] < 500u || period[i] % 500u != 0u ||
            !parameter_integer(p[delay_index[i]], &delay[i])) return 0;
    }
    if (!parameter_integer(p[FMT_SIM_IMU_PIPELINE_DELAY], &pipeline) ||
        !parameter_integer(p[FMT_SIM_IMU_PIPELINE_UNCERTAINTY], &delay[0]) ||
        !parameter_integer(p[FMT_SIM_RANDOM_SEED], &delay[0]) ||
        p[FMT_SIM_RANDOM_SEED] < 1.0 || p[FMT_SIM_RANDOM_SEED] > 4294967295.0)
        return 0;
    if (pipeline + (uint64_t)p[FMT_SIM_IMU_TRANSPORT_DELAY] >=
        (FMT_SENSOR_SIM_QUEUE_CAPACITY - 2u) * period[FMT_SENSOR_SIM_IMU])
        return 0;
    if ((uint64_t)p[FMT_SIM_GNSS_TRANSPORT_DELAY] >=
        (FMT_SENSOR_SIM_QUEUE_CAPACITY - 2u) * period[FMT_SENSOR_SIM_GNSS] ||
        (uint64_t)p[FMT_SIM_MAG_TRANSPORT_DELAY] >=
        (FMT_SENSOR_SIM_QUEUE_CAPACITY - 2u) * period[FMT_SENSOR_SIM_MAG] ||
        (uint64_t)p[FMT_SIM_BARO_TRANSPORT_DELAY] >=
        (FMT_SENSOR_SIM_QUEUE_CAPACITY - 2u) * period[FMT_SENSOR_SIM_BARO])
        return 0;
    return 1;
}

int fmt_sensor_sim_init(FmtSensorSimState *state, const double *parameters, uint64_t epoch_us)
{
    uint32_t seed;
    if (!state || !validate_parameters(parameters)) return -1;
    memset(state, 0, sizeof(*state));
    memcpy(state->parameters, parameters,
           sizeof(double) * FMT_SENSOR_SIM_PARAMETER_COUNT);
    state->epoch_us = epoch_us;
    seed = (uint32_t)parameters[FMT_SIM_RANDOM_SEED];
    state->random_state[FMT_SENSOR_SIM_IMU] = seed ^ 0x9e3779b9u;
    state->random_state[FMT_SENSOR_SIM_GNSS] = seed ^ 0x243f6a88u;
    state->random_state[FMT_SENSOR_SIM_MAG] = seed ^ 0xb7e15162u;
    state->random_state[FMT_SENSOR_SIM_BARO] = seed ^ 0xdeadbeefu;
    for (unsigned i = 0; i < 4; ++i) {
        if (state->random_state[i] == 0u) state->random_state[i] = i + 1u;
    }
    return 0;
}

static void prepare_imu(FmtSensorSimState *state, const double *truth,
                        FmtSensorSimEvent *event)
{
    const double *p = state->parameters;
    double gyro_body[3], accel_body[3], gyro_sensor[3], accel_sensor[3];
    for (unsigned axis = 0; axis < 3; ++axis) {
        gyro_body[axis] = truth[FMT_SENSOR_GYRO + axis];
        accel_body[axis] = truth[FMT_SENSOR_ACCEL + axis];
    }
    rotate_body_to_sensor(p + FMT_SIM_IMU_INSTALLATION, gyro_body, gyro_sensor);
    rotate_body_to_sensor(p + FMT_SIM_IMU_INSTALLATION, accel_body, accel_sensor);
    for (unsigned axis = 0; axis < 3; ++axis) {
        event->values[axis] =
            gyro_sensor[axis] * (1.0 + p[FMT_SIM_SCALE_ERROR + axis]) +
            p[FMT_SIM_GYRO_BIAS + axis] +
            p[FMT_SIM_GYRO_NOISE + axis] * gaussian(&state->random_state[FMT_SENSOR_SIM_IMU]);
        event->values[3 + axis] =
            accel_sensor[axis] * (1.0 + p[FMT_SIM_SCALE_ERROR + axis]) +
            p[FMT_SIM_ACCEL_BIAS + axis] +
            p[FMT_SIM_ACCEL_NOISE + axis] * gaussian(&state->random_state[FMT_SENSOR_SIM_IMU]);
    }
}

static void prepare_gnss(FmtSensorSimState *state, const double *truth,
                         FmtSensorSimEvent *event)
{
    const double *p = state->parameters;
    for (unsigned axis = 0; axis < 3; ++axis) {
        event->values[axis] = truth[FMT_SENSOR_POSITION + axis] +
            p[FMT_SIM_GNSS_POSITION_NOISE + axis] *
            gaussian(&state->random_state[FMT_SENSOR_SIM_GNSS]);
        event->values[3 + axis] = truth[FMT_SENSOR_VELOCITY + axis] +
            p[FMT_SIM_GNSS_VELOCITY_NOISE + axis] *
            gaussian(&state->random_state[FMT_SENSOR_SIM_GNSS]);
    }
}

static void prepare_mag(FmtSensorSimState *state, const double *truth,
                        FmtSensorSimEvent *event)
{
    const double *p = state->parameters;
    double body[3], sensor[3];
    for (unsigned axis = 0; axis < 3; ++axis)
        body[axis] = truth[FMT_SENSOR_MAG + axis];
    rotate_body_to_sensor(p + FMT_SIM_MAG_INSTALLATION, body, sensor);
    for (unsigned axis = 0; axis < 3; ++axis) {
        event->values[axis] = sensor[axis] +
            p[FMT_SIM_MAG_NOISE + axis] *
            gaussian(&state->random_state[FMT_SENSOR_SIM_MAG]);
    }
}

static void prepare_baro(FmtSensorSimState *state, const double *truth,
                         FmtSensorSimEvent *event)
{
    const double *p = state->parameters;
    event->values[0] = truth[FMT_SENSOR_BARO] +
        p[FMT_SIM_BARO_NOISE] * gaussian(&state->random_state[FMT_SENSOR_SIM_BARO]);
}

int fmt_sensor_sim_step(FmtSensorSimState *state, const double truth[18],
                        uint64_t now_us, FmtSensorSimEvent due_events[4])
{
    const double *p;
    uint64_t elapsed;
    const unsigned valid_bits[4] = {
        FMT_IMU_VALID, FMT_GNSS_VALID, FMT_MAG_VALID, FMT_BARO_VALID
    };
    const unsigned period_index[4] = {
        FMT_SIM_IMU_PERIOD, FMT_SIM_GNSS_PERIOD,
        FMT_SIM_MAG_PERIOD, FMT_SIM_BARO_PERIOD
    };
    const unsigned transport_index[4] = {
        FMT_SIM_IMU_TRANSPORT_DELAY, FMT_SIM_GNSS_TRANSPORT_DELAY,
        FMT_SIM_MAG_TRANSPORT_DELAY, FMT_SIM_BARO_TRANSPORT_DELAY
    };
    const unsigned width[4] = {6, 6, 3, 1};
    if (!state || !truth || !due_events || now_us < state->epoch_us ||
        !finite_values(truth, 18)) return -1;
    p = state->parameters;
    elapsed = now_us - state->epoch_us;
    memset(due_events, 0, sizeof(FmtSensorSimEvent) * 4u);

    /* Deliver previously captured events first. A zero-delay sample is
     * intentionally visible on the next 500-us scheduler tick. */
    for (unsigned channel = 0; channel < 4; ++channel) {
        FmtSensorSimQueue *queue = &state->queues[channel];
        if (queue->count && queue->events[queue->head].arrival_us <= now_us) {
            due_events[channel] = queue->events[queue->head];
            due_events[channel].valid = 1u;
            queue->head = (queue->head + 1u) % FMT_SENSOR_SIM_QUEUE_CAPACITY;
            --queue->count;
        }
    }

    if (elapsed == 0u) return 0;
    for (unsigned channel = 0; channel < 4; ++channel) {
        const uint64_t period = (uint64_t)p[period_index[channel]];
        const unsigned mask = (unsigned)truth[FMT_SENSOR_VALID];
        FmtSensorSimEvent event;
        uint64_t pipeline = channel == FMT_SENSOR_SIM_IMU
            ? (uint64_t)p[FMT_SIM_IMU_PIPELINE_DELAY] : 0u;
        if ((elapsed % period) != 0u || (mask & valid_bits[channel]) == 0u)
            continue;
        memset(&event, 0, sizeof(event));
        event.sample_us = now_us;
        event.capture_us = now_us + pipeline;
        event.arrival_us = event.capture_us + (uint64_t)p[transport_index[channel]];
        event.sequence = ++state->sequence[channel];
        switch (channel) {
        case FMT_SENSOR_SIM_IMU: prepare_imu(state, truth, &event); break;
        case FMT_SENSOR_SIM_GNSS: prepare_gnss(state, truth, &event); break;
        case FMT_SENSOR_SIM_MAG: prepare_mag(state, truth, &event); break;
        case FMT_SENSOR_SIM_BARO: prepare_baro(state, truth, &event); break;
        default: return -1;
        }
        if (!finite_values(event.values, width[channel])) return -1;
        if (!queue_push(&state->queues[channel], &event)) return -2;
    }
    return 0;
}
