#define main BrightnessUnlockApplicationMain
#import "../Sources/AppDelegate.m"
#undef main
@interface HardwareDisplay : DisplayController
@property NSString *lastError;
@end
@implementation HardwareDisplay
- (NSUserDefaults *)brightnessPreferences { return [[NSUserDefaults alloc] initWithSuiteName:@"io.github.bluecoconut.StudioXDRBrightness"]; }
- (void)showError:(NSString *)message { self.lastError=message; fprintf(stderr,"ERROR %s: %s\n",self.displayName.UTF8String,message.UTF8String); }
@end
static void Wait(double seconds) {
 NSDate *end=[NSDate dateWithTimeIntervalSinceNow:seconds];
 while(end.timeIntervalSinceNow>0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}
static void Dump(NSString *stage, NSArray<HardwareDisplay *> *displays) {
 printf("\n%s | %s\n",stage.UTF8String,NSDate.date.description.UTF8String);
 for(HardwareDisplay *d in displays) printf("%s id=%u slider=%.3f baseNits=%.2f factor=%.6f physicalNits=%.2f auto=%.0f maxAurora=%.0f savedAuto=%s\n",d.displayName.UTF8String,d.displayID,[d numberProperty:@"DisplayServicesBrightness"],[d numberProperty:@"DisplayNitsKey"],[d numberProperty:kAuroraFactor],[d numberProperty:kNitsPhysical],[d numberProperty:kDisplayBrightnessAuto],[d numberProperty:kDisplayNitsMaxAurora],d.autoBrightnessBeforeBoost.description.UTF8String ?: "none");
 fflush(stdout);
}
static void Require(BOOL condition, NSString *message) {
 if(!condition) @throw [NSException exceptionWithName:@"HardwareCheckFailed" reason:message userInfo:nil];
 printf("PASS: %s\n",message.UTF8String);fflush(stdout);
}
static BOOL Maxed(HardwareDisplay *d) { return !d.lastError && !d.changingBrightness && fabs([d numberProperty:kNitsPhysical]-1000)<3 && fabs([d numberProperty:kAuroraFactor]-1000.0/600)<0.01 && [d numberProperty:kDisplayBrightnessAuto]==0; }
int main(void) { @autoreleasepool {
 [NSApplication sharedApplication];
 dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness",RTLD_LAZY);
 dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",RTLD_LAZY);
 id client=[[NSClassFromString(@"DisplayServicesClient") alloc] init];
 NSMutableArray<HardwareDisplay *> *displays=[NSMutableArray array];
 NSMutableArray<NSDictionary *> *initial=[NSMutableArray array];
 for(NSScreen *screen in NSScreen.screens) {
  HardwareDisplay *d=[HardwareDisplay new];d.displayClient=client;
  d.displayID=[screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
  d.displayName=CGDisplayIsBuiltin(d.displayID)?@"MacBook Pro Built-in":screen.localizedName;
  d.identity=d.displayPreferenceID;
  if([d numberProperty:kDisplayNitsMaxAurora]<=0) continue;
  [displays addObject:d];
  [initial addObject:@{@"auto":@([d numberProperty:kDisplayBrightnessAuto]),@"factor":@([d numberProperty:kAuroraFactor]),@"slider":@([d numberProperty:@"DisplayServicesBrightness"])}];
 }
 NSDictionary *savedPrefs=[displays.firstObject.brightnessPreferences dictionaryForKey:kAutoBeforeBoostKey] ?: @{};
 @try {
  Require(displays.count==2,@"Both physical XDR displays discovered");
  HardwareDisplay *a=displays[0],*b=displays[1];
  Require(CGDisplayIsBuiltin(a.displayID),@"First screen is the built-in MacBook display");
  // Normalize an already-boosted session using its saved per-screen preferences.
  for (HardwareDisplay *d in displays) if ([d numberProperty:kAuroraFactor]>1.001) [d changeBoost:NO maximum:NO];
  Wait(3);
  for (HardwareDisplay *d in displays) Require(!d.lastError, @"Pre-test restoration succeeded");
  NSArray *baselineAuto = @[@([a numberProperty:kDisplayBrightnessAuto]), @([b numberProperty:kDisplayBrightnessAuto])];
  Dump(@"INITIAL",displays);
  double bFactor=[b numberProperty:kAuroraFactor],bNits=[b numberProperty:kNitsPhysical],bAuto=[b numberProperty:kDisplayBrightnessAuto];
  [a enableMaximum:nil];Wait(2.5);Dump(@"BUILT-IN BOOST ONLY",displays);
  Require(Maxed(a),@"Built-in screen reaches reported 1000 nits through native Aurora");
  Require(fabs([b numberProperty:kAuroraFactor]-bFactor)<0.01 && fabs([b numberProperty:kNitsPhysical]-bNits)<3 && [b numberProperty:kDisplayBrightnessAuto]==bAuto,@"Built-in boost leaves external screen unchanged");
  [b enableMaximum:nil];Wait(2.5);Dump(@"BOTH BOOSTED",displays);
  Require(Maxed(a)&&Maxed(b),@"Both displays hold reported 1000 nits independently");
  [a changeBoost:NO maximum:NO];Wait(2.5);Dump(@"BUILT-IN BOOST OFF",displays);
  Require(!a.lastError && [a numberProperty:kAuroraFactor]==1 && [a numberProperty:kDisplayBrightnessAuto]==[baselineAuto[0] doubleValue],@"Built-in boost off restores its original Auto Brightness setting");
  Require(Maxed(b),@"External screen remains at 1000 nits when built-in boost is off");
  [b changeBoost:NO maximum:NO];Wait(3);Dump(@"BOTH RESTORED",displays);
  Require(!b.lastError && [b numberProperty:kAuroraFactor]==1 && [b numberProperty:kDisplayBrightnessAuto]==[baselineAuto[1] doubleValue],@"External boost off restores its original Auto Brightness setting");
  [a enableMaximum:nil];[b enableMaximum:nil];Wait(3);Dump(@"FINAL BOTH BOOSTED",displays);
  Require(Maxed(a)&&Maxed(b),@"Concurrent per-screen maximum actions both succeed");
  Wait(5);Dump(@"STABILITY CHECK",displays);
  Require(Maxed(a)&&Maxed(b),@"Both displays remain at reported 1000 nits after settling");
  puts("ALL HARDWARE CHECKS PASSED. Values are macOS telemetry, not photometer measurements.");
 } @catch(NSException *e) {
  fprintf(stderr,"FAIL: %s\nRestoring initial hardware state.\n",e.reason.UTF8String);
  for(NSUInteger i=0;i<displays.count;i++) { HardwareDisplay *d=displays[i];[d setAuroraFactor:[initial[i][@"factor"] floatValue]];[d setBaseBrightness:[initial[i][@"slider"] floatValue]];[d setAutoBrightnessEnabled:[initial[i][@"auto"] boolValue]]; }
  Wait(2);[displays.firstObject.brightnessPreferences setObject:savedPrefs forKey:kAutoBeforeBoostKey];return 1;
 }
}return 0;}
