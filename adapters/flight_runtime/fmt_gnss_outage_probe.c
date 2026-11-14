#include "mex.h"

/* Reuse Flight's GNSS/PPS/UTC outage-and-recovery host test. The test compiles
 * the real TimeService core and the production GNSS sample-normalization path. */
#define main fmt_gnss_outage_host_main
#include "tests/drivers/test_gnss_outage.c"
#undef main

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    const char *fields[] = {"status", "checks", "failures", "suite"};
    mxArray *result;
    int status;

    (void)prhs;
    if (nrhs != 0 || nlhs > 1) {
        mexErrMsgIdAndTxt("Flight:GnssOutageProbeArguments",
            "fmt_gnss_outage_probe accepts no inputs and returns at most one output.");
    }

    checks = 0;
    failures = 0;
    status = fmt_gnss_outage_host_main();

    if (nlhs == 0) return;
    result = mxCreateStructMatrix(1, 1, 4, fields);
    mxSetField(result, 0, "status", mxCreateDoubleScalar((double)status));
    mxSetField(result, 0, "checks", mxCreateDoubleScalar((double)checks));
    mxSetField(result, 0, "failures", mxCreateDoubleScalar((double)failures));
    mxSetField(result, 0, "suite", mxCreateString("Flight/tests/drivers/test_gnss_outage.c"));
    plhs[0] = result;
}
