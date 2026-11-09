#ifndef FMT_ROTATION_H
#define FMT_ROTATION_H

#include <math.h>

/* Row-major C_0b: FRD body vectors to the fixed local NED frame.
 * Quaternion order is scalar-first [w, x, y, z]. */
static int fmt_rotation(const double *q, double *r)
{
    double n, w, x, y, z;

    if (!q || !r ||
        !isfinite(q[0]) || !isfinite(q[1]) ||
        !isfinite(q[2]) || !isfinite(q[3])) {
        return 0;
    }

    n = hypot(hypot(q[0], q[1]), hypot(q[2], q[3]));
    if (!(n > 1e-12) || !isfinite(n)) return 0;

    w = q[0] / n;
    x = q[1] / n;
    y = q[2] / n;
    z = q[3] / n;

    r[0] = 1.0 - 2.0 * (y * y + z * z);
    r[1] = 2.0 * (x * y - w * z);
    r[2] = 2.0 * (x * z + w * y);
    r[3] = 2.0 * (x * y + w * z);
    r[4] = 1.0 - 2.0 * (x * x + z * z);
    r[5] = 2.0 * (y * z - w * x);
    r[6] = 2.0 * (x * z - w * y);
    r[7] = 2.0 * (y * z + w * x);
    r[8] = 1.0 - 2.0 * (x * x + y * y);
    return 1;
}

static void fmt_cross(const double *a, const double *b, double *c)
{
    c[0] = a[1] * b[2] - a[2] * b[1];
    c[1] = a[2] * b[0] - a[0] * b[2];
    c[2] = a[0] * b[1] - a[1] * b[0];
}

#endif
