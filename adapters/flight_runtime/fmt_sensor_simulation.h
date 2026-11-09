#ifndef FMT_SENSOR_SIMULATION_H
#define FMT_SENSOR_SIMULATION_H

#include <stdint.h>

enum {
    FMT_SENSOR_SIM_PARAMETER_COUNT = 54,
    FMT_SENSOR_SIM_QUEUE_CAPACITY = 32,
    FMT_SENSOR_SIM_IMU = 0,
    FMT_SENSOR_SIM_GNSS = 1,
    FMT_SENSOR_SIM_MAG = 2,
    FMT_SENSOR_SIM_BARO = 3,
    FMT_SIM_GYRO_BIAS = 0,
    FMT_SIM_ACCEL_BIAS = 3,
    FMT_SIM_SCALE_ERROR = 6,
    FMT_SIM_IMU_INSTALLATION = 9,
    FMT_SIM_MAG_INSTALLATION = 18,
    FMT_SIM_GYRO_NOISE = 27,
    FMT_SIM_ACCEL_NOISE = 30,
    FMT_SIM_MAG_NOISE = 33,
    FMT_SIM_BARO_NOISE = 36,
    FMT_SIM_GNSS_POSITION_NOISE = 37,
    FMT_SIM_GNSS_VELOCITY_NOISE = 40,
    FMT_SIM_IMU_PERIOD = 43,
    FMT_SIM_MAG_PERIOD = 44,
    FMT_SIM_BARO_PERIOD = 45,
    FMT_SIM_GNSS_PERIOD = 46,
    FMT_SIM_IMU_PIPELINE_DELAY = 47,
    FMT_SIM_IMU_TRANSPORT_DELAY = 48,
    FMT_SIM_MAG_TRANSPORT_DELAY = 49,
    FMT_SIM_BARO_TRANSPORT_DELAY = 50,
    FMT_SIM_GNSS_TRANSPORT_DELAY = 51,
    FMT_SIM_IMU_PIPELINE_UNCERTAINTY = 52,
    FMT_SIM_RANDOM_SEED = 53
};

typedef struct {
    uint64_t sample_us;
    uint64_t capture_us;
    uint64_t arrival_us;
    uint32_t sequence;
    double values[6];
    uint8_t valid;
} FmtSensorSimEvent;

typedef struct {
    FmtSensorSimEvent events[FMT_SENSOR_SIM_QUEUE_CAPACITY];
    uint32_t head;
    uint32_t count;
} FmtSensorSimQueue;

typedef struct {
    uint64_t epoch_us;
    double parameters[FMT_SENSOR_SIM_PARAMETER_COUNT];
    uint32_t random_state[4];
    uint32_t sequence[4];
    FmtSensorSimQueue queues[4];
} FmtSensorSimState;

/* Returns 0 on success, -1 for invalid configuration/input, -2 on queue overflow. */
int fmt_sensor_sim_init(FmtSensorSimState *state, const double *parameters, uint64_t epoch_us);
int fmt_sensor_sim_step(FmtSensorSimState *state, const double truth_frame[18],
                        uint64_t now_us, FmtSensorSimEvent due_events[4]);

#endif
