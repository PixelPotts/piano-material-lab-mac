#import <Cocoa/Cocoa.h>
#import <AudioToolbox/AudioToolbox.h>
#include <pthread.h>
#include <stdatomic.h>
#include "../platform.h"
#define BLOCK 512
#define BUFFER_COUNT 6
#include "../parameters.h"
#include "../synth.h"
#include "../offline-render.h"

typedef struct {
 AudioQueueRef queue;
 AudioQueueBufferRef buffers[BUFFER_COUNT];
 Engine engine;
 pthread_mutex_t lock;
 Model pending;
 unsigned version,applied;
 int held,renderHeld;
 LONG serial,renderSerial;
 double volume,renderVolume,peak;
 short scope[BLOCK];
 unsigned long clips,faults,callbacks;
} AudioState;
static AudioState sound={.lock=PTHREAD_MUTEX_INITIALIZER};
static _Atomic bool audioStopping=false;
static _Atomic int audioError=0;
static BOOL testMode;

static void audio_callback(void *unused,AudioQueueRef queue,AudioQueueBufferRef buffer){
 if(atomic_load(&audioStopping))return;
 if(pthread_mutex_trylock(&sound.lock)==0){
  sound.renderHeld=sound.held;sound.renderSerial=sound.serial;sound.renderVolume=sound.volume;
  if(sound.version!=sound.applied&&!sound.engine.transition){
   sound.engine.old=sound.engine.active;sound.engine.active.model=sound.pending;
   sound.engine.transition=2048;sound.applied=sound.version;
  }
  pthread_mutex_unlock(&sound.lock);
 }
 short *pcm=buffer->mAudioData;
 render_engine(&sound.engine,pcm,BLOCK,sound.renderSerial,sound.renderHeld,sound.renderVolume);
 buffer->mAudioDataByteSize=BLOCK*sizeof(short);
 double peak=0;for(int i=0;i<BLOCK;i++)if(fabs(pcm[i]/32768.0)>peak)peak=fabs(pcm[i]/32768.0);
 if(pthread_mutex_trylock(&sound.lock)==0){
  memcpy(sound.scope,pcm,sizeof(sound.scope));sound.peak=peak;
  sound.clips=sound.engine.overloads;sound.faults=sound.engine.nonfinite;++sound.callbacks;
  pthread_mutex_unlock(&sound.lock);
 }
 OSStatus error=AudioQueueEnqueueBuffer(queue,buffer,0,NULL);
 if(error)atomic_store(&audioError,error);
}
static void stop_audio(void){
 atomic_store(&audioStopping,true);
 if(sound.queue){AudioQueueStop(sound.queue,true);AudioQueueDispose(sound.queue,true);sound.queue=NULL;}
}
static OSStatus start_audio(const Settings *settings,double volume){
 stop_audio();atomic_store(&audioStopping,false);atomic_store(&audioError,0);
 init_engine(&sound.engine,settings);
 pthread_mutex_lock(&sound.lock);
 sound.pending=sound.engine.active.model;sound.version=sound.applied=1;
 sound.held=sound.renderHeld=0;sound.serial=sound.renderSerial=0;
 sound.volume=sound.renderVolume=volume;sound.peak=0;sound.clips=sound.faults=sound.callbacks=0;
 memset(sound.scope,0,sizeof(sound.scope));pthread_mutex_unlock(&sound.lock);
 AudioStreamBasicDescription format={0};
 format.mSampleRate=RATE;format.mFormatID=kAudioFormatLinearPCM;
 format.mFormatFlags=kLinearPCMFormatFlagIsSignedInteger|kLinearPCMFormatFlagIsPacked;
 format.mBytesPerPacket=2;format.mFramesPerPacket=1;format.mBytesPerFrame=2;
 format.mChannelsPerFrame=1;format.mBitsPerChannel=16;
 OSStatus error=AudioQueueNewOutput(&format,audio_callback,NULL,NULL,NULL,0,&sound.queue);
 for(int i=0;!error&&i<BUFFER_COUNT;i++){
  error=AudioQueueAllocateBuffer(sound.queue,BLOCK*sizeof(short),&sound.buffers[i]);
  if(!error)audio_callback(NULL,sound.queue,sound.buffers[i]);
  if(atomic_load(&audioError))error=atomic_load(&audioError);
 }
 if(!error)error=AudioQueueStart(sound.queue,NULL);
 if(error){stop_audio();atomic_store(&audioError,error);}return error;
}
static NSColor *rgb(int r,int g,int b){return [NSColor colorWithSRGBRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1];}
static NSColor *accent(int i){static int colors[7][3]={{239,183,140},{154,212,180},{219,198,151},{135,190,225},{200,165,204},{239,183,183},{145,194,198}};return rgb(colors[i][0],colors[i][1],colors[i][2]);}
static void fillRect(NSRect rect,NSColor *color){[color setFill];NSRectFill(rect);}
static void drawLine(NSPoint a,NSPoint b,NSColor *color,CGFloat width){[color setStroke];NSBezierPath *p=[NSBezierPath bezierPath];p.lineWidth=width;[p moveToPoint:a];[p lineToPoint:b];[p stroke];}
static void text(NSString *s,NSRect r,CGFloat size,NSColor *color,BOOL centered,BOOL mono){
 NSMutableParagraphStyle *style=[NSMutableParagraphStyle new];style.alignment=centered?NSTextAlignmentCenter:NSTextAlignmentLeft;style.lineBreakMode=NSLineBreakByTruncatingTail;
 NSFont *font=mono?[NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular]:[NSFont systemFontOfSize:size weight:NSFontWeightRegular];
 [s drawInRect:r withAttributes:@{NSFontAttributeName:font,NSForegroundColorAttributeName:color,NSParagraphStyleAttributeName:style}];
}
static NSPoint knobPoint(int index){int group=index/6;return NSMakePoint(24+(group%4)*352+56+(index%3)*112,94+(group/4)*320+96+((index%6)/3)*130);}
static int knobAt(NSPoint p){for(int i=0;i<PARAM_COUNT;i++){NSPoint c=knobPoint(i);if(NSPointInRect(p,NSMakeRect(c.x-50,c.y-34,100,113)))return i;}return -1;}
static NSRect buttonRect(int i){static CGFloat x[]={654,774,894,1014,1134,1282},w[]={108,108,108,108,136,134};return NSMakeRect(x[i],28,w[i],38);}
static NSString *parameterValue(int i,double value){double span=parameters[i].max-parameters[i].min;if(i==P_STENSION)return [NSString stringWithFormat:@"%.2f",value];if(span>=1000)return [NSString stringWithFormat:@"%.0f",value];if(span>=100)return [NSString stringWithFormat:@"%.1f",value];if(span>=10)return [NSString stringWithFormat:@"%.2f",value];if(span>=1)return [NSString stringWithFormat:@"%.3f",value];return [NSString stringWithFormat:@"%.4f",value];}

