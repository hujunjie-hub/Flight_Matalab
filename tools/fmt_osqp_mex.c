/* Host-only gateway to the read-only locked OSQP 1.0.0 mode-2 runtime.
 * The gateway contains no QP construction or controller logic.
 */
#include "mex.h"
#include "osqp.h"
#include "quad_workspace.h"
#include <math.h>

static void read_vector(const mxArray *in, OSQPFloat *out, mwSize n) {
    mwSize i;
    if (!mxIsDouble(in) || mxIsComplex(in) || mxIsSparse(in) || mxGetNumberOfElements(in)!=n)
        mexErrMsgIdAndTxt("Flight:OSQPShape","Inputs must be full real double vectors of the fixed size.");
    for(i=0;i<n;++i) {
        double v=mxGetDoubles(in)[i];
        if(!mxIsFinite(v)) mexErrMsgIdAndTxt("Flight:OSQPFinite","Nonfinite QP input.");
        out[i]=(OSQPFloat)v;
        if(!isfinite(out[i])) mexErrMsgIdAndTxt("Flight:OSQPRange","QP value exceeds float range.");
    }
}

void mexFunction(int nlhs,mxArray **plhs,int nrhs,const mxArray **prhs) {
    OSQPFloat p[45],q[15],a[702],l[190],u[190];
    OSQPInt code;
    mwSize i;
    if(nrhs==0 && nlhs==0) {
        osqp_cold_start(&quad_solver);
        code=osqp_update_rho(&quad_solver,(OSQPFloat)0.1);
        if(code) mexErrMsgIdAndTxt("Flight:OSQPReset","Solver reset failed: %d.",(int)code);
        return;
    }
    if(nrhs!=5 || nlhs!=3)
        mexErrMsgIdAndTxt("Flight:OSQPUsage","[x,y,info]=fmt_osqp_mex(Px,q,Ax,l,u); no arguments resets the solver.");
    read_vector(prhs[0],p,45); read_vector(prhs[1],q,15);
    read_vector(prhs[2],a,702); read_vector(prhs[3],l,190); read_vector(prhs[4],u,190);
    for(i=0;i<190;++i) if(l[i]>u[i])
        mexErrMsgIdAndTxt("Flight:OSQPBounds","Lower bound exceeds upper bound.");
    code=osqp_update_data_mat(&quad_solver,p,OSQP_NULL,45,a,OSQP_NULL,702);
    if(code) mexErrMsgIdAndTxt("Flight:OSQPMatrixUpdate","Matrix update failed: %d.",(int)code);
    code=osqp_update_data_vec(&quad_solver,q,l,u);
    if(code) mexErrMsgIdAndTxt("Flight:OSQPVectorUpdate","Vector update failed: %d.",(int)code);
    code=osqp_solve(&quad_solver);
    plhs[0]=mxCreateDoubleMatrix(15,1,mxREAL);
    plhs[1]=mxCreateDoubleMatrix(190,1,mxREAL);
    plhs[2]=mxCreateDoubleMatrix(6,1,mxREAL);
    for(i=0;i<15;++i) mxGetDoubles(plhs[0])[i]=quad_solver.solution->x[i];
    for(i=0;i<190;++i) mxGetDoubles(plhs[1])[i]=quad_solver.solution->y[i];
    mxGetDoubles(plhs[2])[0]=quad_solver.info->status_val;
    mxGetDoubles(plhs[2])[1]=quad_solver.info->prim_res;
    mxGetDoubles(plhs[2])[2]=quad_solver.info->dual_res;
    mxGetDoubles(plhs[2])[3]=quad_solver.info->iter;
    mxGetDoubles(plhs[2])[4]=quad_solver.info->obj_val;
    mxGetDoubles(plhs[2])[5]=code;
}
