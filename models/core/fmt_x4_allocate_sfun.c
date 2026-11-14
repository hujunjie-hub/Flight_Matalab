#define S_FUNCTION_NAME fmt_x4_allocate_sfun
#define S_FUNCTION_LEVEL 2
#include "simstruc.h"
#include <math.h>

static double clamp_value(double value, double lower, double upper)
{
    return fmax(lower, fmin(value, upper));
}

static double parameter_at(const double *p, int row, int col)
{
    /* AllocationMatrices is an 8x4 MATLAB column-major matrix:
       rows 1..4 are inverse(E), rows 5..8 are E. */
    return p[row + 8 * col];
}

static int solve3(const double a[3][3], const double b[3], double x[3])
{
    double m[3][4];
    int i, j, k, pivot;
    for (i = 0; i < 3; ++i) {
        for (j = 0; j < 3; ++j) m[i][j] = a[i][j];
        m[i][3] = b[i];
    }
    for (i = 0; i < 3; ++i) {
        pivot = i;
        for (j = i + 1; j < 3; ++j)
            if (fabs(m[j][i]) > fabs(m[pivot][i])) pivot = j;
        if (fabs(m[pivot][i]) < 1e-12) return 0;
        for (k = i; k < 4; ++k) {
            double temp = m[i][k];
            m[i][k] = m[pivot][k];
            m[pivot][k] = temp;
        }
        {
            double divisor = m[i][i];
            for (k = i; k < 4; ++k) m[i][k] /= divisor;
        }
        for (j = 0; j < 3; ++j) {
            if (j == i) continue;
            {
                double factor = m[j][i];
                for (k = i; k < 4; ++k) m[j][k] -= factor * m[i][k];
            }
        }
    }
    for (i = 0; i < 3; ++i) x[i] = m[i][3];
    return 1;
}

static int feasible(const double a[14][3], const double b[14], const double x[3])
{
    int i;
    for (i = 0; i < 14; ++i)
        if (a[i][0] * x[0] + a[i][1] * x[1] + a[i][2] * x[2] > b[i] + 1e-7)
            return 0;
    return 1;
}

static void mdlInitializeSizes(SimStruct *S)
{
    ssSetNumSFcnParams(S, 1);
    if (ssGetNumSFcnParams(S) != ssGetSFcnParamsCount(S)) return;
    ssSetSFcnParamTunable(S, 0, 0);
    if (!ssSetNumInputPorts(S, 2)) return;
    ssSetInputPortWidth(S, 0, 4);
    ssSetInputPortWidth(S, 1, 8);
    for (int i = 0; i < 2; ++i) {
        ssSetInputPortDirectFeedThrough(S, i, 1);
        ssSetInputPortRequiredContiguous(S, i, 1);
    }
    if (!ssSetNumOutputPorts(S, 5)) return;
    ssSetOutputPortWidth(S, 0, 4);
    ssSetOutputPortWidth(S, 1, 4);
    ssSetOutputPortWidth(S, 2, 3);
    ssSetOutputPortWidth(S, 3, 1);
    ssSetOutputPortWidth(S, 4, 1);
    ssSetOutputPortDataType(S, 4, SS_BOOLEAN);
    ssSetNumSampleTimes(S, 1);
    ssSetOptions(S, SS_OPTION_EXCEPTION_FREE_CODE);
}

static void mdlInitializeSampleTimes(SimStruct *S)
{
    ssSetSampleTime(S, 0, INHERITED_SAMPLE_TIME);
    ssSetOffsetTime(S, 0, 0);
    ssSetModelReferenceSampleTimeDefaultInheritance(S);
}

#define MDL_SET_WORK_WIDTHS
static void mdlSetWorkWidths(SimStruct *S)
{
    ssSupportsMultipleExecInstances(S, true);
}

