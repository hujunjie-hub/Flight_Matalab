#define S_FUNCTION_NAME fmt_frame_encode_sfun
#define S_FUNCTION_LEVEL 2
#include "simstruc.h"
#include <math.h>
#include <stdint.h>
static void mdlInitializeSizes(SimStruct *S){int i;ssSetNumSFcnParams(S,1);if(ssGetNumSFcnParams(S)!=ssGetSFcnParamsCount(S))return;
 if(!ssSetNumInputPorts(S,3))return;ssSetInputPortWidth(S,0,4);ssSetInputPortWidth(S,1,4);ssSetInputPortWidth(S,2,1);
 for(i=0;i<3;++i){ssSetInputPortDirectFeedThrough(S,i,1);ssSetInputPortRequiredContiguous(S,i,1);}
 if(!ssSetNumOutputPorts(S,4))return;for(i=0;i<3;++i)ssSetOutputPortWidth(S,i,4);ssSetOutputPortWidth(S,3,1);
 ssSetOutputPortDataType(S,0,SS_UINT16);ssSetOutputPortDataType(S,1,SS_UINT16);ssSetOutputPortDataType(S,3,SS_BOOLEAN);
 ssSetNumSampleTimes(S,1);ssSetOptions(S,SS_OPTION_EXCEPTION_FREE_CODE);}
static void mdlInitializeSampleTimes(SimStruct *S){ssSetSampleTime(S,0,INHERITED_SAMPLE_TIME);ssSetOffsetTime(S,0,0);ssSetModelReferenceSampleTimeDefaultInheritance(S);}
#define MDL_SET_WORK_WIDTHS
static void mdlSetWorkWidths(SimStruct *S){ssSupportsMultipleExecInstances(S,true);}
static void mdlOutputs(SimStruct *S,int_T tid){
 const double *demand=ssGetInputPortRealSignal(S,0),*previous=ssGetInputPortRealSignal(S,1),dt=*ssGetInputPortRealSignal(S,2),*p=mxGetPr(ssGetSFcnParam(S,0));
 uint16_T *codes=(uint16_T*)ssGetOutputPortSignal(S,0),*packets=(uint16_T*)ssGetOutputPortSignal(S,1);double *force=ssGetOutputPortRealSignal(S,2);boolean_T *valid=(boolean_T*)ssGetOutputPortSignal(S,3);
 uint16_t candidate[4];double restored[4];int i;(void)tid;
 *valid=false;for(i=0;i<4;++i){codes[i]=0;packets[i]=0;force[i]=0;}
 if(mxGetNumberOfElements(ssGetSFcnParam(S,0))!=2 || !isfinite(dt)||!(dt>0)||!(p[0]>0)||!(p[1]>0)||p[1]*dt+1e-12<p[0]/1999)return;
 for(i=0;i<4;++i){double lo,hi,realcode;int lcode,hcode,code;
   if(!isfinite(demand[i])||!isfinite(previous[i])||demand[i]<0||demand[i]>p[0]||previous[i]<0||previous[i]>p[0])return;
   lo=fmax(0,previous[i]-p[1]*dt);hi=fmin(p[0],previous[i]+p[1]*dt);
   if(demand[i]==0 && lo==0){candidate[i]=0;restored[i]=0;continue;}
   lcode=(int)ceil(48+lo*1999/p[0]-1e-10);hcode=(int)floor(48+hi*1999/p[0]+1e-10);
   if(lcode<48)lcode=48;if(hcode>2047)hcode=2047;if(lcode>hcode)return;
   realcode=48+demand[i]*1999/p[0];code=(int)ceil(realcode-0.5); /* exact ties go to lower code */
   if(code<lcode)code=lcode;if(code>hcode)code=hcode;
   candidate[i]=(uint16_t)code;restored[i]=(code-48)*p[0]/1999;
   if(restored[i]<lo-1e-10||restored[i]>hi+1e-10)return;
 }
 for(i=0;i<4;++i){uint16_t payload=(uint16_t)(candidate[i]<<1),checksum=(uint16_t)((payload^(payload>>4)^(payload>>8))&15);
   codes[i]=candidate[i];packets[i]=(uint16_t)((payload<<4)|checksum);force[i]=restored[i];}
 *valid=true;
}
static void mdlTerminate(SimStruct *S){(void)S;}
#ifdef MATLAB_MEX_FILE
#include "simulink.c"
#else
#include "cg_sfun.h"
#endif
