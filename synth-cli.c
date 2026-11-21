#include "platform.h"
#define BLOCK 512
#include "parameters.h"
#include "synth.h"
#include "offline-render.h"
int main(int argc,char **argv){
 Settings s; default_settings(&s);
 if(argc==2&&!strcmp(argv[1],"--sweep"))return run_sweep();
 if(argc==2&&!strcmp(argv[1],"--test")){
  const char *names[]={"test-note.wav","test-held.wav","test-repeat.wav","test-silence.wav"};
  for(int i=0;i<4;++i)if(!write_wave(names[i],&s,8,i))return 1;
  return 0;
 }
 fprintf(stderr,"Usage: synth-cli --test | --sweep\n");return 2;
}
