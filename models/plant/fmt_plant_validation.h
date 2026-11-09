#ifndef FMT_PLANT_VALIDATION_H
#define FMT_PLANT_VALIDATION_H

#include <math.h>

/* Shared Plant contracts. The model uses a 20-element parameter vector and
 * the fixed 15-element Environment layout documented in QuadPlant-architecture.md. */

static int fmt_finite_vector(const double *values, int count)
{
    int i;
    if (!values || count <= 0) return 0;
    for (i = 0; i < count; ++i) {
        if (!isfinite(values[i])) return 0;
    }
    return 1;
}

static int fmt_plant_parameters_valid(const double *p, int count)
{
    if (count != 20 || !fmt_finite_vector(p, count)) return 0;

    if (!(p[0] > 0.0) || !(p[1] > 0.0) ||
        !(p[2] > 0.0) || !(p[3] > 0.0) ||
        !(p[4] > 0.0) || !(p[5] > 0.0) ||
        p[6] < 0.0 || p[7] < 0.0 || p[8] < 0.0 ||
        p[9] < 0.0 || !(p[10] > 0.0) || p[11] < 0.0 ||
        !(p[16] > 0.0) || p[17] < 0.0 || p[18] < 0.0 ||
        p[19] < 0.0) {
        return 0;
    }
    return 1;
}

static int fmt_plant_state_valid(const double *x)
{
    double q_norm;
    int i;
    if (!fmt_finite_vector(x, 17)) return 0;

    q_norm = hypot(hypot(x[6], x[7]), hypot(x[8], x[9]));
    if (!(q_norm > 1e-12) || !isfinite(q_norm)) return 0;

    for (i = 13; i < 17; ++i) {
        if (x[i] < 0.0) return 0;
    }
    return 1;
}

static int fmt_plant_environment_valid(const double *env)
{
    int i;
    if (!fmt_finite_vector(env, 15)) return 0;

    /* Environment flags are explicit booleans, not arbitrary thresholds. */
    if (!((env[9] == 0.0) || (env[9] == 1.0)) ||
        !((env[10] == 0.0) || (env[10] == 1.0))) {
        return 0;
    }
    /* Per-rotor loss-of-effectiveness is bounded to [0, 1]. */
    for (i = 11; i < 15; ++i) {
        if (env[i] < 0.0 || env[i] > 1.0) return 0;
    }
    return 1;
}

static int fmt_plant_wrench_valid(const double *wrench)
{
    return fmt_finite_vector(wrench, 6);
}

#endif
