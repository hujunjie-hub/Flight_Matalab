#ifndef FMT_FLIGHT_RUNTIME_H
#define FMT_FLIGHT_RUNTIME_H

#include <stdint.h>
#include "fmt_sensor_simulation.h"

enum {
    FMT_DATA_SIM = 0, FMT_MIL_SIM = 1, FMT_EXTINS_DATA_SIM = 2,
    FMT_SENSOR_WIDTH = 18, FMT_COMMAND_WIDTH = 2, FMT_STATUS_WIDTH = 24,
    FMT_SENSOR_GYRO = 0, FMT_SENSOR_ACCEL = 3, FMT_SENSOR_POSITION = 6,
    FMT_SENSOR_VELOCITY = 9, FMT_SENSOR_MAG = 12, FMT_SENSOR_BARO = 15,
    FMT_SENSOR_VALID = 16, FMT_SENSOR_CONTACT = 17,
    FMT_IMU_VALID = 1, FMT_GNSS_VALID = 2, FMT_MAG_VALID = 4, FMT_BARO_VALID = 8
};

typedef int (*FmtStart)(int mode);
typedef void (*FmtStop)(void);
typedef unsigned (*FmtNavWidth)(void);
typedef int (*FmtStep)(const double *sensor, const double *command, const uint8_t *external_nav, 
                       const double *sensor_sim_parameters, double *force, double *status,
                       uint8_t *published_nav);

#endif
