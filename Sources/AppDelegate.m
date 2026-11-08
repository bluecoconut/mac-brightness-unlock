#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ServiceManagement/ServiceManagement.h>
#import <dlfcn.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>

@interface AutoBrightnessRowButton : NSButton
@end

@implementation AutoBrightnessRowButton
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    if (self.highlighted) {
        [[NSColor.controlAccentColor colorWithAlphaComponent:0.15] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:4 yRadius:4] fill];
    }
    NSDictionary *labelStyle = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: NSColor.secondaryLabelColor
    };
    NSDictionary *valueStyle = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: self.enabled ? NSColor.controlAccentColor : NSColor.disabledControlTextColor
    };
    NSString *label = @"Auto brightness";
    NSSize labelSize = [label sizeWithAttributes:labelStyle];
    NSSize valueSize = [self.title sizeWithAttributes:valueStyle];
    [label drawAtPoint:NSMakePoint(0, (NSHeight(self.bounds) - labelSize.height) / 2) withAttributes:labelStyle];
    [self.title drawAtPoint:NSMakePoint(NSWidth(self.bounds) - valueSize.width,
        (NSHeight(self.bounds) - valueSize.height) / 2) withAttributes:valueStyle];
}
@end

// Each screen owns its controls, transition state, and saved Auto Brightness setting.
@interface DisplayController : NSObject
@property NSTextField *heroValue;
@property NSTextField *stateLabel;
@property NSTextField *factorValue;
@property NSTextField *ambientValue;
@property NSButton *autoButton;
@property NSSwitch *auroraSwitch;
@property NSMenuItem *maximumItem;
@property NSView *content;
@property id displayClient;
@property CGDirectDisplayID displayID;
@property NSString *displayName;
@property NSString *identity;
@property BOOL changingBrightness;
- (NSView *)buildContent;
- (NSString *)displayPreferenceID;
- (double)numberProperty:(NSString *)key;
- (double)numberProperty:(NSString *)key forDisplay:(CGDirectDisplayID)displayID;
- (void)refresh:(id)sender;
- (void)enableMaximum:(id)sender;
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property NSStatusItem *statusItem;
@property NSMenu *statusMenu;
@property NSWindow *settingsWindow;
@property NSSwitch *launchSwitch;
@property NSPopUpButton *visibilityPopUp;
@property NSTextField *loginStatusLabel;
@property NSTimer *timer;
@property id displayClient;
@property NSArray<DisplayController *> *displays;
@end

static NSString * const kAuroraFactor = @"AuroraFactor";
static NSString * const kAuroraFactorWithFade = @"AuroraFactorWithFade";
static NSString * const kDisplayBrightnessAuto = @"DisplayBrightnessAuto";
static NSString * const kDisplayBrightnessMax = @"DisplayBrightnessMax";
static NSString * const kDisplayNitsMaxAurora = @"DisplayNitsMaxAurora";
static NSString * const kNitsPhysical = @"NitsPhysical";
static NSString * const kAggregatedLux = @"AggregatedLux";
static NSString * const kVisibilityModeKey = @"StatusItemVisibility";
static NSString * const kAutoBeforeBoostKey = @"AutoBrightnessBeforeBoost";

typedef NS_ENUM(NSInteger, StatusItemVisibility) {
    StatusItemVisibilityHideAlways = 0,
    StatusItemVisibilityShowAlways = 1,
    StatusItemVisibilityWhenConnected = 2,
};

static NSTextField *Label(NSString *text, CGFloat size, NSFontWeight weight) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = NSColor.labelColor;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

