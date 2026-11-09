#define S_FUNCTION_NAME fmt_ground_sfun
#define S_FUNCTION_LEVEL 2
#include "simstruc.h"
#include "fmt_rotation.h"
static void mdlInitializeSizes(SimStruct *S) {
    ssSetNumSFcnParams(S,1);if(ssGetNumSFcnParams(S)!=ssGetSFcnParamsCount(S))return;
    if(!ssSetNumInputPorts(S,2))return;
    ssSetInputPortWidth(S,0,17);ssSetInputPortWidth(S,1,15);
    ssSetInputPortDirectFeedThrough(S,0,1);ssSetInputPortDirectFeedThrough(S,1,1);
    ssSetInputPortRequiredContiguous(S,0,1);ssSetInputPortRequiredContiguous(S,1,1);
    if(!ssSetNumOutputPorts(S,3))return;
    ssSetOutputPortWidth(S,0,6);ssSetOutputPortWidth(S,1,1);ssSetOutputPortWidth(S,2,1);
    ssSetNumSampleTimes(S,1);ssSetOptions(S,SS_OPTION_EXCEPTION_FREE_CODE);
}
static void mdlInitializeSampleTimes(SimStruct *S){ssSetSampleTime(S,0,INHERITED_SAMPLE_TIME);ssSetOffsetTime(S,0,0);ssSetModelReferenceSampleTimeDefaultInheritance(S);}
#define MDL_SET_WORK_WIDTHS
static void mdlSetWorkWidths(SimStruct *S){ssSupportsMultipleExecInstances(S,true);}
static void mdlOutputs(SimStruct *S,int_T tid) {
    const double *x=ssGetInputPortRealSignal(S,0),*env=ssGetInputPortRealSignal(S,1),*p=mxGetPr(ssGetSFcnParam(S,0));
    double *wr=ssGetOutputPortRealSignal(S,0),*gap=ssGetOutputPortRealSignal(S,1),*normal=ssGetOutputPortRealSignal(S,2);
    double r[9];
    (void)tid;
    if(mxGetNumberOfElements(ssGetSFcnParam(S,0))<20){ssSetErrorStatus(S,"PlantParameters must include skid dimensions and friction.");return;}
    if(!fmt_rotation(x+6,r)){ssSetErrorStatus(S,"Invalid Plant quaternion.");return;}
    for(int i=0;i<6;++i) wr[i]=0;
    *gap=INFINITY;
    *normal=0;
    for(int corner=0;corner<4;++corner) {
        const double lever[3]={p[13]+((corner&1)?p[17]:-p[17]),
                               p[14]+((corner&2)?p[18]:-p[18]),p[15]};
        double velocity_body[3], velocity_ned[3], fbody[3], torque[3];
        double down=x[2];
        fmt_cross(x+10,lever,velocity_body);
        for(int i=0;i<3;++i) down+=r[6+i]*lever[i];
        const double clearance=p[12]-down;
        *gap=fmin(*gap,clearance);
        if(env[9]<=0.5 || clearance>0) continue;
        for(int i=0;i<3;++i) {
            velocity_ned[i]=x[3+i];
            for(int j=0;j<3;++j) velocity_ned[i]+=r[3*i+j]*velocity_body[j];
        }
        const double fn=0.25*fmax(0,-p[10]*clearance+p[11]*velocity_ned[2]);
        /* Regularized Coulomb friction avoids a sign change at zero slip. */
        const double slip=hypot(velocity_ned[0],velocity_ned[1]);
        const double friction=-p[19]*fn/fmax(slip,0.05);
        const double force_ned[3]={friction*velocity_ned[0],friction*velocity_ned[1],-fn};
        for(int i=0;i<3;++i)
            fbody[i]=r[i]*force_ned[0]+r[3+i]*force_ned[1]+r[6+i]*force_ned[2];
        fmt_cross(lever,fbody,torque);
        for(int i=0;i<3;++i){wr[i]+=fbody[i];wr[3+i]+=torque[i];}
        *normal+=fn;
    }
}
static void mdlTerminate(SimStruct *S){(void)S;}
#ifdef MATLAB_MEX_FILE
#include "simulink.c"
#else
#include "cg_sfun.h"
#endif

