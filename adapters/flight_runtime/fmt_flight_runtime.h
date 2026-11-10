#ifndef FMT_FLIGHT_RUNTIME_H
#define FMT_FLIGHT_RUNTIME_H

#include <stdint.h>
#include "fmt_sensor_simulation.h"

enum {
    FMT_DATA_SIM = 0, FMT_MIL_SIM = 1, FMT_EXTINS_DATA_SIM = 2,
    FMT_SENSOR_WIDTH = 18, FMT_COMMAND_WIDTH = 2, FMT_STATUS_WIDTH = 40,
    FMT_SENSOR_GYRO = 0, FMT_SENSOR_ACCEL = 3, FMT_SENSOR_POSITION = 6,
    FMT_SENSOR_VELOCITY = 9, FMT_SENSOR_MAG = 12, FMT_SENSOR_BARO = 15,
    FMT_SENSOR_VALID = 16, FMT_SENSOR_CONTACT = 17,
    FMT_IMU_VALID = 1, FMT_GNSS_VALID = 2, FMT_MAG_VALID = 4, FMT_BARO_VALID = 8,
    FMT_SENSOR_MODEL_PARAMETER_COUNT = 54,
    FMT_MODEL_MAG_NOISE = 43, FMT_MODEL_GNSS_POSITION_NOISE = 46,
    FMT_MODEL_GNSS_VELOCITY_NOISE = 49, FMT_MODEL_BARO_NOISE = 52
};

typedef int (*FmtStart)(int mode);
typedef void (*FmtStop)(void);
typedef unsigned (*FmtNavWidth)(void);
typedef int (*FmtStep)(const double *sensor, const double *command, const uint8_t *external_nav, 
                       const double *sensor_model_parameters, const double *sensor_timing_parameters,
                       double *force, double *status, uint8_t *published_nav);

#endif
