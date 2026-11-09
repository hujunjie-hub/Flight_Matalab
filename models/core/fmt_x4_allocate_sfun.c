#define S_FUNCTION_NAME fmt_x4_allocate_sfun
#define S_FUNCTION_LEVEL 2
#include "simstruc.h"
#include <math.h>

static void mdlInitializeSizes(SimStruct *S)
{
    ssSetNumSFcnParams(S, 1);
    if (ssGetNumSFcnParams(S) != ssGetSFcnParamsCount(S)) return;
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

static double clamp(double value, double lower, double upper)
{
    return fmax(lower, fmin(value, upper));
}

static void mdlOutputs(SimStruct *S, int_T tid)
{
    const double *request = ssGetInputPortRealSignal(S, 0);
    const double *bounds = ssGetInputPortRealSignal(S, 1);
    const double *geometry = mxGetPr(ssGetSFcnParam(S, 0));
    double *force = ssGetOutputPortRealSignal(S, 0);
    double *achieved = ssGetOutputPortRealSignal(S, 1);
    double *residual = ssGetOutputPortRealSignal(S, 2);
    double *scale = ssGetOutputPortRealSignal(S, 3);
    boolean_T *valid = (boolean_T *)ssGetOutputPortSignal(S, 4);
    double rp[4], arm_component, yaw_ratio, scale_lower = 0, scale_upper = 1;
    double left_lower, left_upper, right_lower, right_upper;
    double total, collective_sum, left_collective, right_collective;
    double left_collective_lower, left_collective_upper;
    int i, j, group;
    (void)tid;

    *valid = false;
    *scale = 0;
    for (i = 0; i < 4; ++i) {
        force[i] = 0;
        achieved[i] = 0;
    }
    for (i = 0; i < 3; ++i) residual[i] = 0;

    if (mxGetNumberOfElements(ssGetSFcnParam(S, 0)) != 2 ||
        !geometry || !isfinite(geometry[0]) || !isfinite(geometry[1])) return;
    arm_component = geometry[0] / sqrt(2.0);
    yaw_ratio = geometry[1];
    /* yaw_ratio is signed: Flight's first motor has negative yaw torque. */
    if (!(arm_component > 0) || fabs(yaw_ratio) < 1e-12) return;

    for (i = 0; i < 4; ++i) {
        if (!isfinite(request[i]) || !isfinite(bounds[i]) ||
            !isfinite(bounds[4 + i]) || bounds[i] > bounds[4 + i]) return;
    }

    rp[0] = (request[1] + request[2]) / (4 * arm_component);
    rp[1] = (-request[1] + request[2]) / (4 * arm_component);
    rp[2] = -rp[0];
    rp[3] = -rp[1];

    /* Find the maximum common roll/pitch scale inside all motor bounds. */
    for (group = 0; group < 2; ++group) {
        for (i = group; i < 4; i += 2) {
            for (j = group; j < 4; j += 2) {
                double difference = rp[j] - rp[i];
                double available = bounds[4 + j] - bounds[i];
                if (difference > 1e-15) {
                    scale_upper = fmin(scale_upper, available / difference);
                } else if (difference < -1e-15) {
                    scale_lower = fmax(scale_lower, available / difference);
                } else if (available < 0) {
                    return;
                }
            }
        }
    }
    if (scale_upper < scale_lower || scale_upper < 0 || scale_lower > 1) return;
    *scale = clamp(scale_upper, 0, 1);
    for (i = 0; i < 4; ++i) rp[i] *= *scale;

    left_lower = fmax(bounds[0] - rp[0], bounds[2] - rp[2]);
    left_upper = fmin(bounds[4] - rp[0], bounds[6] - rp[2]);
    right_lower = fmax(bounds[1] - rp[1], bounds[3] - rp[3]);
    right_upper = fmin(bounds[5] - rp[1], bounds[7] - rp[3]);
    if (left_lower > left_upper || right_lower > right_upper) return;

    total = clamp(request[0], 2 * (left_lower + right_lower),
                  2 * (left_upper + right_upper));
    collective_sum = total / 2;
    left_collective_lower = fmax(left_lower, collective_sum - right_upper);
    left_collective_upper = fmin(left_upper, collective_sum - right_lower);
    if (left_collective_lower > left_collective_upper) return;

    left_collective = clamp(
        (request[3] + 2 * yaw_ratio * collective_sum) / (4 * yaw_ratio),
        left_collective_lower, left_collective_upper);
    right_collective = collective_sum - left_collective;

    force[0] = left_collective + rp[0];
    force[2] = left_collective + rp[2];
    force[1] = right_collective + rp[1];
    force[3] = right_collective + rp[3];

    achieved[0] = force[0] + force[1] + force[2] + force[3];
    achieved[1] = arm_component * (force[0] - force[1] - force[2] + force[3]);
    achieved[2] = arm_component * (force[0] + force[1] - force[2] - force[3]);
    achieved[3] = yaw_ratio * (force[0] - force[1] + force[2] - force[3]);
    for (i = 0; i < 3; ++i) residual[i] = achieved[i + 1] - request[i + 1];

    for (i = 0; i < 4; ++i) {
        if (!isfinite(force[i]) || force[i] < bounds[i] - 1e-9 ||
            force[i] > bounds[4 + i] + 1e-9) return;
    }
    *valid = true;
}

static void mdlTerminate(SimStruct *S) { (void)S; }

#ifdef MATLAB_MEX_FILE
#include "simulink.c"
#else
#include "cg_sfun.h"
#endif
