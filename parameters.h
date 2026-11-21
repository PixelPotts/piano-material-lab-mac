/* SI calculations use explicit conversions from the units shown on the knobs. */
#include "platform.h"
#define PARAM_COUNT 42
enum { P_HMASS,P_HVEL,P_HFELT,P_HEXP,P_HPOS,P_HWIDTH, P_SLEN,P_STENSION,P_SDIAM,P_SRHO,P_SE,P_SLOSS,
 P_DETL,P_DETR,P_BMASS,P_BK,P_BC,P_BWIDTH, P_PLEN,P_PWIDTH,P_PTHICK,P_PRHO,P_PE,P_PRATIO,
 P_PLOSS,P_CMASS,P_CK,P_CLOSS,P_CVOL,P_APERTURE, P_DAMP,P_DPOS,P_DWIDTH,P_DTIME,P_PEDAL,P_DCOMP,
 P_RLEN,P_RWID,P_RHEIGHT,P_ABSORB,P_DIST,P_ANGLE };
typedef struct { const char *id,*name,*unit,*help; double min,max,initial; int logarithmic; } Parameter;
typedef struct { double p[PARAM_COUNT]; } Settings;
static const Parameter parameters[PARAM_COUNT]={
 {"hammer_mass","Hammer mass","g","Moving hammer mass. More mass stores more impact energy at the same velocity.",2,15,6,1},
 {"hammer_speed","Strike speed","m/s","Hammer velocity just before contact. Changes kinetic energy and the nonlinear felt contact force.",.2,3,1.2,1},
 {"felt_force","Felt firmness","N @ 1 mm","Felt force at 1 mm compression. This is a physical contact-spring parameter, not a brightness filter.",20,1000,140,1},
 {"felt_exponent","Felt exponent","power","Nonlinear contact law: F = F1mm * (compression / 1 mm)^exponent. Felt stiffens as it compresses.",1.6,3.5,2.5,0},
 {"strike_position","Strike point","% length","Hammer position along the speaking string. Modes with a node at this point are weakly excited.",5,30,11.7,0},
 {"hammer_width","Contact width","mm","Finite hammer contact width. The excitation is averaged across this strip of the string.",2,20,8,0},
 {"string_length","Speaking length","m","Distance between string supports. Changes modal frequencies and the distributed string mass.",.45,.9,.65,0},
 {"string_tension","Tension","N","Axial string tension. Tighter strings raise pitch; use TUNE C4 to solve tension for the current material and dimensions.",120,1500,600,1},
 {"wire_diameter","Wire diameter","mm","Solid round wire diameter. Changes linear density AND bending rigidity (which scales with diameter to the fourth power).",.65,1.3,.9,0},
 {"wire_density","Metal density","kg/m3","Wire material density. More mass per length lowers pitch at a fixed tension.",7000,9000,7850,0},
 {"wire_modulus","Elastic modulus","GPa","Young's modulus of the wire. Controls bending stiffness and the stretching of the higher partials.",100,240,200,0},
 {"string_loss","String damping","1/s","Intrinsic modal amplitude-loss rate at the fundamental; higher modes lose energy faster in this reduced model.",.03,2,.12,1},
 {"left_unison","Left unison","cents","Small change to the left string's tension, expressed as its fundamental pitch difference from the center string.",-5,5,-.65,0},
 {"right_unison","Right unison","cents","Small change to the right string's tension. Interference between the three real modal string banks produces beating.",-5,5,.8,0},
 {"bridge_mass","Bridge mass","g","Effective moving bridge mass in a mass-spring-damper transfer model. Shifts bridge resonance and inertial loading.",20,250,70,1},
 {"bridge_stiffness","Bridge stiffness","MN/m","Bridge support spring stiffness. Combined with bridge mass it determines bridge resonance.",.1,8,1.5,1},
 {"bridge_damping","Bridge loss","N s/m","Viscous loss in the bridge support. Broadens and reduces its resonance.",1,100,24,1},
 {"bridge_width","Bridge footprint","mm","Width of the force distribution on the soundboard. Changes how strongly each plate mode is driven.",5,100,30,0},
 {"board_length","Board length","m","Length of the rectangular orthotropic plate approximation. Changes its flexural modal frequencies.",.8,1.8,1.3,0},
 {"board_width","Board width","m","Width of the soundboard plate. Cross-grain stiffness is accounted for separately.",.55,1.3,.95,0},
 {"board_thickness","Board thickness","mm","Thickness changes plate mass and bending rigidity. Bending rigidity scales as thickness cubed.",5,14,8,0},
 {"wood_density","Wood density","kg/m3","Soundboard wood density. Changes modal masses and flexural frequencies.",300,650,450,0},
 {"wood_modulus","Along-grain E","GPa","Longitudinal Young's modulus of the board wood. The plate is a reduced model without individually modeled ribs.",5,18,11,0},
 {"grain_ratio","Cross-grain E","ratio","Cross-grain / along-grain elastic-modulus ratio. Changes the directional bending response.",.025,.2,.07,1},
 {"board_loss","Board loss","loss factor","Soundboard structural loss factor. Larger values produce broader resonances and shorter board ringing.",.008,.12,.035,1},
 {"case_mass","Case panel mass","kg","Effective casing-panel mass, represented by one damped structural mode.",1,15,5,1},
 {"case_stiffness","Case stiffness","MN/m","Effective casing-panel spring stiffness. Sets case resonance together with panel mass.",.1,8,1.2,1},
 {"case_loss","Case loss","loss factor","Structural energy loss in the casing panel. Controls how long its resonance rings.",.015,.3,.09,1},
 {"cavity_volume","Air cavity","m3","Internal case air volume in a lumped Helmholtz-resonator approximation, not a full grand-piano enclosure simulation.",.08,.9,.35,1},
 {"cavity_opening","Lid aperture","cm2","Effective open area of the case. Sets acoustic cavity resonance and radiation damping; not literal lid angle.",100,4000,1500,1},
 {"damper_loss","Damper friction","N s/m","Effective viscous damping at the felt contact. Applied to each mode according to local string motion.",.05,8,.7,1},
 {"damper_position","Damper point","% length","Where the damper contacts the string. A mode near a node at this point is damped less strongly.",22,78,38,0},
 {"damper_width","Damper width","mm","Finite damper contact footprint. Uses the mean squared mode shape over the contact region.",10,70,35,0},
 {"damper_time","Lowering time","ms","Time scale for the damper to return after key release. Smoothly changes contact instead of chopping the waveform.",5,120,25,1},
 {"pedal_lift","Pedal lift","%","Lifts the damper away from the string. 100% keeps the strings ringing after you release the key.",0,100,0,0},
 {"damper_compression","Felt compression","mm","Damper preload/compression. Scales effective contact damping using an explicitly approximate square-root contact law.",.1,1.5,.5,1},
 {"room_length","Room length","m","Shoebox room length. Sets the front/back image-source reflection distances and room volume.",4,14,6,0},
 {"room_width","Room width","m","Shoebox room width. Sets side-wall reflection distances and room volume.",3,10,4.5,0},
 {"room_height","Room height","m","Room height. Source and microphone are both at 1.2 m; floor and ceiling reflection paths are calculated.",2.4,6,3,0},
 {"wall_absorption","Wall absorption","fraction","Average wall energy absorption. Controls reflection amplitudes and the diffuse decay estimate.",.05,.85,.32,0},
 {"mic_distance","Mic distance","m","Distance from the virtual radiator: propagation delay and geometric spreading change together.",.2,1.8,1,0},
 {"mic_angle","Mic polar angle","deg","Observation angle from the board normal. Uses an approximate finite-radiator directivity response.",0,80,20,0}
};
static const char *groupNames[7]={"01  HAMMER & FELT","02  STRINGS & MATERIAL","03  UNISON & BRIDGE","04  SOUNDBOARD WOOD","05  CASING & RESONANCE","06  DAMPER & PEDAL","07  ROOM & MICROPHONE"};
static double bounded(double x,double lo,double hi) { return x<lo?lo:(x>hi?hi:x); }
static double string_tension_c4(const Settings *s) {
 double L=s->p[P_SLEN],d=s->p[P_SDIAM]*.001,A=PI*d*d/4,I=PI*d*d*d*d/64;
 return s->p[P_SRHO]*A*pow(2*L*261.625565,2)-s->p[P_SE]*1e9*I*PI*PI/(L*L);
}
static void default_settings(Settings *s) { int i; for(i=0;i<PARAM_COUNT;++i)s->p[i]=parameters[i].initial; s->p[P_STENSION]=string_tension_c4(s); }
static double normalized(int i,double value) { const Parameter *p=&parameters[i]; return p->logarithmic?log(value/p->min)/log(p->max/p->min):(value-p->min)/(p->max-p->min); }
static double denormalized(int i,double value) { const Parameter *p=&parameters[i]; value=bounded(value,0,1); return p->logarithmic?p->min*pow(p->max/p->min,value):p->min+(p->max-p->min)*value; }
static int write_settings(const char *path,const Settings *s) {
 char temp[MAX_PATH]; FILE *f; int i,ok;
 snprintf(temp,sizeof(temp),"%s.tmp",path); f=fopen(temp,"w"); if(!f)return 0;
 fprintf(f,"PIANO_MATERIAL_LAB_1\n"); for(i=0;i<PARAM_COUNT;++i)fprintf(f,"%s %.17g\n",parameters[i].id,s->p[i]);
 ok=fclose(f)==0; if(!ok)return 0;
#ifdef _WIN32
 return MoveFileExA(temp,path,MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH)!=0;
#else
 return rename(temp,path)==0;
#endif
}
static int read_settings(const char *path,Settings *s) {
 FILE *f=fopen(path,"r"); Settings candidate; char line[128],id[80],extra; double value; int i;
 if(!f)return 0;
 if(!fgets(line,sizeof(line),f)){fclose(f);return 0;}
 line[strcspn(line,"\r\n")]=0;
 if(strcmp(line,"PIANO_MATERIAL_LAB_1")){fclose(f);return 0;}
 for(i=0;i<PARAM_COUNT;++i) {
  if(!fgets(line,sizeof(line),f)||sscanf(line,"%79s %lf %c",id,&value,&extra)!=2||strcmp(id,parameters[i].id)||
     !(value>=parameters[i].min&&value<=parameters[i].max)){fclose(f);return 0;}
  candidate.p[i]=value;
 }
 fclose(f); *s=candidate; return 1;
}