static void mdlOutputs(SimStruct *S, int_T tid)
{
    const mxArray *parameter = ssGetSFcnParam(S, 0);
    const double *p = mxGetPr(parameter);
    const double *request = ssGetInputPortRealSignal(S, 0);
    const double *bounds = ssGetInputPortRealSignal(S, 1);
    double inverse[4][4], effectiveness[4][4];
    double a[14][3] = {{0}}, b[14] = {0}, x[3], aa[3][3], bb[3];
    double lower[4], upper[4], minimum_total = 0, maximum_total = 0;
    double best = -1, total_min = 1e100, total_max = -1e100;
    double collective, yaw_lower = 0, yaw_upper = 1;
    double *force = ssGetOutputPortRealSignal(S, 0);
    double *achieved = ssGetOutputPortRealSignal(S, 1);
    double *residual = ssGetOutputPortRealSignal(S, 2);
    double *scale = ssGetOutputPortRealSignal(S, 3);
    boolean_T *valid = (boolean_T *)ssGetOutputPortSignal(S, 4);
    int i, j, k, row, col;
    (void)tid;

    *valid = false;
    *scale = 0;
    for (i = 0; i < 4; ++i) {
        force[i] = 0;
        achieved[i] = 0;
    }
    for (i = 0; i < 3; ++i) residual[i] = 0;

    if (!mxIsDouble(parameter) || mxIsComplex(parameter) || mxIsSparse(parameter) ||
        mxGetM(parameter) != 8 || mxGetN(parameter) != 4 || !p) return;
    for (col = 0; col < 4; ++col) {
        for (row = 0; row < 4; ++row) {
            inverse[row][col] = parameter_at(p, row, col);
            effectiveness[row][col] = parameter_at(p, row + 4, col);
            if (!isfinite(inverse[row][col]) || !isfinite(effectiveness[row][col])) return;
        }
    }
    /* Reject a stale/malformed inverse rather than allocate with mismatched geometry. */
    for (i = 0; i < 4; ++i) {
        for (j = 0; j < 4; ++j) {
            double product = 0;
            for (k = 0; k < 4; ++k) product += effectiveness[i][k] * inverse[k][j];
            if (fabs(product - (i == j ? 1.0 : 0.0)) > 1e-6) return;
        }
    }
    for (i = 0; i < 4; ++i) {
        if (!isfinite(request[i]) || !isfinite(bounds[i]) ||
            !isfinite(bounds[4 + i]) || bounds[i] > bounds[4 + i]) return;
        lower[i] = bounds[i];
        upper[i] = bounds[4 + i];
        minimum_total += lower[i];
        maximum_total += upper[i];
    }

    /* Port of Flight control_allocate_limited: lexicographic RP, collective, yaw. */
    for (i = 0; i < 4; ++i) {
        a[2 * i][0] = inverse[i][1] * request[1] + inverse[i][2] * request[2];
        a[2 * i][1] = inverse[i][0];
        a[2 * i][2] = inverse[i][3] * request[3];
        for (j = 0; j < 3; ++j) a[2 * i + 1][j] = -a[2 * i][j];
        b[2 * i] = upper[i];
        b[2 * i + 1] = -lower[i];
    }
    a[8][0] = 1;  b[8] = 1;
    a[9][0] = -1;
    a[10][2] = 1; b[10] = 1;
    a[11][2] = -1;
    a[12][1] = 1; b[12] = maximum_total;
    a[13][1] = -1; b[13] = -minimum_total;

    for (i = 0; i < 12; ++i) {
        for (j = i + 1; j < 13; ++j) {
            for (k = j + 1; k < 14; ++k) {
                for (row = 0; row < 3; ++row) {
                    aa[0][row] = a[i][row];
                    aa[1][row] = a[j][row];
                    aa[2][row] = a[k][row];
                }
                bb[0] = b[i]; bb[1] = b[j]; bb[2] = b[k];
                if (solve3(aa, bb, x) && feasible(a, b, x) && x[0] > best)
                    best = x[0];
            }
        }
    }
    if (best < 0) return;
    best = clamp_value(best, 0, 1);

    for (i = 0; i < 14; ++i) {
        for (j = i + 1; j < 14; ++j) {
            double determinant = a[i][1] * a[j][2] - a[i][2] * a[j][1];
            if (fabs(determinant) < 1e-12) continue;
            {
                double bi = b[i] - a[i][0] * best;
                double bj = b[j] - a[j][0] * best;
                x[0] = best;
                x[1] = (bi * a[j][2] - bj * a[i][2]) / determinant;
                x[2] = (a[i][1] * bj - a[j][1] * bi) / determinant;
            }
            if (feasible(a, b, x)) {
                total_min = fmin(total_min, x[1]);
                total_max = fmax(total_max, x[1]);
            }
        }
    }
    if (total_min > total_max) return;
    collective = clamp_value(request[0], total_min, total_max);

    for (i = 0; i < 8; ++i) {
        double rhs = b[i] - a[i][0] * best - a[i][1] * collective;
        if (a[i][2] > 1e-12)
            yaw_upper = fmin(yaw_upper, rhs / a[i][2]);
        else if (a[i][2] < -1e-12)
            yaw_lower = fmax(yaw_lower, rhs / a[i][2]);
        else if (rhs < -1e-6)
            return;
    }
    if (yaw_lower > yaw_upper + 1e-6) return;
    x[0] = best;
    x[1] = collective;
    x[2] = clamp_value(yaw_upper, 0, 1);
    if (!feasible(a, b, x)) return;

    for (i = 0; i < 4; ++i) {
        force[i] = a[2 * i][0] * best +
                   a[2 * i][1] * collective +
                   a[2 * i][2] * x[2];
        if (!isfinite(force[i]) || force[i] < lower[i] - 1e-7 ||
            force[i] > upper[i] + 1e-7) {
            for (j = 0; j < 4; ++j) force[j] = 0;
            return;
        }
    }
    for (i = 0; i < 4; ++i) {
        for (j = 0; j < 4; ++j)
            achieved[i] += effectiveness[i][j] * force[j];
    }
    for (i = 0; i < 3; ++i) residual[i] = achieved[i + 1] - request[i + 1];
    *scale = best;
    *valid = true;
}

static void mdlTerminate(SimStruct *S) { (void)S; }

#ifdef MATLAB_MEX_FILE
#include "simulink.c"
#else
#include "cg_sfun.h"
#endif
