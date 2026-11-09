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
    ssSetInputPortWidth(S, 0, 17); /* PlantState */
    ssSetInputPortWidth(S, 1, 15); /* Environment */
    ssSetInputPortDirectFeedThrough(S, 0, 1);
    ssSetInputPortDirectFeedThrough(S, 1, 1);
    ssSetInputPortRequiredContiguous(S, 0, 1);
    ssSetInputPortRequiredContiguous(S, 1, 1);

    if (!ssSetNumOutputPorts(S, 3)) return;
    ssSetOutputPortWidth(S, 0, 6); /* GroundWrench_FRD */
    ssSetOutputPortWidth(S, 1, 1); /* SignedGapM */
    ssSetOutputPortWidth(S, 2, 1); /* NormalForceN */
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
    const double *env = ssGetInputPortRealSignal(S, 1);
    const mxArray *parameter = ssGetSFcnParam(S, 0);
    const double *p = mxGetPr(parameter);
    double *wrench = ssGetOutputPortRealSignal(S, 0);
    double *gap = ssGetOutputPortRealSignal(S, 1);
    double *normal = ssGetOutputPortRealSignal(S, 2);
    double r[9];
    int corner, i, j;

    (void)tid;

    if (!mxIsDouble(parameter) || mxIsComplex(parameter) || mxIsSparse(parameter) ||
        !p || !fmt_plant_parameters_valid(p, (int)mxGetNumberOfElements(parameter))) {
        ssSetErrorStatus(S, "Invalid PlantParameters for GroundContact.");
        return;
    }
    if (!fmt_plant_state_valid(x)) {
        ssSetErrorStatus(S, "Invalid PlantState for GroundContact.");
        return;
    }
    if (!fmt_plant_environment_valid(env)) {
        ssSetErrorStatus(S, "Invalid Plant Environment for GroundContact.");
        return;
    }
    if (!fmt_rotation(x + 6, r)) {
        ssSetErrorStatus(S, "Invalid Plant quaternion.");
        return;
    }

    for (i = 0; i < 6; ++i) wrench[i] = 0.0;
    *gap = INFINITY;
    *normal = 0.0;

    for (corner = 0; corner < 4; ++corner) {
        const double lever[3] = {
            p[13] + ((corner & 1) ? p[17] : -p[17]),
            p[14] + ((corner & 2) ? p[18] : -p[18]),
            p[15]
        };
        double velocity_body[3], velocity_ned[3], force_body[3], torque_body[3];
        double contact_down = x[2];

        fmt_cross(x + 10, lever, velocity_body);
        for (i = 0; i < 3; ++i) {
            contact_down += r[6 + i] * lever[i];
        }

        /* Positive clearance means above the ground; no air damping force. */
        {
            const double clearance = p[12] - contact_down;
            *gap = fmin(*gap, clearance);
            if (env[9] == 0.0 || clearance > 0.0) continue;

            for (i = 0; i < 3; ++i) {
                velocity_ned[i] = x[3 + i];
                for (j = 0; j < 3; ++j) {
                    velocity_ned[i] += r[3 * i + j] * velocity_body[j];
                }
            }

            /* Down-positive NED: spring/damper force acts upward. */
            {
                const double normal_force =
                    0.25 * fmax(0.0, -p[10] * clearance + p[11] * velocity_ned[2]);
                const double slip = hypot(velocity_ned[0], velocity_ned[1]);
                const double friction_scale =
                    -p[19] * normal_force / fmax(slip, 0.05);
                const double force_ned[3] = {
                    friction_scale * velocity_ned[0],
                    friction_scale * velocity_ned[1],
                    -normal_force
                };

                for (i = 0; i < 3; ++i) {
                    force_body[i] = r[i] * force_ned[0] +
                                    r[3 + i] * force_ned[1] +
                                    r[6 + i] * force_ned[2];
                }
                fmt_cross(lever, force_body, torque_body);

                for (i = 0; i < 3; ++i) {
                    wrench[i] += force_body[i];
                    wrench[3 + i] += torque_body[i];
                }
                *normal += normal_force;
            }
        }
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
