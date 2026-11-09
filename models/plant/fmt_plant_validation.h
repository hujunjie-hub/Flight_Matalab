#ifndef FMT_PLANT_VALIDATION_H
#define FMT_PLANT_VALIDATION_H

#include <math.h>

/* PlantParameters is a 26-element vector:
 * [mass; J(:); kf; tau; drag_NED(3); rateDamping; groundK; groundC;
 *  groundDown; contactLever_FRD(3); gravity; skidHalfSpan(2); friction].
 * J(:) follows MATLAB column-major order. Environment is a fixed 15-vector. */

static int fmt_finite_vector(const double *values, int count)
{
    int i;
    if (!values || count <= 0) return 0;
    for (i = 0; i < count; ++i) {
        if (!isfinite(values[i])) return 0;
    }
    return 1;
}

static int fmt_plant_inertia_valid(const double *p)
{
    const double a = p[1];
    const double b = 0.5 * (p[2] + p[4]);
    const double c = 0.5 * (p[3] + p[7]);
    const double d = p[5];
    const double e = 0.5 * (p[6] + p[8]);
    const double f = p[9];
    const double scale = fmax(1.0, fmax(fabs(a), fmax(fabs(b),
                         fmax(fabs(c), fmax(fabs(d), fmax(fabs(e), fabs(f)))))));
    const double symmetry_tolerance = 1e-10 * scale;
    const double minor2 = a * d - b * b;
    const double determinant =
        a * (d * f - e * e) - b * (b * f - c * e) + c * (b * e - c * d);

    if (fabs(p[2] - p[4]) > symmetry_tolerance ||
        fabs(p[3] - p[7]) > symmetry_tolerance ||
        fabs(p[6] - p[8]) > symmetry_tolerance) {
        return 0;
    }
    /* Sylvester criterion for a symmetric 3x3 positive-definite matrix. */
    return a > 0.0 && minor2 > 0.0 && determinant > 0.0 &&
           isfinite(minor2) && isfinite(determinant);
}

static int fmt_plant_parameters_valid(const double *p, int count)
{
    int i;
    if (count != 26 || !fmt_finite_vector(p, count)) return 0;

    if (!(p[0] > 0.0) || !fmt_plant_inertia_valid(p) ||
        !(p[10] > 0.0) || !(p[11] > 0.0) ||
        p[15] < 0.0 || !(p[16] > 0.0) || p[17] < 0.0 ||
        !(p[22] > 0.0) || p[23] < 0.0 || p[24] < 0.0 || p[25] < 0.0) {
        return 0;
    }
    for (i = 12; i <= 14; ++i) {
        if (p[i] < 0.0) return 0;
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

    if (!((env[9] == 0.0) || (env[9] == 1.0)) ||
        !((env[10] == 0.0) || (env[10] == 1.0))) {
        return 0;
    }
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
