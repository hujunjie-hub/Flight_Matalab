#ifndef FMT_SENSOR_SIMULATION_H
#define FMT_SENSOR_SIMULATION_H

#include <stdint.h>

enum {
    FMT_SENSOR_SIM_PARAMETER_COUNT = 10,
    FMT_SENSOR_SIM_QUEUE_CAPACITY = 32,
    FMT_SENSOR_SIM_FIXED_STEP_US = 500,
    FMT_SENSOR_SIM_IMU = 0,
    FMT_SENSOR_SIM_GNSS = 1,
    FMT_SENSOR_SIM_MAG = 2,
    FMT_SENSOR_SIM_BARO = 3,
    FMT_TIMING_IMU_PERIOD = 0,
    FMT_TIMING_MAG_PERIOD = 1,
    FMT_TIMING_BARO_PERIOD = 2,
    FMT_TIMING_GNSS_PERIOD = 3,
    FMT_TIMING_IMU_PIPELINE_DELAY = 4,
    FMT_TIMING_IMU_TRANSPORT_DELAY = 5,
    FMT_TIMING_MAG_TRANSPORT_DELAY = 6,
    FMT_TIMING_BARO_TRANSPORT_DELAY = 7,
    FMT_TIMING_GNSS_TRANSPORT_DELAY = 8,
    FMT_TIMING_IMU_PIPELINE_UNCERTAINTY = 9
};

typedef struct {
    uint64_t sample_us;
    uint64_t capture_us;
    uint64_t arrival_us;
    uint64_t release_us;
    uint32_t sequence;
    double values[6];
    uint8_t valid;
} FmtSensorSimEvent;

typedef struct {
    uint64_t opportunities;
    uint64_t generated;
    uint64_t suppressed;
    uint64_t released;
    uint64_t accepted;
    uint64_t queue_overflow;
} FmtSensorSimChannelStats;

typedef struct {
    FmtSensorSimEvent events[FMT_SENSOR_SIM_QUEUE_CAPACITY];
    uint32_t head;
    uint32_t count;
} FmtSensorSimQueue;

typedef struct {
    uint64_t epoch_us;
    uint64_t last_step_us;
    uint8_t has_stepped;
    double parameters[FMT_SENSOR_SIM_PARAMETER_COUNT];
    uint32_t sequence[4];
    FmtSensorSimQueue queues[4];
    FmtSensorSimChannelStats stats[4];
} FmtSensorSimState;

/* Returns 0 on success, -1 for invalid time/config/input, -2 on queue overflow. */
int fmt_sensor_sim_init(FmtSensorSimState *state, const double *parameters, uint64_t epoch_us);
int fmt_sensor_sim_step(FmtSensorSimState *state, const double truth_frame[18],
                        uint64_t now_us, FmtSensorSimEvent due_events[4]);
/* Call only after the downstream firmware injection/measurement sink accepts an event. */
int fmt_sensor_sim_mark_accepted(FmtSensorSimState *state, unsigned channel);

#endif
