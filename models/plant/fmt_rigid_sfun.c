#define S_FUNCTION_NAME fmt_rigid_sfun
#define S_FUNCTION_LEVEL 2

#include "simstruc.h"
#include <math.h>
#include "fmt_rotation.h"
#include "fmt_plant_validation.h"

static void mdlInitializeSizes(SimStruct *S)
{
    int i;
    ssSetNumSFcnParams(S, 1);
    if (ssGetNumSFcnParams(S) != ssGetSFcnParamsCount(S)) return;
    ssSetSFcnParamTunable(S, 0, 0);

    if (!ssSetNumInputPorts(S, 4)) return;
    ssSetInputPortWidth(S, 0, 17); /* PlantState */
    ssSetInputPortWidth(S, 1, 6);  /* RotorWrench_FRD */
    ssSetInputPortWidth(S, 2, 6);  /* GroundWrench_FRD */
    ssSetInputPortWidth(S, 3, 15); /* Environment */
    for (i = 0; i < 4; ++i) {
        ssSetInputPortDirectFeedThrough(S, i, 1);
        ssSetInputPortRequiredContiguous(S, i, 1);
    }

    if (!ssSetNumOutputPorts(S, 1)) return;
    ssSetOutputPortWidth(S, 0, 13);
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

static int fmt_solve_inertia(const double *j, const double *rhs, double *solution)
{
    double l00, l10, l20, l11, l21, l22;
    double y0, y1, y2;

    /* Cholesky solve J*x=rhs for a symmetric positive-definite 3x3 matrix. */
    l00 = sqrt(j[0]);
    if (!(l00 > 0.0) || !isfinite(l00)) return 0;
    l10 = j[3] / l00;
    l20 = j[6] / l00;
    l11 = sqrt(j[4] - l10 * l10);
    if (!(l11 > 0.0) || !isfinite(l11)) return 0;
    l21 = (j[7] - l20 * l10) / l11;
    l22 = sqrt(j[8] - l20 * l20 - l21 * l21);
    if (!(l22 > 0.0) || !isfinite(l22)) return 0;

    y0 = rhs[0] / l00;
    y1 = (rhs[1] - l10 * y0) / l11;
    y2 = (rhs[2] - l20 * y0 - l21 * y1) / l22;

    solution[2] = y2 / l22;
    solution[1] = (y1 - l21 * solution[2]) / l11;
    solution[0] = (y0 - l10 * solution[1] - l20 * solution[2]) / l00;
    return fmt_finite_vector(solution, 3);
}

static void mdlOutputs(SimStruct *S, int_T tid)
{
    const double *x = ssGetInputPortRealSignal(S, 0);
    const double *rotor = ssGetInputPortRealSignal(S, 1);
    const double *ground = ssGetInputPortRealSignal(S, 2);
    const double *env = ssGetInputPortRealSignal(S, 3);
    const mxArray *parameter = ssGetSFcnParam(S, 0);
    const double *p = mxGetPr(parameter);
    double *dx = ssGetOutputPortRealSignal(S, 0);
    double r[9], inertia[9], jw[3], gyroscopic[3], rhs[3];
    double w, qx, qy, qz, wx, wy, wz;
    int i, j;

    (void)tid;

    if (!mxIsDouble(parameter) || mxIsComplex(parameter) || mxIsSparse(parameter) ||
        !p || !fmt_plant_parameters_valid(p, (int)mxGetNumberOfElements(parameter))) {
        ssSetErrorStatus(S, "Invalid PlantParameters: expected 26 finite values and a symmetric positive-definite 3x3 inertia matrix.");
        return;
    }
    if (!fmt_plant_state_valid(x)) {
        ssSetErrorStatus(S, "Invalid PlantState: values must be finite, quaternion nonzero and motor speeds nonnegative.");
        return;
    }
    if (!fmt_plant_wrench_valid(rotor) || !fmt_plant_wrench_valid(ground)) {
        ssSetErrorStatus(S, "Invalid Plant wrench: all FRD force and torque values must be finite.");
        return;
    }
    if (!fmt_plant_environment_valid(env)) {
        ssSetErrorStatus(S, "Invalid Plant Environment: flags must be 0/1 and rotor effectiveness must be within [0,1].");
        return;
    }
    if (!fmt_rotation(x + 6, r)) {
        ssSetErrorStatus(S, "Invalid Plant quaternion.");
        return;
    }

    /* Reconstruct MATLAB column-major J(:) as an exactly symmetric row-major matrix.
     * Validation above permits only round-off-sized asymmetry, which is averaged here. */
    for (i = 0; i < 3; ++i) {
        for (j = 0; j < 3; ++j) {
            const double value_ij = p[1 + i + 3 * j];
            const double value_ji = p[1 + j + 3 * i];
            inertia[3 * i + j] = (i == j) ? value_ij : 0.5 * (value_ij + value_ji);
        }
    }

    w = x[6];
    qx = x[7];
    qy = x[8];
    qz = x[9];
    wx = x[10];
    wy = x[11];
    wz = x[12];

    for (i = 0; i < 3; ++i) {
        double force_ned = env[3 + i];
        for (j = 0; j < 3; ++j) {
            force_ned += r[3 * i + j] * (rotor[j] + ground[j]);
        }
        if (env[10] == 1.0) {
            force_ned -= p[12 + i] * (x[3 + i] - env[i]);
        }

        dx[i] = x[3 + i];
        dx[3 + i] = force_ned / p[0] + (i == 2 ? p[22] : 0.0);

        jw[i] = inertia[3 * i] * x[10] +
                inertia[3 * i + 1] * x[11] +
                inertia[3 * i + 2] * x[12];
    }

    /* q_dot = 0.5 * q (scalar-first) x [0, omega_body/N0]. */
    dx[6] = -0.5 * (qx * wx + qy * wy + qz * wz);
    dx[7] =  0.5 * (w * wx + qy * wz - qz * wy);
    dx[8] =  0.5 * (w * wy + qz * wx - qx * wz);
    dx[9] =  0.5 * (w * wz + qx * wy - qy * wx);

    fmt_cross(x + 10, jw, gyroscopic);
    for (i = 0; i < 3; ++i) {
        rhs[i] = rotor[3 + i] + ground[3 + i] + env[6 + i] -
                 p[15] * x[10 + i] - gyroscopic[i];
    }
    if (!fmt_solve_inertia(inertia, rhs, dx + 10)) {
        ssSetErrorStatus(S, "Failed to solve Plant inertia system.");
        return;
    }

    if (!fmt_finite_vector(dx, 13)) {
        ssSetErrorStatus(S, "Nonfinite rigid-body derivative.");
    }
}

static void mdlTerminate(SimStruct *S) { (void)S; }

#ifdef MATLAB_MEX_FILE
#include "simulink.c"
#else
#include "cg_sfun.h"
#endif