@interface PianoView:NSView<NSTextFieldDelegate>{
 @public Settings settings;Model display;double volume;
 int selected,dragging,editing;CGFloat dragY;double dragValue;
 BOOL mouseHeld,spaceHeld,cHeld,autoStrike,autoHeld;
 CFAbsoluteTime autoStart;
 NSTextField *editor;NSString *support,*info;NSTimer *timer;
}
- (instancetype)initWithFrame:(NSRect)frame support:(NSString*)folder;
- (void)publish;
- (void)setParameter:(int)index value:(double)value;
- (void)syncGate;
- (void)releaseKeys;
- (void)saveCurrent;
- (void)button:(int)index;
- (BOOL)selfTest;
@end
@implementation PianoView
- (instancetype)initWithFrame:(NSRect)frame support:(NSString*)folder{
 self=[super initWithFrame:frame];if(self){support=folder;selected=dragging=editing=-1;volume=.5;
 default_settings(&settings);if(!testMode)read_settings([[support stringByAppendingPathComponent:@"current-settings.piano"] fileSystemRepresentation],&settings);
 build_model(&display,&settings);info=@"Drag a knob. Shift = fine. Double-click for exact entry. Right-click resets one control.";
 self.accessibilityLabel=@"Piano Material Lab, 42 physical controls";
 timer=[NSTimer scheduledTimerWithTimeInterval:1.0/30 target:self selector:@selector(tick:) userInfo:nil repeats:YES];}
 return self;
}
- (BOOL)isFlipped{return YES;}
- (BOOL)acceptsFirstResponder{return YES;}
- (CGFloat)canvasScale{return fmin(self.bounds.size.width/1440.0,self.bounds.size.height/960.0);}
- (NSPoint)pointForEvent:(NSEvent*)event{NSPoint p=[self convertPoint:event.locationInWindow fromView:nil];CGFloat s=[self canvasScale];return NSMakePoint(p.x/s,p.y/s);}
- (void)updateTrackingAreas{for(NSTrackingArea *area in [self.trackingAreas copy])[self removeTrackingArea:area];[self addTrackingArea:[[NSTrackingArea alloc]initWithRect:NSZeroRect options:NSTrackingMouseMoved|NSTrackingActiveInKeyWindow|NSTrackingInVisibleRect owner:self userInfo:nil]];[super updateTrackingAreas];}
- (void)publish{build_model(&display,&settings);pthread_mutex_lock(&sound.lock);sound.pending=display;++sound.version;pthread_mutex_unlock(&sound.lock);[self setNeedsDisplay:YES];}
- (void)setParameter:(int)index value:(double)value{if(index<0||index>=PARAM_COUNT||!isfinite(value))return;settings.p[index]=bounded(value,parameters[index].min,parameters[index].max);selected=index;[self publish];}
- (void)syncGate{int held=mouseHeld||spaceHeld||cHeld||autoHeld;pthread_mutex_lock(&sound.lock);if(held&&!sound.held)++sound.serial;sound.held=held;pthread_mutex_unlock(&sound.lock);[self setNeedsDisplay:YES];}
- (void)releaseKeys{mouseHeld=spaceHeld=cHeld=NO;dragging=-1;[self syncGate];}
- (void)saveCurrent{if(editor)[self commitEditor:nil];if(!write_settings([[support stringByAppendingPathComponent:@"current-settings.piano"]fileSystemRepresentation],&settings))info=@"Could not save current settings.";}
- (void)tick:(NSTimer*)unused{if(autoStrike){BOOL down=fmod(CFAbsoluteTimeGetCurrent()-autoStart,2.5)<1;if(down!=autoHeld){autoHeld=down;[self syncGate];}}[self setNeedsDisplay:YES];}
- (void)drawRect:(NSRect)dirty{
 fillRect(self.bounds,rgb(12,15,20));[NSGraphicsContext saveGraphicsState];NSAffineTransform *transform=[NSAffineTransform transform];[transform scaleBy:[self canvasScale]];[transform concat];
 text(@"PIANO / MATERIAL LAB",NSMakeRect(24,24,620,38),28,rgb(237,239,243),NO,NO);
 text(@"42 PHYSICAL CONTROLS   /   NATIVE MAC EDITION",NSMakeRect(25,64,620,20),12,rgb(136,148,163),NO,NO);
 NSArray *names=@[@"TUNE C4",@"RESET ALL",@"SAVE PRESET",@"LOAD PRESET",@"EXPORT WAV",@"AUTO STRIKE"];
 for(int i=0;i<6;i++){NSRect r=buttonRect(i);fillRect(r,i==5&&autoStrike?rgb(59,81,68):rgb(32,38,47));text(names[i],NSMakeRect(r.origin.x,r.origin.y+11,r.size.width,20),12,rgb(220,226,232),YES,NO);}
 for(int i=0;i<8;i++){CGFloat x=24+(i%4)*352,y=94+(i/4)*320;fillRect(NSMakeRect(x,y,336,304),rgb(23,27,34));drawLine(NSMakePoint(x,y),NSMakePoint(x+336,y),i<7?accent(i):rgb(102,113,130),2);text(i<7?@(groupNames[i]):@"08  MODEL READOUT",NSMakeRect(x+16,y+13,308,23),14,rgb(205,213,224),NO,NO);}
 for(int i=0;i<PARAM_COUNT;i++){
  NSPoint c=knobPoint(i);double t=normalized(i,settings.p[i]),angle=(135+270*t)*PI/180;
  for(int segment=0;segment<36;segment++){double a=(135+270*segment/36.0)*PI/180,b=(135+270*(segment+1)/36.0)*PI/180;drawLine(NSMakePoint(c.x+32*cos(a),c.y+32*sin(a)),NSMakePoint(c.x+32*cos(b),c.y+32*sin(b)),segment/36.0<=t?accent(i/6):rgb(49,54,61),3);}
  NSBezierPath *circle=[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x-25,c.y-25,50,50)];[rgb(38,42,49)setFill];[circle fill];[(i==selected?accent(i/6):rgb(73,78,88))setStroke];circle.lineWidth=1;[circle stroke];
  drawLine(NSMakePoint(c.x+11*cos(angle),c.y+11*sin(angle)),NSMakePoint(c.x+22*cos(angle),c.y+22*sin(angle)),accent(i/6),3);
  text(@(parameters[i].unit),NSMakeRect(c.x-54,c.y-50,108,17),11,rgb(135,144,158),YES,NO);
  text(@(parameters[i].name),NSMakeRect(c.x-55,c.y+39,110,19),13,rgb(214,218,225),YES,NO);
  text(parameterValue(i,settings.p[i]),NSMakeRect(c.x-54,c.y+59,108,20),14,accent(i/6),YES,YES);
 }
 double cents=1200*log(display.fundamental/261.625565)/log(2);
 text([NSString stringWithFormat:@"%.2f Hz",display.fundamental],NSMakeRect(1098,463,300,44),34,rgb(232,213,159),NO,NO);
 text([NSString stringWithFormat:@"Center string / C4 %+.1f cents",cents],NSMakeRect(1098,510,306,20),12,rgb(151,163,177),NO,NO);
 NSArray *readouts=@[[NSString stringWithFormat:@"WIRE MASS       %.3f g/m",display.linearDensity*1000],[NSString stringWithFormat:@"INHARMONICITY   %.6f",display.inharmonicity],[NSString stringWithFormat:@"BOARD           %.2f kg / %.1f Hz",display.boardMass,display.boardFirst],[NSString stringWithFormat:@"CASE / CAVITY   %.0f / %.0f Hz",display.caseHz,display.cavityHz],[NSString stringWithFormat:@"ROOM DECAY      %.2f s (estimate)",display.rt60]];
 for(int i=0;i<5;i++)text(readouts[i],NSMakeRect(1098,547+i*26,305,20),14,rgb(196,205,218),NO,YES);
 text(@"Reduced physical model. Not a measured piano.",NSMakeRect(1098,683,302,25),11,rgb(127,139,154),NO,NO);
 short samples[BLOCK];double peak;unsigned long clips,faults;int held;
 pthread_mutex_lock(&sound.lock);memcpy(samples,sound.scope,sizeof(samples));peak=sound.peak;clips=sound.clips;faults=sound.faults;held=sound.held;pthread_mutex_unlock(&sound.lock);
 fillRect(NSMakeRect(24,744,128,130),held?rgb(200,210,215):rgb(239,239,230));text(@"C",NSMakeRect(24,766,128,45),34,rgb(30,36,43),YES,NO);text(@"HOLD / SPACE",NSMakeRect(24,830,128,28),12,rgb(47,55,64),YES,NO);
 fillRect(NSMakeRect(176,744,888,130),rgb(17,21,27));text(@"LIVE PRESSURE SIGNAL / FULL-SCALE VIEW",NSMakeRect(190,751,600,20),12,rgb(120,134,151),NO,NO);drawLine(NSMakePoint(190,815),NSMakePoint(1048,815),rgb(43,51,62),1);
 NSBezierPath *wave=[NSBezierPath bezierPath];wave.lineWidth=1;for(int i=0;i<BLOCK;i++){NSPoint p=NSMakePoint(190+i*858.0/(BLOCK-1),815-samples[i]/32768.0*45);if(i)[wave lineToPoint:p];else[wave moveToPoint:p];}[rgb(146,191,170)setStroke];[wave stroke];
 text(@"MONITOR LEVEL (NOT INSTRUMENT PHYSICS)",NSMakeRect(1098,744,310,24),11,rgb(155,168,184),NO,NO);fillRect(NSMakeRect(1100,790,300,5),rgb(46,55,67));fillRect(NSMakeRect(1100,790,300*volume/1.5,5),rgb(190,204,216));fillRect(NSMakeRect(1095+300*volume/1.5,780,10,25),rgb(220,224,229));
 text([NSString stringWithFormat:@"%.1f dB   Peak %.1f dBFS",volume>0?20*log10(volume):-96,peak>0?20*log10(peak):-96],NSMakeRect(1098,819,310,22),14,rgb(189,201,214),NO,YES);
 text(testMode?@"Self-test / audio device off":atomic_load(&audioError)?@"Audio unavailable - check output device":[NSString stringWithFormat:@"Core Audio   Ceiling: %lu   %@",clips,faults?@"FAULT":@"READY"],NSMakeRect(1098,849,310,22),12,rgb(139,173,153),NO,NO);
 drawLine(NSMakePoint(24,898),NSMakePoint(1416,898),rgb(49,56,66),1);
 NSString *help=selected>=0?[NSString stringWithFormat:@"%s | %s",parameters[selected].name,parameters[selected].help]:info;
 text(help,NSMakeRect(24,910,1392,40),14,rgb(184,196,210),NO,NO);[NSGraphicsContext restoreGraphicsState];
}
- (void)beginEdit:(int)index{
 if(editor)[self commitEditor:nil];[self releaseKeys];selected=editing=index;NSPoint c=knobPoint(index);CGFloat s=[self canvasScale];
 editor=[[NSTextField alloc]initWithFrame:NSMakeRect((c.x-53)*s,(c.y+56)*s,106*s,25*s)];editor.stringValue=[NSString stringWithFormat:@"%.12g",settings.p[index]];editor.font=[NSFont monospacedSystemFontOfSize:14*s weight:NSFontWeightRegular];editor.alignment=NSTextAlignmentCenter;editor.delegate=self;editor.target=self;editor.action=@selector(commitEditor:);[self addSubview:editor];[editor selectText:nil];
}
- (void)commitEditor:(id)sender{
 if(!editor)return;NSString *value=editor.stringValue;int index=editing;NSTextField *old=editor;editor=nil;editing=-1;
 const char *raw=value.UTF8String;char *end;double number=strtod(raw,&end);while(*end==' ')++end;
 if(end!=raw&&!*end&&isfinite(number)&&number>=parameters[index].min&&number<=parameters[index].max)[self setParameter:index value:number];
 else{selected=-1;info=[NSString stringWithFormat:@"Value not applied. Enter %.6g to %.6g %s.",parameters[index].min,parameters[index].max,parameters[index].unit];}
 [old removeFromSuperview];[self.window makeFirstResponder:self];[self setNeedsDisplay:YES];
}
- (BOOL)control:(NSControl*)control textView:(NSTextView*)view doCommandBySelector:(SEL)selector{
 if(selector==@selector(cancelOperation:)){NSTextField *old=editor;editor=nil;editing=-1;[old removeFromSuperview];[self.window makeFirstResponder:self];return YES;}return NO;
}
- (void)controlTextDidEndEditing:(NSNotification*)note{if(editor)[self commitEditor:nil];}
- (void)button:(int)index{
 if(editor)[self commitEditor:nil];selected=-1;
 switch(index){
 case 0:{double tension=string_tension_c4(&settings);if(tension>=parameters[P_STENSION].min&&tension<=parameters[P_STENSION].max){[self setParameter:P_STENSION value:tension];info=@"Tension solved for C4.";}else info=@"C4 requires tension outside this model's range. Change the wire dimensions first.";break;}
 case 1:default_settings(&settings);[self publish];info=@"All 42 physical parameters restored.";break;
 case 2:info=write_settings([[support stringByAppendingPathComponent:@"user-preset.piano"]fileSystemRepresentation],&settings)?@"Preset saved in Application Support/Piano Material Lab.":@"Could not save preset.";break;
 case 3:{Settings saved;if(read_settings([[support stringByAppendingPathComponent:@"user-preset.piano"]fileSystemRepresentation],&saved)){settings=saved;[self publish];info=@"Saved preset loaded.";}else info=@"No valid saved preset. Save a preset first.";break;}
 case 4:{NSSavePanel *panel=[NSSavePanel savePanel];panel.nameFieldStringValue=@"piano-note.wav";panel.allowedFileTypes=@[@"wav"];if([panel runModal]==NSModalResponseOK)info=write_wave(panel.URL.fileSystemRepresentation,&settings,6,0)?@"WAV exported (one-second hold, then release).":@"WAV export failed.";break;}
 case 5:autoStrike=!autoStrike;autoStart=CFAbsoluteTimeGetCurrent();if(!autoStrike){autoHeld=NO;[self syncGate];}info=autoStrike?@"Automatic strike every 2.5 seconds.":@"Automatic striking stopped.";break;
 }
 selected=-1;[self setNeedsDisplay:YES];
}
- (void)mouseDown:(NSEvent*)event{
 if(editor)[self commitEditor:nil];[self.window makeFirstResponder:self];NSPoint p=[self pointForEvent:event];
 for(int i=0;i<6;i++)if(NSPointInRect(p,buttonRect(i))){[self button:i];return;}
 if(NSPointInRect(p,NSMakeRect(24,744,128,130))){mouseHeld=YES;[self syncGate];return;}
 if(NSPointInRect(p,NSMakeRect(1090,772,320,38))){dragging=-2;[self mouseDragged:event];return;}
 int index=knobAt(p);if(index>=0){if(event.clickCount>=2){[self beginEdit:index];return;}selected=dragging=index;dragY=p.y;dragValue=normalized(index,settings.p[index]);}
}
- (void)mouseDragged:(NSEvent*)event{NSPoint p=[self pointForEvent:event];if(dragging>=0){double delta=(dragY-p.y)/180;if(event.modifierFlags&NSEventModifierFlagShift)delta*=.1;[self setParameter:dragging value:denormalized(dragging,dragValue+delta)];}else if(dragging==-2){volume=bounded((p.x-1100)/300*1.5,0,1.5);pthread_mutex_lock(&sound.lock);sound.volume=volume;pthread_mutex_unlock(&sound.lock);}}
- (void)mouseUp:(NSEvent*)event{dragging=-1;mouseHeld=NO;[self syncGate];}
- (void)mouseMoved:(NSEvent*)event{int index=knobAt([self pointForEvent:event]);if(index>=0){selected=index;[self setNeedsDisplay:YES];}}
- (void)rightMouseDown:(NSEvent*)event{int index=knobAt([self pointForEvent:event]);if(index>=0){Settings s;default_settings(&s);[self setParameter:index value:s.p[index]];}}
- (void)scrollWheel:(NSEvent*)event{int i=knobAt([self pointForEvent:event]);if(i>=0){double step=event.scrollingDeltaY*(event.hasPreciseScrollingDeltas?.002:.01);if(event.modifierFlags&NSEventModifierFlagShift)step*=.1;[self setParameter:i value:denormalized(i,normalized(i,settings.p[i])+step)];}}
- (void)keyDown:(NSEvent*)event{
 NSString *key=event.charactersIgnoringModifiers.lowercaseString;
 if(event.modifierFlags&NSEventModifierFlagCommand){[super keyDown:event];return;}
 if([key isEqualToString:@" "]){spaceHeld=YES;[self syncGate];}
 else if([key isEqualToString:@"c"]){cHeld=YES;[self syncGate];}
 else if([key isEqualToString:@"s"]&&!event.isARepeat)[self setParameter:P_PEDAL value:settings.p[P_PEDAL]<50?100:0];
 else if(event.keyCode==53){autoStrike=autoHeld=NO;[self releaseKeys];[self setParameter:P_PEDAL value:0];}
 else if(event.keyCode==48){selected=(selected+1)%PARAM_COUNT;[self setNeedsDisplay:YES];}
 else if(event.keyCode==36&&selected>=0)[self beginEdit:selected];
 else if(event.keyCode>=123&&event.keyCode<=126&&selected>=0){double direction=(event.keyCode==124||event.keyCode==126)?1:-1;[self setParameter:selected value:denormalized(selected,normalized(selected,settings.p[selected])+direction*((event.modifierFlags&NSEventModifierFlagShift)?.001:.01))];}
 else [super keyDown:event];
}
- (void)keyUp:(NSEvent*)event{NSString *key=event.charactersIgnoringModifiers.lowercaseString;if([key isEqualToString:@" "])spaceHeld=NO;if([key isEqualToString:@"c"])cHeld=NO;[self syncGate];}
- (BOOL)selfTest{
 BOOL pass=YES;int drags=0;Settings initial=settings;
 for(int i=0;i<PARAM_COUNT;i++){NSPoint point=knobPoint(i);CGFloat scale=[self canvasScale];NSPoint local=NSMakePoint(point.x*scale,point.y*scale);NSPoint screen=[self convertPoint:local toView:nil];
  NSEvent *down=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:screen modifierFlags:0 timestamp:0 windowNumber:self.window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];[self mouseDown:down];
  screen.y+=9*scale;
  NSEvent *drag=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDragged location:screen modifierFlags:0 timestamp:0 windowNumber:self.window.windowNumber context:nil eventNumber:2 clickCount:1 pressure:1];[self mouseDragged:drag];[self mouseUp:drag];
  if(settings.p[i]==initial.p[i])pass=NO;else ++drags;
 }
 [self beginEdit:P_HMASS];fprintf(stderr,"Exact editor exists=%d before=%s\n",editor!=nil,editor.stringValue.UTF8String);editor.stringValue=@"7.25";fprintf(stderr,"Exact editor input=%s\n",editor.stringValue.UTF8String);[self commitEditor:nil];fprintf(stderr,"Exact applied=%.17g\n",settings.p[P_HMASS]);BOOL exact=settings.p[P_HMASS]==7.25;pass &= exact;
 [self button:2];Settings saved=settings;[self button:1];[self button:3];BOOL preset=memcmp(&saved,&settings,sizeof(saved))==0;pass &= preset;
 [self beginEdit:P_HMASS];editor.stringValue=@"nan";[self commitEditor:nil];BOOL invalid=settings.p[P_HMASS]==saved.p[P_HMASS];pass &= invalid;
 [self setParameter:P_STENSION value:500];[self button:0];BOOL tuning=fabs(display.fundamental-261.625565)<1e-5;pass &= tuning;
 mouseHeld=YES;[self syncGate];pthread_mutex_lock(&sound.lock);BOOL gate=sound.held&&sound.serial>=1;pthread_mutex_unlock(&sound.lock);[self releaseKeys];
 pthread_mutex_lock(&sound.lock);gate &= !sound.held;pass &= gate;pthread_mutex_unlock(&sound.lock);
 settings=initial;[self publish];selected=-1;[self display];
 NSBitmapImageRep *image=[self bitmapImageRepForCachingDisplayInRect:self.bounds];[self cacheDisplayInRect:self.bounds toBitmapImageRep:image];
 [[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}]writeToFile:@"mac-ui-test.png" atomically:YES];
 NSDictionary *result=@{@"passed":@(pass),@"knob_drags":@(drags),@"exact_entry":@(exact),@"preset_roundtrip":@(preset),@"invalid_value_rejected":@(invalid),@"tune_c4":@(tuning),@"gate_release":@(gate),@"audio_device_tested":@NO};
 [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil]writeToFile:@"mac-ui-test.json" atomically:YES];
 return pass;
}
@end

