#include "mex.h"

/* Reuse the exact upstream Flight time-service host suite. The test fixture
 * supplies a deterministic raw tick source and exercises the production
 * systime.c implementation without replacing or copying its algorithms. */
#define main fmt_time_service_host_main
#include "tests/time/test_time_service.c"
#undef main

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    const char *fields[] = {"status", "checks", "failures", "suite"};
    mxArray *result;
    int status;

    (void)prhs;
    if (nrhs != 0 || nlhs > 1) {
        mexErrMsgIdAndTxt("Flight:TimeServiceProbeArguments",
            "fmt_time_service_probe accepts no inputs and returns at most one output.");
    }

    checks = 0;
    failures = 0;
    status = fmt_time_service_host_main();

    if (nlhs == 0) return;
    result = mxCreateStructMatrix(1, 1, 4, fields);
    mxSetField(result, 0, "status", mxCreateDoubleScalar((double)status));
    mxSetField(result, 0, "checks", mxCreateDoubleScalar((double)checks));
    mxSetField(result, 0, "failures", mxCreateDoubleScalar((double)failures));
    mxSetField(result, 0, "suite", mxCreateString("Flight/tests/time/test_time_service.c"));
    plhs[0] = result;
}
