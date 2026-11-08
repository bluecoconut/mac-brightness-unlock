// Exercise the real transition code with a fake display; never touch hardware.
#define main StudioXDRApplicationMain
#import "../Sources/AppDelegate.m"
#undef main

@interface FakeDisplay : DisplayController
@property NSMutableDictionary<NSString *, NSNumber *> *values;
@property NSMutableArray<NSString *> *writes;
@property NSMutableArray<dispatch_block_t> *pending;
@property NSUserDefaults *testPreferences;
@property NSString *identifier;
@property NSString *lastError;
@property BOOL rejectAutoOff;
@property BOOL rejectAutoOn;
@property BOOL ignoreAutoOff;
@property BOOL rejectBoost;
@property BOOL deferAutoReadback;
@end

@implementation FakeDisplay
- (instancetype)init {
    if ((self = [super init])) {
        self.identifier = @"test-display-A";
        self.values = [@{kDisplayBrightnessAuto: @YES, kDisplayBrightnessMax: @600,
            kDisplayNitsMaxAurora: @1000, kAuroraFactor: @1,
            @"DisplayServicesBrightness": @0.55} mutableCopy];
        self.writes = [NSMutableArray array];
        self.pending = [NSMutableArray array];
        self.testPreferences = [[NSUserDefaults alloc] initWithSuiteName:
            [@"StudioXDRBrightness.tests." stringByAppendingString:NSUUID.UUID.UUIDString]];
    }
    return self;
}
- (NSString *)displayPreferenceID { return self.identifier; }
- (NSUserDefaults *)brightnessPreferences { return self.testPreferences; }
- (double)numberProperty:(NSString *)key { return self.values[key] ? self.values[key].doubleValue : -1; }
- (BOOL)setAutoBrightnessEnabled:(BOOL)enabled {
    [self.writes addObject:enabled ? @"auto:on" : @"auto:off"];
    if ((enabled && self.rejectAutoOn) || (!enabled && self.rejectAutoOff)) return NO;
    if (!enabled && self.ignoreAutoOff) return YES;
    if (self.deferAutoReadback) {
        NSMutableDictionary *values = self.values;
        [self.pending addObject:^{ values[kDisplayBrightnessAuto] = @(enabled); }];
    } else self.values[kDisplayBrightnessAuto] = @(enabled);
    return YES;
}
- (BOOL)setBaseBrightness:(float)value {
    [self.writes addObject:@"base"];
    self.values[@"DisplayServicesBrightness"] = @(value);
    return YES;
}
- (BOOL)setAuroraFactor:(float)value {
    [self.writes addObject:value > 1 ? @"boost" : @"normal"];
    if (value > 1 && self.rejectBoost) return NO;
    self.values[kAuroraFactor] = @(value);
    return YES;
}
- (void)afterBrightnessSettles:(dispatch_block_t)block { [self.pending addObject:[block copy]]; }
- (void)refresh:(id)sender { (void)sender; }
- (void)showError:(NSString *)message { self.lastError = message; }
- (void)drain {
    while (self.pending.count) {
        dispatch_block_t block = self.pending.firstObject;
        [self.pending removeObjectAtIndex:0];
        block();
    }
}
@end

static void Check(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); }
}