static NSStackView *InfoRow(NSString *name, NSView *value) {
    NSTextField *nameLabel = Label(name, 12, NSFontWeightRegular);
    nameLabel.textColor = NSColor.secondaryLabelColor;
    NSView *spacer = [[NSView alloc] init];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [spacer setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *row = [NSStackView stackViewWithViews:@[nameLabel, spacer, value]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 8;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row.heightAnchor constraintEqualToConstant:18].active = YES;
    return row;
}

static NSImage *BrightnessBurstImage(BOOL active) {
    static NSImage *offImage = nil;
    static NSImage *onImage = nil;
    if (active && onImage) return onImage;
    if (!active && offImage) return offImage;

    NSImage *image = [NSImage imageWithSize:NSMakeSize(18, 18) flipped:NO drawingHandler:^BOOL(NSRect bounds) {
        (void)bounds;
        [[NSColor blackColor] setFill];
        NSBezierPath *burst = [[NSBezierPath alloc] init];
        for (NSInteger point = 0; point < 16; point++) {
            CGFloat angle = -M_PI_2 + point * (M_PI / 8.0);
            CGFloat radius;
            if (point % 2 == 0) {
                NSInteger ray = point / 2;
                radius = ray % 2 == 0 ? 8.0 : 6.0;
            } else {
                radius = 3.8;
            }
            NSPoint vertex = NSMakePoint(9 + cos(angle) * radius, 9 + sin(angle) * radius);
            if (point == 0) [burst moveToPoint:vertex];
            else [burst lineToPoint:vertex];
        }
        [burst closePath];
        [burst appendBezierPathWithOvalInRect:NSMakeRect(6.35, 6.35, 5.3, 5.3)];
        burst.windingRule = NSWindingRuleEvenOdd;
        [burst fill];
        if (active) {
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(7.8, 7.8, 2.4, 2.4)] fill];
        }
        return YES;
    }];
    image.template = YES;
    if (active) onImage = image;
    else offImage = image;
    return image;
}

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY | RTLD_LOCAL);
    dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY | RTLD_LOCAL);
    self.displayClient = [[NSClassFromString(@"DisplayServicesClient") alloc] init];
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{kVisibilityModeKey: @(StatusItemVisibilityWhenConnected)}];
    [self refresh:nil];
    self.timer = [NSTimer timerWithTimeInterval:1.0 target:self selector:@selector(refresh:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)rebuildMenu {
    [self.statusMenu cancelTracking];
    [self.statusMenu removeAllItems];
    self.statusMenu = [[NSMenu alloc] initWithTitle:@""];
    self.statusMenu.autoenablesItems = NO;
    for (DisplayController *display in self.displays) {
        NSMenuItem *contentItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
        contentItem.view = display.content ?: [display buildContent];
        [self.statusMenu addItem:contentItem];
        [self.statusMenu addItem:display.maximumItem];
        [self.statusMenu addItem:NSMenuItem.separatorItem];
    }
    if (!self.displays.count) {
        NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:@"No compatible XDR displays connected" action:nil keyEquivalent:@""];
        [self.statusMenu addItem:empty];
        [self.statusMenu addItem:NSMenuItem.separatorItem];
    }
    NSMenuItem *settings = [[NSMenuItem alloc] initWithTitle:@"Settings…" action:@selector(showSettings:) keyEquivalent:@","];
    settings.target = self;
    [self.statusMenu addItem:settings];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(quit:) keyEquivalent:@"q"];
    quit.target = self;
    [self.statusMenu addItem:quit];
    self.statusItem.menu = self.statusMenu;
}

- (void)showError:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Brightness Unlock";
    alert.informativeText = message;
    [alert runModal];
}

