#define S_FUNCTION_NAME fmt_normalize_sfun
#define S_FUNCTION_LEVEL 2

#include "simstruc.h"
#include <math.h>
#include "fmt_plant_validation.h"

static void mdlInitializeSizes(SimStruct *S)
{
    ssSetNumSFcnParams(S, 0);
    if (!ssSetNumInputPorts(S, 1)) return;
    ssSetInputPortWidth(S, 0, 17);
    ssSetInputPortDirectFeedThrough(S, 0, 1);
    ssSetInputPortRequiredContiguous(S, 0, 1);

    if (!ssSetNumOutputPorts(S, 2)) return;
    ssSetOutputPortWidth(S, 0, 17);
    ssSetOutputPortWidth(S, 1, 1);
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
    const double *x = ssGetInputPortRealSignal(S, 0);
    double *y = ssGetOutputPortRealSignal(S, 0);
    double *norm_out = ssGetOutputPortRealSignal(S, 1);
    double norm_q;
    int i;

    (void)tid;

    if (!fmt_plant_state_valid(x)) {
        ssSetErrorStatus(S, "Invalid RK4 state: values must be finite, quaternion nonzero and motor speeds nonnegative.");
        return;
    }

    norm_q = hypot(hypot(x[6], x[7]), hypot(x[8], x[9]));
    if (!(norm_q > 1e-12) || !isfinite(norm_q)) {
        ssSetErrorStatus(S, "Invalid RK4 quaternion norm.");
        return;
    }

    for (i = 0; i < 17; ++i) y[i] = x[i];
    for (i = 6; i < 10; ++i) y[i] /= norm_q;
    *norm_out = norm_q;
}

static void mdlTerminate(SimStruct *S) { (void)S; }

#ifdef MATLAB_MEX_FILE
#include "simulink.c"
#else
#include "cg_sfun.h"
#endif
