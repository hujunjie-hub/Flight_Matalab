#define S_FUNCTION_NAME fmt_ground_sfun
#define S_FUNCTION_LEVEL 2

#include "simstruc.h"
#include <math.h>
#include "fmt_rotation.h"
#include "fmt_plant_validation.h"

static void mdlInitializeSizes(SimStruct *S)
{
    ssSetNumSFcnParams(S, 1);
    if (ssGetNumSFcnParams(S) != ssGetSFcnParamsCount(S)) return;
    ssSetSFcnParamTunable(S, 0, 0);

    if (!ssSetNumInputPorts(S, 2)) return;
    ssSetInputPortWidth(S, 0, 17);
    ssSetInputPortWidth(S, 1, 15);
    ssSetInputPortDirectFeedThrough(S, 0, 1);
    ssSetInputPortDirectFeedThrough(S, 1, 1);
    ssSetInputPortRequiredContiguous(S, 0, 1);
    ssSetInputPortRequiredContiguous(S, 1, 1);

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
    int corner, i;

    (void)tid;

    if (!mxIsDouble(parameter) || mxIsComplex(parameter) || mxIsSparse(parameter) ||
        !p || !fmt_plant_parameters_valid(p, (int)mxGetNumberOfElements(parameter))) {
        ssSetErrorStatus(S, "Invalid PlantParameters for GroundContact.");
        return;
    }
    if (!fmt_plant_state_valid(x) || !fmt_plant_environment_valid(env)) {
        ssSetErrorStatus(S, "Invalid PlantState or Environment for GroundContact.");
        return;
    }
    if (!fmt_rotation(x + 6, rotation)) {
        ssSetErrorStatus(S, "Invalid Plant quaternion.");
        return;
    }

    for (i = 0; i < 6; ++i) wrench[i] = 0.0;
    *gap = INFINITY;
    *normal = 0.0;

    for (corner = 0; corner < 4; ++corner) {
        const double lever[3] = {
            p[19] + ((corner & 1) ? p[23] : -p[23]),
            p[20] + ((corner & 2) ? p[24] : -p[24]),
            p[21]
        };
        double rotational_velocity_body[3], torque[3], force_body[3];
        double contact_down = x[2];
        double contact_velocity_down;
        double signed_gap, penetration, force_n;

        fmt_cross(x + 10, lever, rotational_velocity_body);
        for (i = 0; i < 3; ++i) {
            contact_down += rotation[6 + i] * lever[i];
        }

        signed_gap = p[18] - contact_down;
        *gap = fmin(*gap, signed_gap);
        if (env[9] == 0.0 || signed_gap > 0.0) continue;

        contact_velocity_down = x[5];
        for (i = 0; i < 3; ++i) {
            contact_velocity_down += rotation[6 + i] * rotational_velocity_body[i];
        }

        penetration = -signed_gap;
        force_n = 0.25 * fmax(0.0, p[16] * penetration + p[17] * contact_velocity_down);

        /* First-version Plant intentionally has no horizontal ground friction. */
        for (i = 0; i < 3; ++i) {
            force_body[i] = -force_n * rotation[6 + i];
        }
        fmt_cross(lever, force_body, torque);

        for (i = 0; i < 3; ++i) {
            wrench[i] += force_body[i];
            wrench[3 + i] += torque[i];
        }
        *normal += force_n;
    }

    if (!fmt_finite_vector(wrench, 6) || !isfinite(*gap) ||
        !isfinite(*normal) || *normal < 0.0) {
        ssSetErrorStatus(S, "Nonfinite or negative GroundContact output.");
    }
}

static void mdlTerminate(SimStruct *S) { (void)S; }

#ifdef MATLAB_MEX_FILE
#include "simulink.c"
#else
#include "cg_sfun.h"
#endif
