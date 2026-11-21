#define WIN32_LEAN_AND_MEAN
#include "platform.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#define PI 3.14159265358979323846
#define RATE 44100
#include "parameters.h"
#include "synth.h"
static Engine a,b,c;
static short reference[8192],chunked[8192],pcm[512];
static unsigned int randomState=0x174203;
static double uniform(void){randomState=1664525*randomState+1013904223;return (randomState>>8)/16777216.0;}
int main(void){
 Settings s,copy,invalid;int i,k,n,fail=0;FILE *f=fopen("engine-validation.txt","w");unsigned long maxLimited=0;
 if(!f)return 1;
 default_settings(&s);init_engine(&a,&s);
 fprintf(f,"default_frequency=%.9f\ndefault_tension=%.9f\n",a.active.model.fundamental,s.p[P_STENSION]);
 if(fabs(a.active.model.fundamental-261.625565)>1e-6)++fail;
 b=a;
 for(i=0;i<8192;++i)render_engine(&a,&reference[i],1,1,1,.5);
 for(i=0;i<8192;i+=512)render_engine(&b,&chunked[i],512,1,1,.5);
 if(memcmp(reference,chunked,sizeof(reference)))++fail;
 fprintf(f,"block_partition_invariance=%s\n",memcmp(reference,chunked,sizeof(reference))?"FAIL":"PASS");
 for(i=0;i<PARAM_COUNT;++i){
  default_settings(&s);s.p[i]=parameters[i].max;
  b=a;c=a;change_engine(&b,&s);
  render_engine(&b,pcm,1,1,1,.5);render_engine(&c,chunked,1,1,1,.5);
  if(pcm[0]!=chunked[0])++fail;
 }
 fprintf(f,"crossfade_first_sample_checks=42\n");
 for(k=0;k<80;++k){
  default_settings(&s);
  for(i=0;i<PARAM_COUNT;++i)s.p[i]=denormalized(i,k==0?0:(k==1?1:uniform()));
  init_engine(&a,&s);
  for(n=0;n<RATE;n+=512)render_engine(&a,pcm,512,1,n<RATE/2,.5);
  if(a.nonfinite)++fail;if(a.overloads>maxLimited)maxLimited=a.overloads;
 }
 fprintf(f,"combined_settings_stress_cases=80\nmaximum_safety_limited_samples=%lu\n",maxLimited);
 default_settings(&s);if(!write_settings("validation-roundtrip.piano",&s))++fail;
 memset(&copy,0,sizeof(copy));if(!read_settings("validation-roundtrip.piano",&copy)||memcmp(&s,&copy,sizeof(s)))++fail;
 {FILE *windows=fopen("validation-windows.piano","wb");
  if(!windows)++fail;else {fprintf(windows,"PIANO_MATERIAL_LAB_1\r\n");for(i=0;i<PARAM_COUNT;++i)fprintf(windows,"%s %.17g\r\n",parameters[i].id,s.p[i]);fclose(windows);
   if(!read_settings("validation-windows.piano",&copy)||memcmp(&s,&copy,sizeof(s)))++fail;}}
 DeleteFileA("validation-windows.piano");
 fprintf(f,"windows_crlf_preset_compatibility=checked\n");
 invalid=copy;{FILE *bad=fopen("validation-invalid.piano","w");if(bad){fprintf(bad,"PIANO_MATERIAL_LAB_1\nhammer_mass nan\n");fclose(bad);}}
 if(read_settings("validation-invalid.piano",&copy)||memcmp(&copy,&invalid,sizeof(copy)))++fail;
 DeleteFileA("validation-roundtrip.piano");DeleteFileA("validation-invalid.piano");
 fprintf(f,"preset_roundtrip_and_invalid_input=checked\nfailures=%d\n",fail);
 fclose(f);return fail?1:0;
}
