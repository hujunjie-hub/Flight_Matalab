#define S_FUNCTION_NAME fmt_rigid_sfun
#define S_FUNCTION_LEVEL 2
#include "simstruc.h"
#include "fmt_rotation.h"
static void mdlInitializeSizes(SimStruct *S) {
    int i;ssSetNumSFcnParams(S,1);if(ssGetNumSFcnParams(S)!=ssGetSFcnParamsCount(S))return;
    if(!ssSetNumInputPorts(S,4))return;
    ssSetInputPortWidth(S,0,17);ssSetInputPortWidth(S,1,6);ssSetInputPortWidth(S,2,6);ssSetInputPortWidth(S,3,15);
    for(i=0;i<4;++i){ssSetInputPortDirectFeedThrough(S,i,1);ssSetInputPortRequiredContiguous(S,i,1);}
    if(!ssSetNumOutputPorts(S,1))return;ssSetOutputPortWidth(S,0,13);
    ssSetNumSampleTimes(S,1);ssSetOptions(S,SS_OPTION_EXCEPTION_FREE_CODE);
}
static void mdlInitializeSampleTimes(SimStruct *S){ssSetSampleTime(S,0,INHERITED_SAMPLE_TIME);ssSetOffsetTime(S,0,0);ssSetModelReferenceSampleTimeDefaultInheritance(S);}
#define MDL_SET_WORK_WIDTHS
static void mdlSetWorkWidths(SimStruct *S){ssSupportsMultipleExecInstances(S,true);}
static void mdlOutputs(SimStruct *S,int_T tid) {
    const double *x=ssGetInputPortRealSignal(S,0),*rotor=ssGetInputPortRealSignal(S,1),*ground=ssGetInputPortRealSignal(S,2),*env=ssGetInputPortRealSignal(S,3),*p=mxGetPr(ssGetSFcnParam(S,0));
    double *dx=ssGetOutputPortRealSignal(S,0),r[9],jw[3],gyroscopic[3];int i,j;
    double w=x[6],qx=x[7],qy=x[8],qz=x[9],wx=x[10],wy=x[11],wz=x[12];
    (void)tid;
    if(mxGetNumberOfElements(ssGetSFcnParam(S,0))<17){ssSetErrorStatus(S,"PlantParameters must contain at least 17 values.");return;}
    if(!fmt_rotation(x+6,r)){ssSetErrorStatus(S,"Invalid Plant quaternion.");return;}
    for(i=0;i<3;++i){
        double fn=env[3+i];
        for(j=0;j<3;++j) fn+=r[3*i+j]*(rotor[j]+ground[j]);
        if(env[10]>0.5)fn-=p[6+i]*(x[3+i]-env[i]);
        dx[i]=x[3+i];dx[3+i]=fn/p[0]+(i==2?p[16]:0);
        jw[i]=p[1+i]*x[10+i];
    }
    dx[6]=-.5*(qx*wx+qy*wy+qz*wz);
    dx[7]= .5*(w*wx+qy*wz-qz*wy);
    dx[8]= .5*(w*wy+qz*wx-qx*wz);
    dx[9]= .5*(w*wz+qx*wy-qy*wx);
    fmt_cross(x+10,jw,gyroscopic);
    for(i=0;i<3;++i)dx[10+i]=(rotor[3+i]+ground[3+i]+env[6+i]-p[9]*x[10+i]-gyroscopic[i])/p[1+i];
}
static void mdlTerminate(SimStruct *S){(void)S;}
#ifdef MATLAB_MEX_FILE
#include "simulink.c"
#else
#include "cg_sfun.h"
#endif

