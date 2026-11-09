#include "fmt_sensor_simulation.h"
#include "fmt_flight_runtime.h"

#include <math.h>
#include <string.h>

static int finite_values(const double *values, unsigned count)
{
    for (unsigned i = 0; i < count; ++i)
        if (!isfinite(values[i])) return 0;
    return 1;
}

static int integer_value(double value, uint64_t *out)
{
    if (!isfinite(value) || value < 0.0 || value > 9.0e15 || floor(value) != value)
        return 0;
    *out = (uint64_t)value;
    return 1;
}

static int validate_parameters(const double *p)
{
    uint64_t periods[4], transports[4], pipeline, uncertainty;
    const unsigned period_index[4] = {
        FMT_TIMING_IMU_PERIOD, FMT_TIMING_GNSS_PERIOD,
        FMT_TIMING_MAG_PERIOD, FMT_TIMING_BARO_PERIOD
    };
    const unsigned transport_index[4] = {
        FMT_TIMING_IMU_TRANSPORT_DELAY, FMT_TIMING_GNSS_TRANSPORT_DELAY,
        FMT_TIMING_MAG_TRANSPORT_DELAY, FMT_TIMING_BARO_TRANSPORT_DELAY
    };

    if (!p || !finite_values(p, FMT_SENSOR_SIM_PARAMETER_COUNT)) return 0;
    for (unsigned i = 0; i < 4; ++i) {
        if (!integer_value(p[period_index[i]], &periods[i]) ||
            (i == FMT_SENSOR_SIM_IMU
                ? periods[i] < 1000u || periods[i] % 1000u != 0u
                : periods[i] < 500u || periods[i] % 500u != 0u) ||
            !integer_value(p[transport_index[i]], &transports[i]))
            return 0;
    }
    if (!integer_value(p[FMT_TIMING_IMU_PIPELINE_DELAY], &pipeline) ||
        !integer_value(p[FMT_TIMING_IMU_PIPELINE_UNCERTAINTY], &uncertainty) ||
        uncertainty > UINT32_MAX)
        return 0;

    if (pipeline + transports[FMT_SENSOR_SIM_IMU] >=
        (FMT_SENSOR_SIM_QUEUE_CAPACITY - 2u) * periods[FMT_SENSOR_SIM_IMU])
        return 0;
    for (unsigned channel = FMT_SENSOR_SIM_GNSS; channel <= FMT_SENSOR_SIM_BARO; ++channel) {
        if (transports[channel] >=
            (FMT_SENSOR_SIM_QUEUE_CAPACITY - 2u) * periods[channel])
            return 0;
    }
    return 1;
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

int fmt_sensor_sim_init(FmtSensorSimState *state, const double *parameters, uint64_t epoch_us)
{
    if (!state || !validate_parameters(parameters)) return -1;
    memset(state, 0, sizeof(*state));
    memcpy(state->parameters, parameters,
           sizeof(double) * FMT_SENSOR_SIM_PARAMETER_COUNT);
    state->epoch_us = epoch_us;
    state->last_step_us = epoch_us;
    return 0;
}

int fmt_sensor_sim_step(FmtSensorSimState *state, const double truth[18],
                        uint64_t now_us, FmtSensorSimEvent due_events[4])
{
    const double *p;
    uint64_t elapsed;
    double mask_value;
    unsigned mask;
    const unsigned valid_bits[4] = {
        FMT_IMU_VALID, FMT_GNSS_VALID, FMT_MAG_VALID, FMT_BARO_VALID
    };
    const unsigned period_index[4] = {
        FMT_TIMING_IMU_PERIOD, FMT_TIMING_GNSS_PERIOD,
        FMT_TIMING_MAG_PERIOD, FMT_TIMING_BARO_PERIOD
    };
    const unsigned transport_index[4] = {
        FMT_TIMING_IMU_TRANSPORT_DELAY, FMT_TIMING_GNSS_TRANSPORT_DELAY,
        FMT_TIMING_MAG_TRANSPORT_DELAY, FMT_TIMING_BARO_TRANSPORT_DELAY
    };
    const unsigned source_index[4] = {
        FMT_SENSOR_GYRO, FMT_SENSOR_POSITION, FMT_SENSOR_MAG, FMT_SENSOR_BARO
    };
    const unsigned width[4] = {6, 6, 3, 1};

    if (!state || !truth || !due_events || now_us < state->epoch_us ||
        !finite_values(truth, 18))
        return -1;
    if (state->has_stepped) {
        if (now_us <= state->last_step_us ||
            now_us - state->last_step_us != FMT_SENSOR_SIM_FIXED_STEP_US)
            return -1;
    } else if (now_us != state->epoch_us &&
               now_us - state->epoch_us != FMT_SENSOR_SIM_FIXED_STEP_US) {
        return -1;
    }
    mask_value = truth[FMT_SENSOR_VALID];
    if (mask_value < 0.0 || mask_value > 15.0 || floor(mask_value) != mask_value)
        return -1;
    mask = (unsigned)mask_value;
    state->last_step_us = now_us;
    state->has_stepped = 1u;

    p = state->parameters;
    elapsed = now_us - state->epoch_us;
    memset(due_events, 0, sizeof(FmtSensorSimEvent) * 4u);

    if (elapsed != 0u) {
        for (unsigned channel = 0; channel < 4; ++channel) {
            const uint64_t period = (uint64_t)p[period_index[channel]];
            const uint64_t pipeline = channel == FMT_SENSOR_SIM_IMU
                ? (uint64_t)p[FMT_TIMING_IMU_PIPELINE_DELAY] : 0u;
            const uint64_t transport = (uint64_t)p[transport_index[channel]];
            FmtSensorSimEvent event;

            if ((elapsed % period) != 0u) continue;
            ++state->stats[channel].opportunities;
            ++state->sequence[channel];
            if ((mask & valid_bits[channel]) == 0u) {
                ++state->stats[channel].suppressed;
                continue;
            }
            if (UINT64_MAX - now_us < pipeline ||
                UINT64_MAX - (now_us + pipeline) < transport)
                return -1;

            memset(&event, 0, sizeof(event));
            event.sample_us = now_us;
            event.capture_us = now_us + pipeline;
            event.arrival_us = event.capture_us + transport;
            event.sequence = state->sequence[channel];
            if (channel == FMT_SENSOR_SIM_IMU) {
                memcpy(event.values, truth + FMT_SENSOR_GYRO, 3u * sizeof(double));
                memcpy(event.values + 3, truth + FMT_SENSOR_ACCEL, 3u * sizeof(double));
            } else if (channel == FMT_SENSOR_SIM_GNSS) {
                memcpy(event.values, truth + FMT_SENSOR_POSITION, 6u * sizeof(double));
            } else {
                memcpy(event.values, truth + source_index[channel], width[channel] * sizeof(double));
            }
            if (!finite_values(event.values, width[channel])) return -1;
            if (!queue_push(&state->queues[channel], &event)) {
                ++state->stats[channel].queue_overflow;
                return -2;
            }
            ++state->stats[channel].generated;
        }
    }

    /* One due event per channel is possible on the fixed 500-us simulation clock. */
    for (unsigned channel = 0; channel < 4; ++channel) {
        FmtSensorSimQueue *queue = &state->queues[channel];
        if (queue->count && queue->events[queue->head].arrival_us <= now_us) {
            if (queue->count > 1u) {
                const uint32_t next = (queue->head + 1u) % FMT_SENSOR_SIM_QUEUE_CAPACITY;
                if (queue->events[next].arrival_us <= now_us)
                    return -2;
            }
            due_events[channel] = queue->events[queue->head];
            due_events[channel].valid = 1u;
            queue->head = (queue->head + 1u) % FMT_SENSOR_SIM_QUEUE_CAPACITY;
            --queue->count;
            ++state->stats[channel].released;
        }
    }
    return 0;
}

int fmt_sensor_sim_mark_accepted(FmtSensorSimState *state, unsigned channel)
{
    if (!state || channel >= 4u ||
        state->stats[channel].accepted >= state->stats[channel].released)
        return -1;
    ++state->stats[channel].accepted;
    return 0;
}
