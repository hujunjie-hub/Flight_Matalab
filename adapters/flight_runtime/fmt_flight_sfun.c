#define S_FUNCTION_NAME fmt_flight_sfun
#define S_FUNCTION_LEVEL 2
#include "simstruc.h"
#include <windows.h>
#include "fmt_flight_runtime.h"

enum { NAV_WIDTH, DLL_PATH, PARAM_COUNT };
enum { MOTORS, STATUS, NAV, WORK_COUNT };

typedef struct {
    HMODULE library;
    FmtStart start;
    int started;
    FmtStop stop;
    FmtStep step;
} Runtime;

static int nav_width(SimStruct *S)
{
    return (int)mxGetScalar(ssGetSFcnParam(S, NAV_WIDTH));
}

static void mdlInitializeSizes(SimStruct *S)
{
    ssSetNumSFcnParams(S, PARAM_COUNT);
    if (ssGetNumSFcnParams(S) != ssGetSFcnParamsCount(S)) return;
    for (int i = 0; i < PARAM_COUNT; ++i) ssSetSFcnParamTunable(S, i, 0);
    if (!ssSetNumInputPorts(S, 6) || !ssSetNumOutputPorts(S, 3) ||
        !ssSetNumDWork(S, WORK_COUNT)) return;
    const int input_widths[] = {FMT_SENSOR_WIDTH, FMT_COMMAND_WIDTH, nav_width(S), 1, FMT_SENSOR_MODEL_PARAMETER_COUNT, FMT_SENSOR_SIM_PARAMETER_COUNT};
    const int output_widths[] = {4, FMT_STATUS_WIDTH, nav_width(S)};
    const DTypeId types[] = {SS_DOUBLE, SS_DOUBLE, SS_UINT8, SS_DOUBLE, SS_DOUBLE, SS_DOUBLE};
    const char *state_names[] = {"CommittedThrust", "FlightDiagnostics", "NavigationFrame"};
    for (int i = 0; i < 3; ++i) {
        ssSetInputPortWidth(S, i, input_widths[i]);
        ssSetInputPortDataType(S, i, types[i]);
        ssSetInputPortDirectFeedThrough(S, i, 0);
        ssSetInputPortRequiredContiguous(S, i, 1);
        ssSetOutputPortWidth(S, i, output_widths[i]);
        ssSetOutputPortDataType(S, i, types[i]);
        ssSetDWorkWidth(S, i, output_widths[i]);
        ssSetDWorkDataType(S, i, types[i]);
        ssSetDWorkName(S, i, state_names[i]);
        ssSetDWorkUsedAsDState(S, i, 1);
    }
    for (int i = 3; i < 6; ++i) {
        ssSetInputPortWidth(S, i, input_widths[i]);
        ssSetInputPortDataType(S, i, types[i]);
        ssSetInputPortDirectFeedThrough(S, i, 0);
        ssSetInputPortRequiredContiguous(S, i, 1);
    }
    ssSetNumPWork(S, 1);
    ssSetNumSampleTimes(S, 1);
    ssSetSimStateCompliance(S, DISALLOW_SIM_STATE);
}

static void mdlInitializeSampleTimes(SimStruct *S)
{
    ssSetSampleTime(S, 0, .0005);
    ssSetOffsetTime(S, 0, 0);
    ssSetModelReferenceSampleTimeDefaultInheritance(S);
}

#define MDL_START
static void mdlStart(SimStruct *S)
{
    const mxArray *path = ssGetSFcnParam(S, DLL_PATH);
    Runtime *runtime = calloc(1, sizeof(*runtime));
    wchar_t file[MAX_PATH];
    if (!runtime || !mxIsChar(path) || mxGetNumberOfElements(path) >= MAX_PATH) {
        free(runtime);
        ssSetErrorStatus(S, "Invalid Flight SIL runtime path.");
        return;
    }
    const mxChar *chars = mxGetChars(path);
    size_t n = mxGetNumberOfElements(path);
    for (size_t i = 0; i < n; ++i) file[i] = chars[i];
    file[n] = L'\0';
    runtime->library = LoadLibraryW(file);
    if (!runtime->library) {
        free(runtime);
        ssSetErrorStatus(S, "Build the Flight SIL DLL with tools/build_flight_runtime.ps1.");
        return;
    }
    runtime->start = (FmtStart)GetProcAddress(runtime->library, "fmt_flight_start");
    FmtNavWidth width = (FmtNavWidth)GetProcAddress(runtime->library, "fmt_flight_nav_width");
    runtime->stop = (FmtStop)GetProcAddress(runtime->library, "fmt_flight_stop");
    runtime->step = (FmtStep)GetProcAddress(runtime->library, "fmt_flight_step");
    if (!runtime->start || !width || !runtime->stop || !runtime->step ||
        width() != (unsigned)nav_width(S)) {
        FreeLibrary(runtime->library);
        free(runtime);
        ssSetErrorStatus(S, "Flight SIL failed to initialize. Check the replay ABI and run one entry per process.");
        return;
    }
    ssSetPWorkValue(S, 0, runtime);
}

static void mdlOutputs(SimStruct *S, int_T tid)
{
    (void)tid;
    memcpy(ssGetOutputPortSignal(S, MOTORS), ssGetDWork(S, MOTORS), 4 * sizeof(double));
    memcpy(ssGetOutputPortSignal(S, STATUS), ssGetDWork(S, STATUS), FMT_STATUS_WIDTH * sizeof(double));
    memcpy(ssGetOutputPortSignal(S, NAV), ssGetDWork(S, NAV), nav_width(S));
}

#define MDL_UPDATE
static void mdlUpdate(SimStruct *S, int_T tid)
{
    (void)tid;
    Runtime *runtime = ssGetPWorkValue(S, 0);
    if (!runtime->started) {
        if (runtime->start((int)*ssGetInputPortRealSignal(S, 3))) {
            ssSetErrorStatus(S, "Flight SIL initialization failed. Run one entry per process.");
            return;
        }
        runtime->started = 1;
    }
    if (runtime->step(ssGetInputPortRealSignal(S, 0), ssGetInputPortRealSignal(S, 1),
                      ssGetInputPortSignal(S, 2), ssGetInputPortRealSignal(S, 4),
                      ssGetInputPortRealSignal(S, 5), ssGetDWork(S, MOTORS),
                      ssGetDWork(S, STATUS), ssGetDWork(S, NAV)))
        ssSetErrorStatus(S, "Flight SIL scheduler failed.");
}

static void mdlTerminate(SimStruct *S)
{
    Runtime *runtime = ssGetPWorkValue(S, 0);
    if (runtime) {
        if (runtime->started) runtime->stop();
        FreeLibrary(runtime->library);
        free(runtime);
    }
}

#include "simulink.c"


