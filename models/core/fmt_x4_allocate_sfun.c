#define S_FUNCTION_NAME fmt_x4_allocate_sfun
#define S_FUNCTION_LEVEL 2
#include "simstruc.h"
#include <math.h>
static void mdlInitializeSizes(SimStruct *S){int i;ssSetNumSFcnParams(S,1);if(ssGetNumSFcnParams(S)!=ssGetSFcnParamsCount(S))return;
 if(!ssSetNumInputPorts(S,2))return;ssSetInputPortWidth(S,0,4);ssSetInputPortWidth(S,1,8);
 for(i=0;i<2;++i){ssSetInputPortDirectFeedThrough(S,i,1);ssSetInputPortRequiredContiguous(S,i,1);}
 if(!ssSetNumOutputPorts(S,5))return;ssSetOutputPortWidth(S,0,4);ssSetOutputPortWidth(S,1,4);ssSetOutputPortWidth(S,2,3);ssSetOutputPortWidth(S,3,1);ssSetOutputPortWidth(S,4,1);ssSetOutputPortDataType(S,4,SS_BOOLEAN);
 ssSetNumSampleTimes(S,1);ssSetOptions(S,SS_OPTION_EXCEPTION_FREE_CODE);}
static void mdlInitializeSampleTimes(SimStruct *S){ssSetSampleTime(S,0,INHERITED_SAMPLE_TIME);ssSetOffsetTime(S,0,0);ssSetModelReferenceSampleTimeDefaultInheritance(S);}
#define MDL_SET_WORK_WIDTHS
static void mdlSetWorkWidths(SimStruct *S){ssSupportsMultipleExecInstances(S,true);}
static double clamp(double v,double l,double u){return fmax(l,fmin(v,u));}
static void mdlOutputs(SimStruct *S,int_T tid){
 const double *request=ssGetInputPortRealSignal(S,0),*bounds=ssGetInputPortRealSignal(S,1),*geometry=mxGetPr(ssGetSFcnParam(S,0));
 double *f=ssGetOutputPortRealSignal(S,0),*achieved=ssGetOutputPortRealSignal(S,1),*residual=ssGetOutputPortRealSignal(S,2),*scale=ssGetOutputPortRealSignal(S,3);
 boolean_T *valid=(boolean_T*)ssGetOutputPortSignal(S,4);double rp[4],a,gamma,slo=0,shi=1,la,ua,lb,ub,total,csum,ca,cb;int i,j,group;(void)tid;
 *valid=false;*scale=0;for(i=0;i<4;++i){f[i]=0;achieved[i]=0;}for(i=0;i<3;++i)residual[i]=0;
 if(mxGetNumberOfElements(ssGetSFcnParam(S,0))!=2)return;a=geometry[0]/sqrt(2.0);gamma=geometry[1];if(!(a>0)||!(gamma>0))return;
 for(i=0;i<4;++i)if(!isfinite(request[i])||!isfinite(bounds[i])||!isfinite(bounds[4+i])||bounds[i]>bounds[4+i])return;
 rp[0]=(request[1]+request[2])/(4*a);rp[1]=(-request[1]+request[2])/(4*a);rp[2]=-rp[0];rp[3]=-rp[1];
 /* Maximum feasible common roll/pitch scale; each yaw pair shares a collective. */
 for(group=0;group<2;++group)for(i=group;i<4;i+=2)for(j=group;j<4;j+=2){
    double d=rp[j]-rp[i],b=bounds[4+j]-bounds[i];
    if(d>1e-15)shi=fmin(shi,b/d);else if(d< -1e-15)slo=fmax(slo,b/d);else if(b<0)return;
 }
 if(shi<slo || shi<0 || slo>1)return;*scale=clamp(shi,0,1);for(i=0;i<4;++i)rp[i]*=*scale;
 la=fmax(bounds[0]-rp[0],bounds[2]-rp[2]);ua=fmin(bounds[4]-rp[0],bounds[6]-rp[2]);
 lb=fmax(bounds[1]-rp[1],bounds[3]-rp[3]);ub=fmin(bounds[5]-rp[1],bounds[7]-rp[3]);
 total=clamp(request[0],2*(la+lb),2*(ua+ub));csum=total/2;
 ca=clamp((request[3]+2*gamma*csum)/(4*gamma),fmax(la,csum-ub),fmin(ua,csum-lb));cb=csum-ca;
 f[0]=ca+rp[0];f[2]=ca+rp[2];f[1]=cb+rp[1];f[3]=cb+rp[3];
 achieved[0]=f[0]+f[1]+f[2]+f[3];achieved[1]=a*(f[0]-f[1]-f[2]+f[3]);
 achieved[2]=a*(f[0]+f[1]-f[2]-f[3]);achieved[3]=gamma*(f[0]-f[1]+f[2]-f[3]);
 for(i=0;i<3;++i)residual[i]=achieved[1+i]-request[1+i];
 for(i=0;i<4;++i)if(!isfinite(f[i])||f[i]<bounds[i]-1e-9||f[i]>bounds[4+i]+1e-9)return;
 *valid=true;
}
static void mdlTerminate(SimStruct *S){(void)S;}
#ifdef MATLAB_MEX_FILE
#include "simulink.c"
#else
#include "cg_sfun.h"
#endif
