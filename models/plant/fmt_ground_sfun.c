#define S_FUNCTION_NAME fmt_ground_sfun
#define S_FUNCTION_LEVEL 2
#include "simstruc.h"
#include <math.h>
#include "fmt_rotation.h"

static void mdlInitializeSizes(SimStruct *S)
{
    ssSetNumSFcnParams(S, 1);
    if (ssGetNumSFcnParams(S) != ssGetSFcnParamsCount(S)) return;
    ssSetSFcnParamTunable(S, 0, 0);
    if (!ssSetNumInputPorts(S, 2)) return;
    ssSetInputPortWidth(S, 0, 17);
    ssSetInputPortWidth(S, 1, 15);
    for (int i = 0; i < 2; ++i) {
        ssSetInputPortDirectFeedThrough(S, i, 1);
        ssSetInputPortRequiredContiguous(S, i, 1);
    }
    if (!ssSetNumOutputPorts(S, 3)) return;
    ssSetOutputPortWidth(S, 0, 6);
    ssSetOutputPortWidth(S, 1, 1);
    ssSetOutputPortWidth(S, 2, 1);
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
    const double *env = ssGetInputPortRealSignal(S, 1);
    double *wrench = ssGetOutputPortRealSignal(S, 0);
    double *gap = ssGetOutputPortRealSignal(S, 1);
    double *normal = ssGetOutputPortRealSignal(S, 2);
    double rotation[9];
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
    if (!(p[10] > 0) || p[11] < 0 || p[17] < 0 || p[18] < 0) {
        ssSetErrorStatus(S, "Invalid ground stiffness, damping or skid geometry.");
        return;
    }
    for (int i = 0; i < 17; ++i) {
        if (!isfinite(x[i])) {
            ssSetErrorStatus(S, "Plant state contains a nonfinite value.");
            return;
        }
    }
    if (!isfinite(env[9])) {
        ssSetErrorStatus(S, "Ground enable input is nonfinite.");
        return;
    }
    if (!fmt_rotation(x + 6, rotation)) {
        ssSetErrorStatus(S, "Invalid Plant quaternion.");
        return;
    }

    for (int i = 0; i < 6; ++i) wrench[i] = 0;
    *gap = INFINITY;
    *normal = 0;

    for (int corner = 0; corner < 4; ++corner) {
        const double lever[3] = {
            p[13] + ((corner & 1) ? p[17] : -p[17]),
            p[14] + ((corner & 2) ? p[18] : -p[18]),
            p[15]
        };
        double rotational_velocity_body[3], torque[3], force_body[3];
        double contact_down = x[2];
        double contact_velocity_down;
        double signed_gap, penetration, force_n;

        fmt_cross(x + 10, lever, rotational_velocity_body);
        for (int i = 0; i < 3; ++i)
            contact_down += rotation[6 + i] * lever[i];

        signed_gap = p[12] - contact_down;
        *gap = fmin(*gap, signed_gap);
        if (env[9] <= 0.5 || signed_gap > 0) continue;

        contact_velocity_down = x[5];
        for (int i = 0; i < 3; ++i)
            contact_velocity_down += rotation[6 + i] * rotational_velocity_body[i];

        penetration = -signed_gap;
        force_n = 0.25 * fmax(0, p[10] * penetration + p[11] * contact_velocity_down);
        /* The first Plant version intentionally has no horizontal ground friction. */
        for (int i = 0; i < 3; ++i)
            force_body[i] = -force_n * rotation[6 + i];
        fmt_cross(lever, force_body, torque);

        for (int i = 0; i < 3; ++i) {
            wrench[i] += force_body[i];
            wrench[3 + i] += torque[i];
        }
        *normal += force_n;
    }
    for (int i = 0; i < 6; ++i) {
        if (!isfinite(wrench[i])) {
            ssSetErrorStatus(S, "Ground contact wrench became nonfinite.");
            return;
        }
    }
    if (!isfinite(*gap) || !isfinite(*normal)) {
        ssSetErrorStatus(S, "Ground contact diagnostic became nonfinite.");
        return;
    }
}

static void mdlTerminate(SimStruct *S) { (void)S; }

#ifdef MATLAB_MEX_FILE
#include "simulink.c"
#else
#include "cg_sfun.h"
#endif