int main(void) { @autoreleasepool {
    FakeDisplay *d = [FakeDisplay new];
    [d changeBoost:YES maximum:NO];
    Check(d.changingBrightness && [d.writes isEqual:@[@"auto:off"]], @"Disable auto before applying boost");
    [d changeBoost:YES maximum:YES];
    Check(d.writes.count == 1, @"Ignore clicks during a transition");
    [d drain];
    Check(!d.lastError && !d.changingBrightness, @"Boost completes");
    Check(fabs([d numberProperty:@"DisplayServicesBrightness"]-0.55)<0.001, @"Boost preserves slider");
    Check([d numberProperty:kDisplayBrightnessAuto] == 0 && [d numberProperty:kAuroraFactor]>1.66, @"Manual boost excludes auto");
    Check(d.autoBrightnessBeforeBoost.boolValue, @"Remember prior Auto On");
    [d changeBoost:YES maximum:YES]; [d drain];
    Check([d numberProperty:@"DisplayServicesBrightness"] == 1 && d.autoBrightnessBeforeBoost.boolValue, @"Repeated maximum preserves original preference");
    [d changeBoost:NO maximum:NO]; [d drain];
    Check([d numberProperty:kAuroraFactor]==1 && [d numberProperty:kDisplayBrightnessAuto]==1 && !d.autoBrightnessBeforeBoost, @"Boost off restores Auto On");

    d = [FakeDisplay new]; d.values[kDisplayBrightnessAuto]=@NO;
    [d changeBoost:YES maximum:NO]; [d drain];
    [d changeBoost:NO maximum:NO]; [d drain];
    Check([d numberProperty:kDisplayBrightnessAuto]==0, @"Originally disabled Auto stays off");

    d = [FakeDisplay new]; [d changeBoost:YES maximum:NO]; [d drain];
    FakeDisplay *reopened = [FakeDisplay new];
    reopened.testPreferences=d.testPreferences; reopened.values=[d.values mutableCopy];
    [reopened changeBoost:NO maximum:NO]; [reopened drain];
    Check([reopened numberProperty:kDisplayBrightnessAuto]==1, @"Restore preference after relaunch");
    reopened.identifier=@"test-display-B";
    Check(!reopened.autoBrightnessBeforeBoost, @"Preferences are isolated per display");

    d = [FakeDisplay new]; d.rejectAutoOff=YES;
    [d changeBoost:YES maximum:YES]; [d drain];
    Check(d.lastError && ![d.writes containsObject:@"boost"] && ![d.writes containsObject:@"base"], @"Auto disable failure blocks boost and maximum");
    Check(!d.autoBrightnessBeforeBoost, @"Failed action does not retain a restoration entry");

    d = [FakeDisplay new]; d.ignoreAutoOff=YES;
    [d changeBoost:YES maximum:YES]; [d drain];
    Check(d.lastError && [d numberProperty:kAuroraFactor]==1, @"False success from Auto API cannot enable boost");

    d = [FakeDisplay new]; d.rejectBoost=YES;
    [d changeBoost:YES maximum:YES]; [d drain];
    Check(d.lastError && [d numberProperty:kDisplayBrightnessAuto]==1 && fabs([d numberProperty:@"DisplayServicesBrightness"]-0.55)<0.001, @"Failed maximum restores auto and slider");

    d = [FakeDisplay new]; [d changeBoost:YES maximum:NO]; [d drain];
    [d toggleAutoBrightness:nil]; [d drain];
    Check([d numberProperty:kDisplayBrightnessAuto]==1 && [d numberProperty:kAuroraFactor]==1 && !d.autoBrightnessBeforeBoost, @"Explicit Auto On ends manual boost");
    [d toggleAutoBrightness:nil]; [d drain];
    Check([d numberProperty:kDisplayBrightnessAuto]==0 && [d numberProperty:kAuroraFactor]==1, @"Auto Off does not start boost");

    d = [FakeDisplay new]; d.deferAutoReadback=YES;
    [d changeBoost:YES maximum:NO]; [d drain];
    Check(!d.lastError && [d numberProperty:kDisplayBrightnessAuto]==0, @"Wait for asynchronous Auto Off before boost");
    [d toggleAutoBrightness:nil]; [d drain];
    Check(!d.lastError && [d numberProperty:kDisplayBrightnessAuto]==1 && !d.changingBrightness, @"Wait for asynchronous Auto On before reporting success");
    [d changeBoost:YES maximum:NO]; [d drain];
    [d changeBoost:NO maximum:NO]; [d drain];
    Check(!d.lastError && [d numberProperty:kDisplayBrightnessAuto]==1 && !d.autoBrightnessBeforeBoost, @"Wait for asynchronous preference restoration");

    d = [FakeDisplay new]; [d changeBoost:YES maximum:NO];
    d.identifier=@"test-display-B"; NSUInteger before=d.writes.count; [d drain];
    Check(d.lastError && d.writes.count==before, @"Disconnect prevents delayed writes to another display");
    d.identifier=@"test-display-A";
    Check(d.autoBrightnessBeforeBoost.boolValue, @"Disconnect retains restoration preference");

    d = [FakeDisplay new]; [d changeBoost:YES maximum:NO]; [d drain]; d.rejectAutoOn=YES;
    [d changeBoost:NO maximum:NO]; [d drain];
    Check(d.lastError && d.autoBrightnessBeforeBoost.boolValue, @"Failed restoration can be retried");

    d = [FakeDisplay new]; d.values[kDisplayNitsMaxAurora]=@(NAN);
    [d changeBoost:YES maximum:NO]; [d drain];
    Check(d.lastError && d.writes.count==0, @"Invalid readings never change settings");
    // Two screens can transition concurrently, sharing the app's preferences.
    FakeDisplay *builtIn = [FakeDisplay new];
    FakeDisplay *external = [FakeDisplay new];
    builtIn.identifier = @"built-in";
    external.identifier = @"external";
    external.testPreferences = builtIn.testPreferences;
    builtIn.values[kDisplayBrightnessAuto] = @NO;
    [builtIn changeBoost:YES maximum:YES];
    [external changeBoost:YES maximum:NO];
    Check(builtIn.changingBrightness && external.changingBrightness, @"Screens transition independently");
    [external drain];
    Check(builtIn.changingBrightness && builtIn.writes.count == 1, @"Finishing external does not advance built-in transition");
    [builtIn drain];
    Check(!builtIn.lastError && !external.lastError, @"Both concurrent boosts complete");
    Check(!builtIn.autoBrightnessBeforeBoost.boolValue && external.autoBrightnessBeforeBoost.boolValue, @"Remember separate auto preferences");
    Check([builtIn numberProperty:@"DisplayServicesBrightness"] == 1 && fabs([external numberProperty:@"DisplayServicesBrightness"]-0.55)<0.001, @"Maximum changes only its screen slider");
    NSUInteger externalWrites = external.writes.count;
    [builtIn changeBoost:NO maximum:NO]; [builtIn drain];
    Check([external numberProperty:kAuroraFactor]>1.66 && external.writes.count==externalWrites, @"Turning off one screen leaves the other boosted");
    Check([builtIn numberProperty:kDisplayBrightnessAuto]==0 && external.autoBrightnessBeforeBoost.boolValue, @"Restoration preserves the other screen preference");
    [external changeBoost:NO maximum:NO]; [external drain];
    Check([external numberProperty:kDisplayBrightnessAuto]==1 && !external.autoBrightnessBeforeBoost, @"Each screen restores its own Auto Brightness setting");

    puts("PASS: brightness transitions, restoration, relaunch, explicit toggles, failure rollback, disconnect handling, and concurrent per-screen isolation");
} return 0; }
