#define S_FUNCTION_NAME fmt_rigid_sfun
#define S_FUNCTION_LEVEL 2
#include "simstruc.h"
#include <math.h>
#include "fmt_rotation.h"

static void mdlInitializeSizes(SimStruct *S)
{
    ssSetNumSFcnParams(S, 1);
    if (ssGetNumSFcnParams(S) != ssGetSFcnParamsCount(S)) return;
    ssSetSFcnParamTunable(S, 0, 0);
    if (!ssSetNumInputPorts(S, 4)) return;
    ssSetInputPortWidth(S, 0, 17);
    ssSetInputPortWidth(S, 1, 6);
    ssSetInputPortWidth(S, 2, 6);
    ssSetInputPortWidth(S, 3, 15);
    for (int i = 0; i < 4; ++i) {
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

static void mdlOutputs(SimStruct *S, int_T tid)
{
    const mxArray *parameter = ssGetSFcnParam(S, 0);
    const double *p = mxGetPr(parameter);
    const double *x = ssGetInputPortRealSignal(S, 0);
    const double *rotor = ssGetInputPortRealSignal(S, 1);
    const double *ground = ssGetInputPortRealSignal(S, 2);
    const double *env = ssGetInputPortRealSignal(S, 3);
    double *dx = ssGetOutputPortRealSignal(S, 0);
    double rotation[9], angular_momentum[3], gyroscopic[3];
    (void)tid;

    if (!mxIsDouble(parameter) || mxIsComplex(parameter) || mxIsSparse(parameter) ||
        mxGetNumberOfElements(parameter) != 19 || !p) {
        ssSetErrorStatus(S, "PlantParameters must contain exactly 19 values.");
        return;
    }
    for (int i = 0; i < 19; ++i) {
        if (!isfinite(p[i])) {
            ssSetErrorStatus(S, "PlantParameters contains a nonfinite value.");
            return;
        }
    }
    if (!(p[0] > 0) || !(p[1] > 0) || !(p[2] > 0) || !(p[3] > 0) ||
        !(p[4] > 0) || !(p[5] > 0) ||
        p[6] < 0 || p[7] < 0 || p[8] < 0 || p[9] < 0 ||
        !(p[10] > 0) || p[11] < 0 || !(p[16] > 0) ||
        p[17] < 0 || p[18] < 0) {
        ssSetErrorStatus(S, "Invalid mass, inertia, motor, drag, damping, ground or gravity parameters.");
        return;
    }
    for (int i = 0; i < 17; ++i) {
        if (!isfinite(x[i])) {
            ssSetErrorStatus(S, "Plant state contains a nonfinite value.");
            return;
        }
    }
    for (int i = 0; i < 6; ++i) {
        if (!isfinite(rotor[i]) || !isfinite(ground[i])) {
            ssSetErrorStatus(S, "Rotor or ground wrench contains a nonfinite value.");
            return;
        }
    }
    for (int i = 0; i < 15; ++i) {
        if (!isfinite(env[i])) {
            ssSetErrorStatus(S, "Environment contains a nonfinite value.");
            return;
        }
    }
    if (!fmt_rotation(x + 6, rotation)) {
        ssSetErrorStatus(S, "Invalid Plant quaternion.");
        return;
    }

    for (int i = 0; i < 3; ++i) {
        double force_ned = env[3 + i];
        for (int j = 0; j < 3; ++j)
            force_ned += rotation[3 * i + j] * (rotor[j] + ground[j]);
        if (env[10] > 0.5)
            force_ned -= p[6 + i] * (x[3 + i] - env[i]);

        dx[i] = x[3 + i];
        dx[3 + i] = force_ned / p[0] + (i == 2 ? p[16] : 0);
        angular_momentum[i] = p[1 + i] * x[10 + i];
    }

    dx[6] = -0.5 * (x[7] * x[10] + x[8] * x[11] + x[9] * x[12]);
    dx[7] =  0.5 * (x[6] * x[10] + x[8] * x[12] - x[9] * x[11]);
    dx[8] =  0.5 * (x[6] * x[11] + x[9] * x[10] - x[7] * x[12]);
    dx[9] =  0.5 * (x[6] * x[12] + x[7] * x[11] - x[8] * x[10]);

    fmt_cross(x + 10, angular_momentum, gyroscopic);
    for (int i = 0; i < 3; ++i)
        dx[10 + i] = (rotor[3 + i] + ground[3 + i] + env[6 + i] -
                      p[9] * x[10 + i] - gyroscopic[i]) / p[1 + i];

    for (int i = 0; i < 13; ++i) {
        if (!isfinite(dx[i])) {
            ssSetErrorStatus(S, "Rigid-body derivative became nonfinite.");
            return;
        }
    }
}

static void mdlTerminate(SimStruct *S) { (void)S; }

#ifdef MATLAB_MEX_FILE
#include "simulink.c"
#else
#include "cg_sfun.h"
#endif