@interface AppDelegate:NSObject<NSApplicationDelegate,NSWindowDelegate>
@property(strong) NSWindow *window;
@property(strong) PianoView *view;
@end
@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification*)notification{
 NSString *folder;
 if(testMode)folder=[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID]UUIDString]];
 else folder=[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"Piano Material Lab"];
 NSError *error=nil;if(![[NSFileManager defaultManager]createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&error]){NSAlert *alert=[NSAlert new];alert.messageText=@"Cannot create the settings folder";alert.informativeText=error.localizedDescription;[alert runModal];[NSApp terminate:nil];return;}
 NSRect available=NSScreen.mainScreen.visibleFrame;CGFloat scale=fmin(1,fmin((available.size.width-50)/1440.0,(available.size.height-80)/960.0));
 self.window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,1440*scale,960*scale) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
 self.window.title=@"Piano Material Lab - Mac";self.window.contentMinSize=NSMakeSize(900,600);self.window.contentAspectRatio=NSMakeSize(1440,960);self.window.delegate=self;self.window.releasedWhenClosed=NO;
 self.view=[[PianoView alloc]initWithFrame:self.window.contentView.bounds support:folder];self.view.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;self.window.contentView=self.view;
 [self.window center];[self.window makeKeyAndOrderFront:nil];[self.window makeFirstResponder:self.view];[NSApp activateIgnoringOtherApps:YES];
 if(testMode){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.3*NSEC_PER_SEC)),dispatch_get_main_queue(),^{BOOL pass=[self.view selfTest];[[NSFileManager defaultManager]removeItemAtPath:folder error:nil];exit(pass?0:1);});}
 else {OSStatus status=start_audio(&self.view->settings,self.view->volume);if(status){NSAlert *alert=[NSAlert new];alert.messageText=@"Audio output could not start";alert.informativeText=[NSString stringWithFormat:@"Core Audio returned %d. Check the Mac's selected output device, then reopen the app. WAV export is still available.",(int)status];[alert beginSheetModalForWindow:self.window completionHandler:nil];}}
}
- (void)windowDidResignKey:(NSNotification*)note{[self.view releaseKeys];}
- (void)applicationDidResignActive:(NSNotification*)note{[self.view releaseKeys];}
- (void)windowWillClose:(NSNotification*)note{[self.view saveCurrent];}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender{return YES;}
- (void)applicationWillTerminate:(NSNotification*)note{[self.view saveCurrent];stop_audio();}
@end
int main(int argc,const char **argv){
 @autoreleasepool{
  for(int i=1;i<argc;i++)if(!strcmp(argv[i],"--self-test"))testMode=YES;
  NSApplication *app=[NSApplication sharedApplication];[app setActivationPolicy:NSApplicationActivationPolicyRegular];
  NSMenu *main=[NSMenu new],*application=[NSMenu new];NSMenuItem *root=[NSMenuItem new];[main addItem:root];[root setSubmenu:application];
  [application addItemWithTitle:@"About Piano Material Lab" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
  [application addItem:[NSMenuItem separatorItem]];[application addItemWithTitle:@"Quit Piano Material Lab" action:@selector(terminate:) keyEquivalent:@"q"];
  NSMenuItem *editRoot=[[NSMenuItem alloc]initWithTitle:@"Edit" action:nil keyEquivalent:@""];NSMenu *edit=[[NSMenu alloc]initWithTitle:@"Edit"];
  [edit addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];[edit addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];[edit addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];[edit addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];[editRoot setSubmenu:edit];[main addItem:editRoot];app.mainMenu=main;
  AppDelegate *delegate=[AppDelegate new];app.delegate=delegate;[app run];
 }
 return 0;
}