// Reconcile by UUID and current display ID. Never retarget an in-flight controller.
- (void)refresh:(id)sender {
    (void)sender;
    NSMutableArray<DisplayController *> *connected = [NSMutableArray array];
    for (NSScreen *screen in NSScreen.screens) {
        CGDirectDisplayID displayID = [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
        DisplayController *candidate = [DisplayController new];
        candidate.displayClient = self.displayClient;
        candidate.displayID = displayID;
        candidate.displayName = CGDisplayIsBuiltin(displayID) ? @"MacBook Pro · Built-in" : screen.localizedName;
        candidate.identity = [candidate displayPreferenceID];
        double normal = [candidate numberProperty:kDisplayBrightnessMax];
        double maximum = [candidate numberProperty:kDisplayNitsMaxAurora];
        if (!candidate.identity || !isfinite(normal) || !isfinite(maximum) || normal <= 0 ||
            maximum <= normal || maximum / normal > 2) continue;
        DisplayController *controller = candidate;
        for (DisplayController *existing in self.displays) {
            if (existing.displayID == displayID && [existing.identity isEqualToString:candidate.identity]) {
                controller = existing;
                break;
            }
        }
        [connected addObject:controller];
    }
    BOOL changed = !self.statusMenu || ![self.displays isEqualToArray:connected];
    self.displays = connected;
    if (changed) [self rebuildMenu];
    StatusItemVisibility visibility = [self statusItemVisibility];
    if (visibility == StatusItemVisibilityShowAlways ||
        (visibility == StatusItemVisibilityWhenConnected && connected.count)) [self ensureStatusItem];
    else [self removeStatusItem];
    BOOL boosted = NO;
    NSMutableArray<NSString *> *readings = [NSMutableArray array];
    for (DisplayController *display in self.displays) {
        [display refresh:nil];
        boosted |= [display numberProperty:kAuroraFactor] > 1.001;
        [readings addObject:[NSString stringWithFormat:@"%@: %@", display.displayName, display.heroValue.stringValue]];
    }
    self.statusItem.button.image = BrightnessBurstImage(boosted);
    self.statusItem.button.toolTip = readings.count ? [readings componentsJoinedByString:@"\n"] : @"No compatible XDR displays connected";
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    (void)sender;
    if (!flag) [self showSettings:nil];
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [self.timer invalidate];
    if (self.statusItem) [[NSStatusBar systemStatusBar] removeStatusItem:self.statusItem];
}

- (void)ensureStatusItem {
    if (self.statusItem) return;
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    NSStatusBarButton *button = self.statusItem.button;
    button.image = BrightnessBurstImage(NO);
    button.toolTip = @"Brightness Unlock";
    self.statusItem.menu = self.statusMenu;
}

- (void)removeStatusItem {
    if (!self.statusItem) return;
    [self.statusMenu cancelTracking];
    self.statusItem.menu = nil;
    [[NSStatusBar systemStatusBar] removeStatusItem:self.statusItem];
    self.statusItem = nil;
}

- (void)quit:(id)sender {
    (void)sender;
    [NSApp terminate:nil];
}

- (StatusItemVisibility)statusItemVisibility {
    return (StatusItemVisibility)[[NSUserDefaults standardUserDefaults] integerForKey:kVisibilityModeKey];
}

- (void)updateLoginItemControls {
    SMAppServiceStatus status = SMAppService.mainAppService.status;
    self.launchSwitch.state = status == SMAppServiceStatusEnabled
        ? NSControlStateValueOn
        : NSControlStateValueOff;
    self.loginStatusLabel.stringValue = status == SMAppServiceStatusRequiresApproval
        ? @"Approval required in System Settings › Login Items"
        : @"Opens quietly when you sign in";
    self.loginStatusLabel.textColor = status == SMAppServiceStatusRequiresApproval
        ? NSColor.systemOrangeColor
        : NSColor.secondaryLabelColor;
}

- (void)showSettings:(id)sender {
    (void)sender;
    if (!self.settingsWindow) {
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 390, 160)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
            backing:NSBackingStoreBuffered
            defer:NO];
        window.title = @"Brightness Unlock Settings";
        window.releasedWhenClosed = NO;

        NSView *content = window.contentView;
        NSStackView *root = [[NSStackView alloc] init];
        root.orientation = NSUserInterfaceLayoutOrientationVertical;
        root.alignment = NSLayoutAttributeWidth;
        root.spacing = 14;
        root.translatesAutoresizingMaskIntoConstraints = NO;
        [content addSubview:root];
        [NSLayoutConstraint activateConstraints:@[
            [root.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
            [root.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
            [root.topAnchor constraintEqualToAnchor:content.topAnchor constant:20]
        ]];

        NSTextField *launchTitle = Label(@"Launch at Login", 13, NSFontWeightMedium);
        self.launchSwitch = [[NSSwitch alloc] initWithFrame:NSZeroRect];
        self.launchSwitch.controlSize = NSControlSizeSmall;
        self.launchSwitch.target = self;
        self.launchSwitch.action = @selector(toggleLaunchAtLogin:);
        NSView *launchSpacer = [[NSView alloc] init];
        [launchSpacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSStackView *launchRow = [NSStackView stackViewWithViews:@[launchTitle, launchSpacer, self.launchSwitch]];
        launchRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        launchRow.alignment = NSLayoutAttributeCenterY;

        self.loginStatusLabel = Label(@"Opens quietly when you sign in", 11, NSFontWeightRegular);
        self.loginStatusLabel.textColor = NSColor.secondaryLabelColor;
        self.loginStatusLabel.alignment = NSTextAlignmentLeft;
        NSStackView *launchGroup = [NSStackView stackViewWithViews:@[launchRow, self.loginStatusLabel]];
        launchGroup.orientation = NSUserInterfaceLayoutOrientationVertical;
        launchGroup.alignment = NSLayoutAttributeWidth;
        launchGroup.spacing = 3;
        [root addArrangedSubview:launchGroup];
        [launchGroup.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;
        [self.loginStatusLabel.widthAnchor constraintEqualToAnchor:launchGroup.widthAnchor].active = YES;

        NSTextField *visibilityTitle = Label(@"Menu Bar Icon", 13, NSFontWeightMedium);
        self.visibilityPopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        [self.visibilityPopUp addItemsWithTitles:@[@"Hide Always", @"Show Always", @"Show When Display Is Connected"]];
        self.visibilityPopUp.controlSize = NSControlSizeSmall;
        self.visibilityPopUp.target = self;
        self.visibilityPopUp.action = @selector(changeVisibility:);
        NSView *visibilitySpacer = [[NSView alloc] init];
        [visibilitySpacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSStackView *visibilityRow = [NSStackView stackViewWithViews:@[visibilityTitle, visibilitySpacer, self.visibilityPopUp]];
        visibilityRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        visibilityRow.alignment = NSLayoutAttributeCenterY;
        [root addArrangedSubview:visibilityRow];
        [visibilityRow.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;

        NSTextField *visibilityHelp = Label(@"Reopen the app from Finder to access Settings when the icon is hidden.", 11, NSFontWeightRegular);
        visibilityHelp.textColor = NSColor.secondaryLabelColor;
        visibilityHelp.maximumNumberOfLines = 2;
        [root addArrangedSubview:visibilityHelp];
        [visibilityHelp.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;

        self.settingsWindow = window;
    }

    [self.visibilityPopUp selectItemAtIndex:[self statusItemVisibility]];
    [self updateLoginItemControls];
    [self.settingsWindow center];
    [self.settingsWindow makeKeyAndOrderFront:nil];
    [NSApp activate];
}

- (void)toggleLaunchAtLogin:(id)sender {
    (void)sender;
    NSError *error = nil;
    BOOL enable = self.launchSwitch.state == NSControlStateValueOn;
    BOOL succeeded = enable
        ? [SMAppService.mainAppService registerAndReturnError:&error]
        : [SMAppService.mainAppService unregisterAndReturnError:&error];
    if (!succeeded) {
        [self updateLoginItemControls];
        [self showError:error.localizedDescription ?: @"Couldn’t update Launch at Login."];
        return;
    }
    [self updateLoginItemControls];
}

- (void)changeVisibility:(id)sender {
    (void)sender;
    [[NSUserDefaults standardUserDefaults] setInteger:self.visibilityPopUp.indexOfSelectedItem forKey:kVisibilityModeKey];
    [self refresh:nil];
}

@end

@implementation DisplayController

- (NSView *)buildContent {
    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 248, 150)];
    NSStackView *root = [[NSStackView alloc] init];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeWidth;
    root.spacing = 5;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:10],
        [root.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-10],
        [root.topAnchor constraintEqualToAnchor:content.topAnchor constant:9],
        [root.bottomAnchor constraintLessThanOrEqualToAnchor:content.bottomAnchor constant:-8]
    ]];

    NSTextField *name = Label(self.displayName ?: @"Display", 12, NSFontWeightSemibold);
    name.lineBreakMode = NSLineBreakByTruncatingTail;
    name.toolTip = self.displayName;
    [root addArrangedSubview:name];
    [name.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;

    self.heroValue = Label(@"— nits", 20, NSFontWeightSemibold);
    NSView *headerSpacer = [[NSView alloc] init];
    headerSpacer.translatesAutoresizingMaskIntoConstraints = NO;
    [headerSpacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.auroraSwitch = [[NSSwitch alloc] initWithFrame:NSZeroRect];
    self.auroraSwitch.target = self;
    self.auroraSwitch.action = @selector(toggleAurora:);
    self.auroraSwitch.controlSize = NSControlSizeSmall;
    self.auroraSwitch.toolTip = @"Boost pauses Auto Brightness; turning boost off restores your previous setting";
    self.auroraSwitch.accessibilityLabel = [self.displayName stringByAppendingString:@" boost"];
    NSStackView *header = [NSStackView stackViewWithViews:@[self.heroValue, headerSpacer, self.auroraSwitch]];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.alignment = NSLayoutAttributeCenterY;
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [root addArrangedSubview:header];
    [header.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;

    self.stateLabel = Label(@"Reading display…", 11, NSFontWeightRegular);
    self.stateLabel.textColor = NSColor.secondaryLabelColor;
    self.stateLabel.alignment = NSTextAlignmentLeft;
    [root addArrangedSubview:self.stateLabel];
    [self.stateLabel.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;

    NSBox *separator = [[NSBox alloc] init];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [root addArrangedSubview:separator];
    [separator.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;

    self.factorValue = Label(@"—", 12, NSFontWeightSemibold);
    self.ambientValue = Label(@"—", 12, NSFontWeightSemibold);
    self.autoButton = [AutoBrightnessRowButton buttonWithTitle:@"—" target:self action:@selector(toggleAutoBrightness:)];
    self.autoButton.bordered = NO;
    self.autoButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.autoButton.heightAnchor constraintEqualToConstant:18].active = YES;
    self.autoButton.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    self.autoButton.contentTintColor = NSColor.controlAccentColor;
    self.autoButton.controlSize = NSControlSizeSmall;
    self.autoButton.accessibilityLabel = [self.displayName stringByAppendingString:@" auto brightness"];
    self.autoButton.toolTip = @"Toggle Auto Brightness. Turning it on ends manual boost.";
    NSStackView *details = [NSStackView stackViewWithViews:@[
        InfoRow(@"Aurora factor", self.factorValue),
        InfoRow(@"Ambient light", self.ambientValue),
        self.autoButton
    ]];
    details.orientation = NSUserInterfaceLayoutOrientationVertical;
    details.alignment = NSLayoutAttributeWidth;
    details.spacing = 1;
    details.translatesAutoresizingMaskIntoConstraints = NO;
    [details setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    [root addArrangedSubview:details];
    [details.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;
    [self.autoButton.widthAnchor constraintEqualToAnchor:details.widthAnchor].active = YES;

    self.content = content;
    self.maximumItem = [[NSMenuItem alloc] initWithTitle:@"Set to 1000 nits" action:@selector(enableMaximum:) keyEquivalent:@""];
    self.maximumItem.target = self;
    [self refresh:nil];
    return content;
}

- (id)copyProperty:(NSString *)key forDisplay:(CGDirectDisplayID)displayID {
    if (!self.displayClient || !displayID || ![self displayPreferenceID]) return nil;
    id (*send)(id, SEL, id, unsigned long long) = (void *)objc_msgSend;
    return send(self.displayClient, sel_registerName("copyPropertyForKey:andDisplay:"), key, displayID);
}

- (id)copyProperty:(NSString *)key {
    return [self copyProperty:key forDisplay:self.displayID];
}

- (double)numberProperty:(NSString *)key forDisplay:(CGDirectDisplayID)displayID {
    id value = [self copyProperty:key forDisplay:displayID];
    return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : -1.0;
}

- (double)numberProperty:(NSString *)key {
    id value = [self copyProperty:key];
    return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : -1.0;
}

- (BOOL)setProperty:(NSString *)key value:(id)value {
    if (!self.displayClient || ![self displayPreferenceID]) return NO;
    BOOL (*send)(id, SEL, id, id, unsigned long long) = (void *)objc_msgSend;
    return send(self.displayClient, sel_registerName("setProperty:withKey:andDisplay:"), value, key, self.displayID);
}

- (BOOL)setAuroraFactor:(float)factor {
    NSDictionary *payload = @{kAuroraFactor: @(factor), @"AuroraFadePeriod": @0.5f};
    return [self setProperty:kAuroraFactorWithFade value:payload];
}

// A display UUID keeps a reconnect/relaunch from restoring another monitor's setting.
- (NSString *)displayPreferenceID {
    if (!self.displayID || !CGDisplayIsOnline(self.displayID)) return nil;
    CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(self.displayID);
    if (!uuid) return nil;
    NSString *identifier = CFBridgingRelease(CFUUIDCreateString(NULL, uuid));
    CFRelease(uuid);
    return self.identity && ![self.identity isEqualToString:identifier] ? nil : identifier;
}

- (NSUserDefaults *)brightnessPreferences {
    return NSUserDefaults.standardUserDefaults;
}

- (NSNumber *)autoBrightnessBeforeBoost {
    NSString *identifier = [self displayPreferenceID];
    id value = identifier ? [[self.brightnessPreferences dictionaryForKey:kAutoBeforeBoostKey] objectForKey:identifier] : nil;
    return [value isKindOfClass:NSNumber.class] ? value : nil;
}

- (void)saveAutoBrightnessBeforeBoost:(NSNumber *)value {
    NSString *identifier = [self displayPreferenceID];
    if (!identifier) return;
    NSMutableDictionary *settings = [[self.brightnessPreferences dictionaryForKey:kAutoBeforeBoostKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (value) settings[identifier] = value;
    else [settings removeObjectForKey:identifier];
    [self.brightnessPreferences setObject:settings forKey:kAutoBeforeBoostKey];
}

- (BOOL)setAutoBrightnessEnabled:(BOOL)enabled {
    if (![self displayPreferenceID]) return NO;
    void *ds = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY);
    int (*setAuto)(unsigned int, bool) = dlsym(ds, "DisplayServicesEnableAmbientLightCompensation");
    // Writing DisplayBrightnessAuto directly can report success without changing it.
    // The request can return before its readback updates. Callers verify after
    // the transition, rather than rejecting a successful but asynchronous write.
    return setAuto && setAuto(self.displayID, enabled) == 0;
}

- (BOOL)setBaseBrightness:(float)brightness {
    if (![self displayPreferenceID]) return NO;
    void *ds = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY);
    int (*setBrightness)(unsigned int, float) = dlsym(ds, "DisplayServicesSetBrightness");
    return setBrightness && setBrightness(self.displayID, brightness) == 0;
}

- (void)afterBrightnessSettles:(dispatch_block_t)block {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 700 * NSEC_PER_MSEC), dispatch_get_main_queue(), block);
}

- (void)finishBrightnessChange:(NSString *)error {
    self.changingBrightness = NO;
    [self refresh:nil];
    if (error) [self showError:error];
}

- (void)finishAutoBrightnessChange:(BOOL)enabled savedPreference:(NSNumber *)saved error:(NSString *)error {
    NSString *identifier = [self displayPreferenceID];
    [self afterBrightnessSettles:^{
        if (!identifier || ![[self displayPreferenceID] isEqualToString:identifier]) {
            [self finishBrightnessChange:@"The display disconnected before Auto Brightness could be verified."];
            return;
        }
        double actual = [self numberProperty:kDisplayBrightnessAuto];
        if (!isfinite(actual) || actual < 0 || (actual > 0.5) != enabled) {
            [self finishBrightnessChange:@"Couldn’t verify Auto Brightness. Check its live setting and try again."];
            return;
        }
        [self saveAutoBrightnessBeforeBoost:saved];
        [self finishBrightnessChange:error];
    }];
}

- (void)changeBoost:(BOOL)enabled maximum:(BOOL)maximum {
    if (self.changingBrightness) return;
    NSString *identifier = [self displayPreferenceID];
    double autoBefore = [self numberProperty:kDisplayBrightnessAuto];
    double normalMax = [self numberProperty:kDisplayBrightnessMax];
    double auroraMax = [self numberProperty:kDisplayNitsMaxAurora];
    double oldFactor = [self numberProperty:kAuroraFactor];
    double oldSlider = [self numberProperty:@"DisplayServicesBrightness"];
    double target = normalMax > 0 ? auroraMax / normalMax : -1;
    if (!identifier || !isfinite(autoBefore) || autoBefore < 0 ||
        !isfinite(target) || target <= 1 || target > 2 ||
        !isfinite(oldFactor) || oldFactor < 1 ||
        !isfinite(oldSlider) || oldSlider < 0 || oldSlider > 1) {
        [self finishBrightnessChange:@"Couldn’t read the display’s brightness controls."];
        return;
    }
    NSNumber *savedAuto = [self autoBrightnessBeforeBoost];
    self.changingBrightness = YES;
    [self refresh:nil];
    if (enabled) {
        // Save before disabling so the previous setting survives an app restart.
        [self saveAutoBrightnessBeforeBoost:(autoBefore > 0.5 || !savedAuto) ? @(autoBefore > 0.5) : savedAuto];
        if (![self setAutoBrightnessEnabled:NO]) {
            BOOL restored = [self setAutoBrightnessEnabled:autoBefore > 0.5];
            if (restored) [self finishAutoBrightnessChange:autoBefore > 0.5 savedPreference:savedAuto
                error:@"Couldn’t turn off Auto Brightness. Boost was not applied."];
            else [self finishBrightnessChange:@"Couldn’t update Auto Brightness. Check its setting in System Settings."];
            return;
        }
    } else if (![self setAuroraFactor:1.0f]) {
        [self finishBrightnessChange:@"The display rejected the Aurora reset."];
        return;
    }

    // Auto Brightness can queue an Aurora-exit fade. Let that notification arrive
    // before applying manual boost; UI polling must not overwrite a pending click.
    [self afterBrightnessSettles:^{
        if (![[self displayPreferenceID] isEqualToString:identifier]) {
            [self finishBrightnessChange:@"The display disconnected. Reconnect it to finish changing brightness."];
            return;
        }
        if (!enabled) {
            if (savedAuto && ![self setAutoBrightnessEnabled:savedAuto.boolValue]) {
                [self finishBrightnessChange:@"Boost is off, but the previous Auto Brightness setting couldn’t be restored. Use the Auto Brightness control to retry."];
                return;
            }
            if (savedAuto) {
                [self finishAutoBrightnessChange:savedAuto.boolValue savedPreference:nil error:nil];
                return;
            }
            [self saveAutoBrightnessBeforeBoost:nil];
            [self finishBrightnessChange:nil];
            return;
        }
        double autoNow = [self numberProperty:kDisplayBrightnessAuto];
        BOOL succeeded = isfinite(autoNow) && autoNow >= 0 && autoNow <= 0.5;
        if (succeeded) succeeded = [self setBaseBrightness:maximum ? 1.0f : (float)oldSlider];
        if (succeeded) succeeded = [self setAuroraFactor:(float)target];
        if (!succeeded) {
            BOOL baseRestored = [self setBaseBrightness:(float)oldSlider];
            BOOL factorRestored = [self setAuroraFactor:(float)oldFactor];
            BOOL autoRestored = [self setAutoBrightnessEnabled:autoBefore > 0.5];
            NSString *error = baseRestored && factorRestored && autoRestored
                ? @"The display rejected the boost. Your previous brightness settings were restored."
                : @"The display rejected the boost and some settings couldn’t be restored. Check the brightness controls.";
            if (autoRestored) [self finishAutoBrightnessChange:autoBefore > 0.5 savedPreference:savedAuto error:error];
            else [self finishBrightnessChange:error];
            return;
        }
        [self afterBrightnessSettles:^{
            if (![[self displayPreferenceID] isEqualToString:identifier]) {
                [self finishBrightnessChange:@"The display disconnected while applying boost."];
                return;
            }
            double actualAuto = [self numberProperty:kDisplayBrightnessAuto];
            double actualFactor = [self numberProperty:kAuroraFactor];
            BOOL verified = isfinite(actualAuto) && actualAuto >= 0 && actualAuto <= 0.5 &&
                isfinite(actualFactor) && fabs(actualFactor - target) < 0.01;
            NSLog(@"Manual boost: auto=%.0f factor=%.6f verified=%d", actualAuto, actualFactor, verified);
            [self finishBrightnessChange:verified ? nil : @"macOS changed the requested boost. Check the live brightness controls."];
        }];
    }];
}

- (void)enableMaximum:(id)sender {
    (void)sender;
    [self changeBoost:YES maximum:YES];
}

- (void)toggleAurora:(id)sender {
    (void)sender;
    [self changeBoost:self.auroraSwitch.state == NSControlStateValueOn maximum:NO];
}

- (void)toggleAutoBrightness:(id)sender {
    (void)sender;
    if (self.changingBrightness) return;
    double actual = [self numberProperty:kDisplayBrightnessAuto];
    NSString *identifier = [self displayPreferenceID];
    if (!identifier || !isfinite(actual) || actual < 0) {
        [self finishBrightnessChange:@"Couldn’t read Auto Brightness."];
        return;
    }
    BOOL enable = actual <= 0.5;
    self.changingBrightness = YES;
    [self refresh:nil];
    // An explicit choice of automatic control ends manual boost.
    if (enable && ![self setAuroraFactor:1.0f]) {
        [self finishBrightnessChange:@"Couldn’t end manual boost. Auto Brightness was not changed."];
        return;
    }
    [self afterBrightnessSettles:^{
        if (![[self displayPreferenceID] isEqualToString:identifier]) {
            [self finishBrightnessChange:@"The display disconnected before Auto Brightness could be changed."];
            return;
        }
        if (![self setAutoBrightnessEnabled:enable]) {
            [self finishBrightnessChange:@"Couldn’t change Auto Brightness. Check its setting in System Settings."];
            return;
        }
        NSLog(@"Auto Brightness changed to %@", enable ? @"On" : @"Off");
        [self finishAutoBrightnessChange:enable savedPreference:nil error:nil];
    }];
}

- (void)refresh:(id)sender {
    (void)sender;
    if (![self displayPreferenceID]) {
        self.heroValue.stringValue = @"No display";
        self.stateLabel.stringValue = @"Display disconnected";
        self.stateLabel.textColor = NSColor.systemRedColor;
        self.factorValue.stringValue = @"Unavailable";
        self.ambientValue.stringValue = @"Unavailable";
        self.autoButton.title = @"Unavailable";
        self.autoButton.enabled = NO;
        self.auroraSwitch.enabled = NO;
        self.maximumItem.enabled = NO;
        return;
    }
    double physical = [self numberProperty:kNitsPhysical];
    double factor = [self numberProperty:kAuroraFactor];
    double normalMaximum = [self numberProperty:kDisplayBrightnessMax];
    double maximum = [self numberProperty:kDisplayNitsMaxAurora];
    double lux = [self numberProperty:kAggregatedLux];
    double autoBrightness = [self numberProperty:kDisplayBrightnessAuto];

    self.heroValue.stringValue = physical >= 0 ? [NSString stringWithFormat:@"%.0f nits", physical] : @"— nits";
    self.factorValue.stringValue = factor >= 0 ? [NSString stringWithFormat:@"%.6g×", factor] : @"Unavailable";
    self.ambientValue.stringValue = lux >= 0 ? [NSString stringWithFormat:@"%.0f lux", lux] : @"Unavailable";
    self.autoButton.title = autoBrightness > 0.5 ? @"On" : (autoBrightness >= 0 ? @"Off" : @"Unavailable");
    self.autoButton.accessibilityValue = self.autoButton.title;
    self.autoButton.enabled = autoBrightness >= 0 && !self.changingBrightness;
    BOOL boosted = factor > 1.001;
    BOOL maxed = maximum > 0 && physical >= maximum - 2 && boosted;
    double activeMaximum = boosted ? maximum : normalMaximum;
    NSString *ceiling = activeMaximum > 0 ? [NSString stringWithFormat:@"%.0f-nit ceiling", activeMaximum] : @"ceiling unavailable";
    self.stateLabel.stringValue = autoBrightness > 0.5 ? @"Automatic brightness" : maxed
        ? [NSString stringWithFormat:@"Boosted · %@", ceiling]
        : (boosted
            ? [NSString stringWithFormat:@"Boosted %.3g× · %@", factor, ceiling]
            : [NSString stringWithFormat:@"Normal behavior · %@", ceiling]);
    self.stateLabel.textColor = maxed ? NSColor.systemGreenColor : NSColor.secondaryLabelColor;
    if (!self.changingBrightness) self.auroraSwitch.state = boosted && autoBrightness >= 0 && autoBrightness <= 0.5
        ? NSControlStateValueOn : NSControlStateValueOff;
    self.auroraSwitch.enabled = factor >= 0 && maximum > 0 && autoBrightness >= 0 && !self.changingBrightness;
    self.maximumItem.enabled = maximum > 0 && autoBrightness >= 0 && !self.changingBrightness;
    self.maximumItem.title = [NSString stringWithFormat:@"Set to %.0f nits", maximum];
}

- (void)showError:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = self.displayName ?: @"Brightness Unlock";
    alert.informativeText = message;
    [alert runModal];
}
@end

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyAccessory;
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
