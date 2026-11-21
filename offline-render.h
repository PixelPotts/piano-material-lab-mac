/* Offline render/tests use the same engine as live playback. */
static int write_wave(const char *filename,const Settings *s,int seconds,int scenario) {
 Engine *e=(Engine*)calloc(1,sizeof(Engine)); FILE *f; short pcm[BLOCK];
 unsigned int size=RATE*seconds*2,riff=size+36,fmt=16,rate=RATE,bytes=RATE*2;
 unsigned short format=1,channels=1,align=2,bits=16; int n,count,ok=1;
 if(!e)return 0;init_engine(e,s);f=fopen(filename,"wb");if(!f){free(e);return 0;}
 fwrite("RIFF",1,4,f);fwrite(&riff,4,1,f);fwrite("WAVEfmt ",1,8,f);fwrite(&fmt,4,1,f);
 fwrite(&format,2,1,f);fwrite(&channels,2,1,f);fwrite(&rate,4,1,f);fwrite(&bytes,4,1,f);
 fwrite(&align,2,1,f);fwrite(&bits,2,1,f);fwrite("data",1,4,f);fwrite(&size,4,1,f);
 for(n=0;n<RATE*seconds;n+=count){
  int held=scenario==1||n<RATE;LONG serial=scenario==3?0:1;
  count=BLOCK;if(n<RATE&&n+count>RATE)count=RATE-n;if(n+count>RATE*seconds)count=RATE*seconds-n;
  if(scenario==2){int boundary=(n/(RATE/8)+1)*(RATE/8);serial=1+n/(RATE/8);held=1;if(n+count>boundary)count=boundary-n;}
  render_engine(e,pcm,count,serial,held,.5);
  if(fwrite(pcm,2,count,f)!=(size_t)count){ok=0;break;}
 }
 if(e->nonfinite)ok=0;if(fclose(f))ok=0;free(e);return ok;
}
static int run_sweep(void) {
 Settings s; Engine *e=(Engine*)calloc(1,sizeof(Engine)); short pcm[BLOCK];
 int parameter,side,n,j; FILE *report=fopen("control-sweep.csv","w");
 if(!e||!report){free(e);if(report)fclose(report);return 1;}
 fprintf(report,"parameter,side,value,fundamental,peak,rms,nonfinite,overloads,signature\n");
 for(parameter=-1;parameter<PARAM_COUNT;++parameter)for(side=0;side<(parameter<0?1:2);++side){
  double peak=0,energy=0;unsigned long long hash=1469598103934665603ULL;
  default_settings(&s);if(parameter>=0)s.p[parameter]=side?parameters[parameter].max:parameters[parameter].min;
  init_engine(e,&s);
  for(n=0;n<RATE*2;n+=BLOCK){
   int count=BLOCK;if(n+count>RATE*2)count=RATE*2-n;
   render_engine(e,pcm,count,1,n<RATE,.5);
   for(j=0;j<count;++j){double a=pcm[j]/32768.0;energy+=a*a;if(fabs(a)>peak)peak=fabs(a);hash^=(unsigned short)pcm[j];hash*=1099511628211ULL;}
  }
  fprintf(report,"%s,%d,%.12g,%.8f,%.8f,%.8f,%lu,%lu,%llu\n",parameter<0?"default":parameters[parameter].id,side,parameter<0?0:s.p[parameter],e->active.model.fundamental,peak,sqrt(energy/(RATE*2)),e->nonfinite,e->overloads,hash);
 }
 fclose(report);
 /* Exercise coefficient transitions while the actual model is sounding. */
 default_settings(&s);init_engine(e,&s);
 for(parameter=0;parameter<PARAM_COUNT;++parameter){
  s.p[parameter]=parameters[parameter].max;change_engine(e,&s);
  for(n=0;n<4096;n+=BLOCK)render_engine(e,pcm,BLOCK,1,1,.5);
  default_settings(&s);change_engine(e,&s);
  for(n=0;n<4096;n+=BLOCK)render_engine(e,pcm,BLOCK,1,1,.5);
 }
 report=fopen("transition-test.txt","w");if(report){fprintf(report,"nonfinite=%lu\noverloads=%lu\n",e->nonfinite,e->overloads);fclose(report);}
 j=e->nonfinite?1:0;free(e);return j;
}
