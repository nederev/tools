#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>

#import "SidecarController.h"

static NSString *const AppBundleID = @"com.nederev.SidecarReconnector";
static NSString *const TargetNameKey = @"targetName";
static NSString *const TargetIdentifierKey = @"targetIdentifier";
static NSString *const HotKeyCodeKey = @"hotKeyCode";
static NSString *const HotKeyModifiersKey = @"hotKeyModifiers";
static NSString *const PausedKey = @"paused";
static NSString *const LogPath = @"~/Library/Logs/SidecarReconnector.log";
static const UInt32 HotKeySignature = 0x53524331;
static const UInt32 ReconnectHotKeyID = 1;

// A click on the icon while the popover is open arrives just after the
// transient auto-dismiss; treat a click this soon after a close as "the click
// that closed it" and don't re-open. Reliable now that device discovery no
// longer blocks the main thread.
static const NSTimeInterval PopoverReopenGuard = 0.25;

typedef NS_ENUM(NSInteger, SRNotify) {
  SRNotifyNone = 0,     // silent (background wake/retry reconnects)
  SRNotifyFailureOnly,  // alert only on failure (global hotkey)
  SRNotifyAll,          // alert on success and failure (explicit user action)
};

typedef NS_ENUM(NSInteger, SRPanelStatusKind) {
  SRPanelStatusChecking,
  SRPanelStatusConnected,
  SRPanelStatusDisconnected,
  SRPanelStatusPaused,     // auto-reconnect suspended by the user
  SRPanelStatusAttention,  // not configured / not found / ambiguous / error
};

@class AppDelegate;
static AppDelegate *GlobalAppDelegate = nil;

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate, NSPopoverDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSMenu *statusMenu;
@property(nonatomic, strong) NSMenuItem *statusMenuItem;
@property(nonatomic, strong) NSMenuItem *targetMenuItem;
@property(nonatomic, strong) NSMenuItem *launchAtLoginItem;
@property(nonatomic, strong) NSMenuItem *pauseMenuItem;
@property(nonatomic, strong) NSPopover *popover;
@property(nonatomic, strong) NSDate *popoverClosedAt;
@property(nonatomic, strong) NSView *panelStatusPill;
@property(nonatomic, strong) NSTextField *panelStatusLabel;
@property(nonatomic, strong) NSTextField *panelSelectedLabel;
@property(nonatomic, strong) NSTextField *hotKeyLabel;
@property(nonatomic, strong) NSPopUpButton *targetPopup;
@property(nonatomic, strong) NSButton *recordHotKeyButton;
@property(nonatomic, strong) NSButton *launchAtLoginCheckbox;
@property(nonatomic, strong) NSSwitch *pauseSwitch;
@property(nonatomic, strong) SidecarController *controller;
@property(nonatomic, strong) NSMutableArray<NSTimer *> *retryTimers;
@property(nonatomic, strong) id localKeyMonitor;
@property(nonatomic, assign) EventHotKeyRef reconnectHotKeyRef;
@property(nonatomic, assign) BOOL recordingHotKey;
@property(nonatomic, assign) BOOL reconnectRunning;
- (void)reconnectFromHotKey;
@end

static OSStatus ReconnectHotKeyHandler(EventHandlerCallRef nextHandler, EventRef event, void *userData) {
  (void)nextHandler;
  (void)event;
  (void)userData;
  [GlobalAppDelegate reconnectFromHotKey];
  return noErr;
}

@implementation AppDelegate

- (NSString *)appVersion {
  NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
  return version.length ? version : @"0.1";
}

- (NSString *)appTitle {
  return [NSString stringWithFormat:@"Sidecar Reconnector v%@", [self appVersion]];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  (void)notification;
  GlobalAppDelegate = self;
  // Menu-bar-only app: the control panel is a popover off the status item, so a
  // Dock icon adds nothing. LSUIElement already does this at launch; assert it
  // here too in case the bundle plist is ever out of sync.
  [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
  NSString *iconPath = [[NSBundle mainBundle] pathForResource:@"SidecarReconnectorIcon" ofType:@"png"];
  NSImage *iconImage = iconPath.length ? [[NSImage alloc] initWithContentsOfFile:iconPath] : nil;
  if (iconImage != nil) {
    [NSApp setApplicationIconImage:iconImage];
  }
  self.controller = [SidecarController new];
  self.retryTimers = [NSMutableArray array];
  [self setupStatusItem];
  [self installHotKeyHandler];
  [self registerReconnectHotKey];
  [self registerNotifications];
  [self log:[NSString stringWithFormat:@"%@ app loaded", [self appTitle]]];
  // Live in the menu bar: don't pop the panel on launch — it opens on click.
  [self refreshAsyncAllowAutoSelect:YES];
}

- (void)setupStatusItem {
  self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];

  // On a notched Mac with a full menu bar, a newly-added status item gets parked
  // under the notch (physically invisible). Seed the preferred position to 0
  // (rightmost third-party slot, next to Control Center, clear of the notch)
  // only on first run; afterwards the system persists wherever the user
  // Cmd-drags it, so we don't fight their choice on relaunch.
  NSString *autosave = @"SidecarReconnectorStatusItem";
  NSString *posKey = [@"NSStatusItem Preferred Position " stringByAppendingString:autosave];
  if ([[NSUserDefaults standardUserDefaults] objectForKey:posKey] == nil) {
    [[NSUserDefaults standardUserDefaults] setDouble:0.0 forKey:posKey];
  }
  self.statusItem.autosaveName = autosave;

  NSStatusBarButton *button = self.statusItem.button;
  button.toolTip = [self appTitle];

  // Prefer a compact template glyph; fall back to text if the SF Symbol is
  // unavailable. A template image renders correctly in light/dark menu bars and
  // is far less likely to be pushed off-screen (notch/crowding) than wide text.
  NSImage *icon = nil;
  if (@available(macOS 11.0, *)) {
    icon = [NSImage imageWithSystemSymbolName:@"rectangle.connected.to.line.below"
                    accessibilityDescription:@"Sidecar Reconnector"];
    if (!icon) icon = [NSImage imageWithSystemSymbolName:@"display" accessibilityDescription:@"Sidecar Reconnector"];
  }
  if (icon) {
    icon.template = YES;
    button.image = icon;
    button.imagePosition = NSImageOnly;
  } else {
    button.title = @"◰";
    button.font = [NSFont monospacedSystemFontOfSize:13.0 weight:NSFontWeightSemibold];
  }

  // Left-click opens the control panel; right-click (or control-click) shows the
  // menu. Driving clicks through an action (rather than assigning statusItem.menu)
  // is what lets a left-click open the panel directly.
  button.target = self;
  button.action = @selector(statusItemClicked:);
  [button sendActionOn:(NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp)];
  self.statusItem.visible = YES;
  [self log:[NSString stringWithFormat:@"status item created icon=%@ length=variable click=action",
                                       icon ? @"symbol" : @"text"]];

  NSMenu *menu = [[NSMenu alloc] initWithTitle:[self appTitle]];
  menu.delegate = self;

  self.statusMenuItem = [[NSMenuItem alloc] initWithTitle:@"Status: Checking..." action:nil keyEquivalent:@""];
  self.statusMenuItem.enabled = NO;
  [menu addItem:self.statusMenuItem];
  [menu addItem:[NSMenuItem separatorItem]];

  [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Reconnect Now" action:@selector(reconnectNow:) keyEquivalent:@"r"]];

  // Checkmark when paused; one click here pauses without opening the panel.
  self.pauseMenuItem = [[NSMenuItem alloc] initWithTitle:@"Pause" action:@selector(togglePause:) keyEquivalent:@""];
  [menu addItem:self.pauseMenuItem];

  self.targetMenuItem = [[NSMenuItem alloc] initWithTitle:@"Target" action:nil keyEquivalent:@""];
  self.targetMenuItem.submenu = [[NSMenu alloc] initWithTitle:@"Target"];
  [menu addItem:self.targetMenuItem];

  self.launchAtLoginItem = [[NSMenuItem alloc] initWithTitle:@"Launch at Login" action:@selector(toggleLaunchAtLogin:) keyEquivalent:@""];
  [menu addItem:self.launchAtLoginItem];

  [menu addItem:[NSMenuItem separatorItem]];
  [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Show Control Panel" action:@selector(showControlPanel:) keyEquivalent:@"p"]];
  [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Open Log" action:@selector(openLog:) keyEquivalent:@"l"]];
  [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(quit:) keyEquivalent:@"q"]];

  // Held for right-click; not assigned to statusItem.menu so left-clicks reach
  // our action (see statusItemClicked:).
  self.statusMenu = menu;
}

- (void)statusItemClicked:(id)sender {
  (void)sender;
  NSEvent *event = [NSApp currentEvent];
  BOOL secondary = event && ((event.type == NSEventTypeRightMouseUp) ||
                             (event.modifierFlags & NSEventModifierFlagControl));
  if (secondary) {
    [self popUpStatusMenu];
  } else {
    [self togglePopover];
  }
}

- (void)popUpStatusMenu {
  if (!self.statusMenu) return;
  // Temporarily attach the menu so the status item pops it under the button,
  // then detach so subsequent left-clicks keep triggering the action.
  self.statusItem.menu = self.statusMenu;
  [self.statusItem.button performClick:nil];
  self.statusItem.menu = nil;
}

- (SRPanelStatusKind)statusKindForText:(NSString *)status {
  // Check "Disconnected" before "Connected": the word "disconnected" contains
  // the substring "connected".
  if ([status localizedCaseInsensitiveContainsString:@"Paused"]) return SRPanelStatusPaused;
  if ([status localizedCaseInsensitiveContainsString:@"Checking"]) return SRPanelStatusChecking;
  if ([status localizedCaseInsensitiveContainsString:@"Disconnected"]) return SRPanelStatusDisconnected;
  if ([status localizedCaseInsensitiveContainsString:@"Connected"]) return SRPanelStatusConnected;
  return SRPanelStatusAttention;
}

- (void)updateStatusItemForStatus:(NSString *)status {
  NSStatusBarButton *button = self.statusItem.button;
  button.toolTip = status.length ? status : [self appTitle];
  SRPanelStatusKind kind = [self statusKindForText:status];
  // Paused: dim the glyph so the menu bar shows the app is dormant (and no red).
  button.alphaValue = (kind == SRPanelStatusPaused) ? 0.45 : 1.0;
  button.contentTintColor = (kind == SRPanelStatusDisconnected || kind == SRPanelStatusAttention)
                                ? [NSColor systemRedColor]
                                : nil;
}

- (void)registerNotifications {
  NSNotificationCenter *workspaceCenter = [[NSWorkspace sharedWorkspace] notificationCenter];
  [workspaceCenter addObserver:self selector:@selector(workspaceDidWake:) name:NSWorkspaceDidWakeNotification object:nil];
  [workspaceCenter addObserver:self selector:@selector(workspaceScreensDidWake:) name:NSWorkspaceScreensDidWakeNotification object:nil];
  [workspaceCenter addObserver:self selector:@selector(workspaceSessionDidBecomeActive:) name:NSWorkspaceSessionDidBecomeActiveNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(screenParametersChanged:) name:NSApplicationDidChangeScreenParametersNotification object:nil];
}

- (void)menuWillOpen:(NSMenu *)menu {
  (void)menu;
  [self refreshAsyncAllowAutoSelect:NO];
  [self syncLaunchAtLoginControls];
  [self syncPauseControls];
}

- (NSString *)expandedLogPath {
  return [LogPath stringByExpandingTildeInPath];
}

- (void)log:(NSString *)message {
  NSString *line = [NSString stringWithFormat:@"%@ %@\n", [self timestamp], message ? message : @""];
  NSString *path = [self expandedLogPath];
  [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
  NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
  if (!handle) {
    [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return;
  }
  [handle seekToEndOfFile];
  [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
  [handle closeFile];
}

- (NSString *)timestamp {
  NSDateFormatter *formatter = [NSDateFormatter new];
  formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
  formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
  formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
  return [formatter stringFromDate:[NSDate date]];
}

- (NSString *)selectedTargetName {
  return [[NSUserDefaults standardUserDefaults] stringForKey:TargetNameKey];
}

- (NSString *)selectedTargetIdentifier {
  return [[NSUserDefaults standardUserDefaults] stringForKey:TargetIdentifierKey];
}

- (UInt32)hotKeyCode {
  NSNumber *value = [[NSUserDefaults standardUserDefaults] objectForKey:HotKeyCodeKey];
  return value ? value.unsignedIntValue : kVK_ANSI_U;
}

- (UInt32)hotKeyModifiers {
  NSNumber *value = [[NSUserDefaults standardUserDefaults] objectForKey:HotKeyModifiersKey];
  return value ? value.unsignedIntValue : (cmdKey | optionKey | controlKey);
}

- (SRCTarget *)selectedTarget {
  return [SRCTarget targetWithName:[self selectedTargetName] identifier:[self selectedTargetIdentifier]];
}

- (BOOL)hasSelectedTarget {
  return [self selectedTargetName].length || [self selectedTargetIdentifier].length;
}

- (void)setSelectedDevice:(SRCDevice *)device {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  if (device.name.length) [defaults setObject:device.name forKey:TargetNameKey];
  if (device.identifier.length) [defaults setObject:device.identifier forKey:TargetIdentifierKey];
  [defaults synchronize];
  [self log:[NSString stringWithFormat:@"selected target %@", [SidecarController logLineForDevice:device prefix:@"target"]]];
  [self updateSelectedTargetLabel];
}

- (void)clearSelectedTarget:(id)sender {
  (void)sender;
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults removeObjectForKey:TargetNameKey];
  [defaults removeObjectForKey:TargetIdentifierKey];
  [defaults synchronize];
  [self log:@"cleared target selection"];
  [self updateSelectedTargetLabel];
  [self refreshAsyncAllowAutoSelect:NO];
}

- (void)installHotKeyHandler {
  EventTypeSpec eventType = { .eventClass = kEventClassKeyboard, .eventKind = kEventHotKeyPressed };
  InstallApplicationEventHandler(&ReconnectHotKeyHandler, 1, &eventType, NULL, NULL);
}

- (void)registerReconnectHotKey {
  if (self.reconnectHotKeyRef) {
    UnregisterEventHotKey(self.reconnectHotKeyRef);
    self.reconnectHotKeyRef = NULL;
  }

  EventHotKeyID hotKeyID = { .signature = HotKeySignature, .id = ReconnectHotKeyID };
  OSStatus status = RegisterEventHotKey([self hotKeyCode],
                                        [self hotKeyModifiers],
                                        hotKeyID,
                                        GetApplicationEventTarget(),
                                        0,
                                        &_reconnectHotKeyRef);
  if (status == noErr) {
    [self log:[NSString stringWithFormat:@"registered hotkey %@", [self hotKeyDisplayString]]];
  } else {
    [self log:[NSString stringWithFormat:@"hotkey registration failed status=%d", status]];
  }
  [self updateHotKeyLabel];
}

- (NSString *)keyNameForCode:(UInt32)keyCode {
  NSDictionary<NSNumber *, NSString *> *names = @{
    @(kVK_ANSI_A): @"A", @(kVK_ANSI_B): @"B", @(kVK_ANSI_C): @"C", @(kVK_ANSI_D): @"D",
    @(kVK_ANSI_E): @"E", @(kVK_ANSI_F): @"F", @(kVK_ANSI_G): @"G", @(kVK_ANSI_H): @"H",
    @(kVK_ANSI_I): @"I", @(kVK_ANSI_J): @"J", @(kVK_ANSI_K): @"K", @(kVK_ANSI_L): @"L",
    @(kVK_ANSI_M): @"M", @(kVK_ANSI_N): @"N", @(kVK_ANSI_O): @"O", @(kVK_ANSI_P): @"P",
    @(kVK_ANSI_Q): @"Q", @(kVK_ANSI_R): @"R", @(kVK_ANSI_S): @"S", @(kVK_ANSI_T): @"T",
    @(kVK_ANSI_U): @"U", @(kVK_ANSI_V): @"V", @(kVK_ANSI_W): @"W", @(kVK_ANSI_X): @"X",
    @(kVK_ANSI_Y): @"Y", @(kVK_ANSI_Z): @"Z", @(kVK_ANSI_0): @"0", @(kVK_ANSI_1): @"1",
    @(kVK_ANSI_2): @"2", @(kVK_ANSI_3): @"3", @(kVK_ANSI_4): @"4", @(kVK_ANSI_5): @"5",
    @(kVK_ANSI_6): @"6", @(kVK_ANSI_7): @"7", @(kVK_ANSI_8): @"8", @(kVK_ANSI_9): @"9",
    @(kVK_Space): @"Space",
    @(kVK_Return): @"Return",
    @(kVK_Escape): @"Esc",
  };
  NSString *name = names[@(keyCode)];
  return name ? name : [NSString stringWithFormat:@"Key %@", @(keyCode)];
}

- (NSString *)hotKeyDisplayString {
  UInt32 modifiers = [self hotKeyModifiers];
  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  if (modifiers & controlKey) [parts addObject:@"Ctrl"];
  if (modifiers & optionKey) [parts addObject:@"Option"];
  if (modifiers & shiftKey) [parts addObject:@"Shift"];
  if (modifiers & cmdKey) [parts addObject:@"Cmd"];
  [parts addObject:[self keyNameForCode:[self hotKeyCode]]];
  return [parts componentsJoinedByString:@" + "];
}

- (UInt32)carbonModifiersFromEvent:(NSEvent *)event {
  NSEventModifierFlags flags = event.modifierFlags;
  UInt32 modifiers = 0;
  if (flags & NSEventModifierFlagControl) modifiers |= controlKey;
  if (flags & NSEventModifierFlagOption) modifiers |= optionKey;
  if (flags & NSEventModifierFlagShift) modifiers |= shiftKey;
  if (flags & NSEventModifierFlagCommand) modifiers |= cmdKey;
  return modifiers;
}

- (void)updateHotKeyLabel {
  if (!self.hotKeyLabel) return;
  self.hotKeyLabel.stringValue = self.recordingHotKey ? @"Press new shortcut..." : [self hotKeyDisplayString];
}

- (void)startRecordingHotKey:(id)sender {
  (void)sender;
  self.recordingHotKey = YES;
  [self updateHotKeyLabel];
  [self setButton:self.recordHotKeyButton
            title:@"…"
             font:[NSFont systemFontOfSize:15.0 weight:NSFontWeightSemibold]
            color:[NSColor colorWithWhite:0.92 alpha:1.0]];

  if (self.localKeyMonitor) [NSEvent removeMonitor:self.localKeyMonitor];
  __weak AppDelegate *weakSelf = self;
  self.localKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
    [weakSelf finishRecordingHotKeyWithEvent:event];
    return nil;
  }];
}

- (void)finishRecordingHotKeyWithEvent:(NSEvent *)event {
  UInt32 modifiers = [self carbonModifiersFromEvent:event];
  if (modifiers == 0 || event.keyCode == kVK_Escape) {
    [self stopRecordingHotKey];
    return;
  }

  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setObject:@(event.keyCode) forKey:HotKeyCodeKey];
  [defaults setObject:@(modifiers) forKey:HotKeyModifiersKey];
  [defaults synchronize];
  [self log:[NSString stringWithFormat:@"hotkey changed %@", [self hotKeyDisplayString]]];
  [self stopRecordingHotKey];
  [self registerReconnectHotKey];
}

- (void)stopRecordingHotKey {
  if (self.localKeyMonitor) {
    [NSEvent removeMonitor:self.localKeyMonitor];
    self.localKeyMonitor = nil;
  }
  self.recordingHotKey = NO;
  [self updateHotKeyLabel];
  [self setButton:self.recordHotKeyButton
            title:@"✎"
             font:[NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold]
            color:[NSColor colorWithWhite:0.92 alpha:1.0]];
}

- (NSTextField *)labelWithFrame:(NSRect)frame
                           text:(NSString *)text
                           font:(NSFont *)font
                          color:(NSColor *)color {
  NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
  label.editable = NO;
  label.selectable = NO;
  label.bezeled = NO;
  label.drawsBackground = NO;
  label.font = font;
  label.textColor = color;
  label.stringValue = text ? text : @"";
  return label;
}

- (void)setButton:(NSButton *)button title:(NSString *)title font:(NSFont *)font color:(NSColor *)textColor {
  button.font = font;
  NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
  style.alignment = NSTextAlignmentCenter;
  button.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{
    NSForegroundColorAttributeName: textColor,
    NSFontAttributeName: font,
    NSParagraphStyleAttributeName: style,
  }];
}

- (NSButton *)buttonWithTitle:(NSString *)title
                        frame:(NSRect)frame
                       action:(SEL)action
                    fillColor:(NSColor *)fillColor
                    textColor:(NSColor *)textColor {
  NSButton *button = [NSButton buttonWithTitle:@"" target:self action:action];
  button.frame = frame;
  button.bordered = NO;
  button.wantsLayer = YES;
  button.layer.cornerRadius = 10.0;
  button.layer.backgroundColor = fillColor.CGColor;
  [self setButton:button title:title font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold] color:textColor];
  return button;
}

- (NSView *)roundedSurfaceWithFrame:(NSRect)frame color:(NSColor *)color radius:(CGFloat)radius {
  NSView *surface = [[NSView alloc] initWithFrame:frame];
  surface.wantsLayer = YES;
  surface.layer.cornerRadius = radius;
  surface.layer.backgroundColor = color.CGColor;
  surface.layer.masksToBounds = YES;
  return surface;
}

- (NSView *)borderedSurfaceWithFrame:(NSRect)frame
                                color:(NSColor *)color
                               radius:(CGFloat)radius
                          borderColor:(NSColor *)borderColor
                          borderWidth:(CGFloat)borderWidth {
  NSView *surface = [self roundedSurfaceWithFrame:frame color:color radius:radius];
  surface.layer.borderColor = borderColor.CGColor;
  surface.layer.borderWidth = borderWidth;
  return surface;
}

- (NSView *)separatorWithFrame:(NSRect)frame {
  return [self roundedSurfaceWithFrame:frame color:[NSColor colorWithWhite:1.0 alpha:0.12] radius:0.0];
}

- (void)updatePanelStatusAppearance:(NSString *)status {
  if (!self.panelStatusLabel) return;

  NSString *label;
  NSColor *background;
  NSColor *foreground = [NSColor colorWithWhite:0.82 alpha:1.0];
  switch ([self statusKindForText:status]) {
    case SRPanelStatusConnected:
      label = @"Connected";
      background = [NSColor colorWithRed:0.28 green:0.78 blue:0.36 alpha:1.0];
      break;
    case SRPanelStatusDisconnected:
      label = @"Disconnected";
      background = [NSColor colorWithRed:0.90 green:0.28 blue:0.28 alpha:1.0];
      break;
    case SRPanelStatusChecking:
      label = @"Checking";
      background = [NSColor colorWithRed:0.36 green:0.54 blue:0.88 alpha:1.0];
      break;
    case SRPanelStatusPaused:
      label = @"Paused";
      background = [NSColor colorWithRed:0.85 green:0.62 blue:0.20 alpha:1.0];
      break;
    case SRPanelStatusAttention:
      label = @"Needs attention";
      background = [NSColor colorWithRed:0.36 green:0.27 blue:0.11 alpha:1.0];
      foreground = [NSColor colorWithWhite:0.78 alpha:1.0];
      break;
  }

  self.panelStatusLabel.stringValue = label;
  self.panelStatusLabel.textColor = foreground;
  self.panelStatusPill.layer.backgroundColor = background.CGColor;
}

- (void)ensurePopover {
  if (self.popover) return;

  NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 236)];
  {
    content.wantsLayer = YES;
    content.layer.backgroundColor = [NSColor colorWithRed:0.08 green:0.09 blue:0.10 alpha:1.0].CGColor;

    // Faint version marker, top-right corner.
    NSTextField *versionLabel = [self labelWithFrame:NSMakeRect(360, 215, 118, 13)
                                                text:[NSString stringWithFormat:@"v%@", [self appVersion]]
                                                font:[NSFont systemFontOfSize:9.0 weight:NSFontWeightRegular]
                                               color:[NSColor colorWithWhite:1.0 alpha:0.22]];
    versionLabel.alignment = NSTextAlignmentRight;
    [content addSubview:versionLabel];

    CGFloat left = 22.0;
    CGFloat labelWidth = 92.0;
    CGFloat controlX = 128.0;
    CGFloat controlWidth = 300.0;
    CGFloat iconButtonX = 448.0;
    CGFloat iconButtonSize = 30.0;

    NSView *icon = [self roundedSurfaceWithFrame:NSMakeRect(left, 166, 42, 42)
                                           color:[NSColor colorWithRed:0.12 green:0.23 blue:0.48 alpha:1.0]
                                          radius:9.0];
    [content addSubview:icon];
    NSColor *iconStroke = [NSColor colorWithRed:0.72 green:0.82 blue:1.0 alpha:0.70];
    [icon addSubview:[self borderedSurfaceWithFrame:NSMakeRect(10, 11, 17, 21)
                                              color:[NSColor clearColor]
                                             radius:3.5
                                        borderColor:iconStroke
                                        borderWidth:1.4]];
    [icon addSubview:[self borderedSurfaceWithFrame:NSMakeRect(21, 10, 16, 17)
                                              color:[NSColor colorWithRed:0.12 green:0.23 blue:0.48 alpha:1.0]
                                             radius:3.5
                                        borderColor:iconStroke
                                        borderWidth:1.4]];

    self.panelSelectedLabel = [self labelWithFrame:NSMakeRect(86, 187, 248, 20)
                                             text:@"Selected: none"
                                             font:[NSFont systemFontOfSize:15.0 weight:NSFontWeightBold]
                                            color:[NSColor colorWithWhite:0.94 alpha:1.0]];
    [content addSubview:self.panelSelectedLabel];

    self.panelStatusPill = [self roundedSurfaceWithFrame:NSMakeRect(86, 174, 8, 8)
                                                   color:[NSColor colorWithRed:0.36 green:0.54 blue:0.88 alpha:1.0]
                                                  radius:4.0];
    [content addSubview:self.panelStatusPill];

    self.panelStatusLabel = [self labelWithFrame:NSMakeRect(98, 169, 164, 16)
                                            text:@"Checking"
                                            font:[NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium]
                                           color:[NSColor colorWithWhite:0.82 alpha:1.0]];
    [content addSubview:self.panelStatusLabel];

    NSButton *reconnect = [self buttonWithTitle:@"↻"
                                          frame:NSMakeRect(iconButtonX, 174, iconButtonSize, iconButtonSize)
                                         action:@selector(reconnectNow:)
                                      fillColor:[NSColor colorWithRed:0.08 green:0.38 blue:0.72 alpha:1.0]
                                      textColor:[NSColor whiteColor]];
    [self setButton:reconnect title:@"↻" font:[NSFont systemFontOfSize:17.0 weight:NSFontWeightSemibold] color:[NSColor whiteColor]];
    reconnect.toolTip = @"Reconnect Now";
    [content addSubview:reconnect];

    // Master Pause toggle: suspends automatic reconnects (manual still works).
    NSTextField *pauseLabel = [self labelWithFrame:NSMakeRect(338, 169, 52, 16)
                                              text:@"Pause"
                                              font:[NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium]
                                             color:[NSColor colorWithWhite:0.74 alpha:1.0]];
    pauseLabel.alignment = NSTextAlignmentRight;
    [content addSubview:pauseLabel];

    self.pauseSwitch = [[NSSwitch alloc] initWithFrame:NSMakeRect(396, 167, 38, 22)];
    self.pauseSwitch.target = self;
    self.pauseSwitch.action = @selector(togglePause:);
    self.pauseSwitch.toolTip = @"Pause auto-reconnect (app keeps running)";
    [content addSubview:self.pauseSwitch];

    [content addSubview:[self separatorWithFrame:NSMakeRect(left, 148, 456, 1)]];

    NSTextField *targetLabel = [self labelWithFrame:NSMakeRect(left, 112, labelWidth, 20)
                                              text:@"Target"
                                              font:[NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium]
                                             color:[NSColor colorWithWhite:0.78 alpha:1.0]];
    [content addSubview:targetLabel];

    self.targetPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(controlX, 107, controlWidth, 28) pullsDown:NO];
    self.targetPopup.target = self;
    self.targetPopup.action = @selector(choosePanelTarget:);
    self.targetPopup.controlSize = NSControlSizeRegular;
    self.targetPopup.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightMedium];
    [content addSubview:self.targetPopup];

    NSButton *targets = [self buttonWithTitle:@"↻"
                                        frame:NSMakeRect(iconButtonX, 107, iconButtonSize, 28)
                                       action:@selector(refreshTargetsMenu:)
                                    fillColor:[NSColor colorWithWhite:0.19 alpha:1.0]
                                    textColor:[NSColor colorWithWhite:0.92 alpha:1.0]];
    [self setButton:targets title:@"↻" font:[NSFont systemFontOfSize:15.0 weight:NSFontWeightSemibold] color:[NSColor colorWithWhite:0.92 alpha:1.0]];
    targets.toolTip = @"Refresh Targets";
    [content addSubview:targets];

    [content addSubview:[self separatorWithFrame:NSMakeRect(left, 87, 456, 1)]];

    NSTextField *hotKeyTitle = [self labelWithFrame:NSMakeRect(left, 51, labelWidth, 20)
                                               text:@"Hotkey"
                                               font:[NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium]
                                              color:[NSColor colorWithWhite:0.78 alpha:1.0]];
    [content addSubview:hotKeyTitle];

    NSView *hotKeySurface = [self borderedSurfaceWithFrame:NSMakeRect(controlX, 46, controlWidth, 28)
                                                     color:[NSColor colorWithWhite:0.14 alpha:1.0]
                                                    radius:7.0
                                               borderColor:[NSColor colorWithWhite:1.0 alpha:0.08]
                                               borderWidth:1.0];
    [content addSubview:hotKeySurface];

    self.hotKeyLabel = [self labelWithFrame:NSMakeRect(controlX + 11, 52, controlWidth - 22, 17)
                                       text:[self hotKeyDisplayString]
                                       font:[NSFont systemFontOfSize:12.5 weight:NSFontWeightMedium]
                                      color:[NSColor colorWithWhite:0.88 alpha:1.0]];
    [content addSubview:self.hotKeyLabel];

    self.recordHotKeyButton = [self buttonWithTitle:@"✎"
                                              frame:NSMakeRect(iconButtonX, 46, iconButtonSize, 28)
                                             action:@selector(startRecordingHotKey:)
                                          fillColor:[NSColor colorWithWhite:0.19 alpha:1.0]
                                          textColor:[NSColor colorWithWhite:0.92 alpha:1.0]];
    [self setButton:self.recordHotKeyButton title:@"✎" font:[NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold] color:[NSColor colorWithWhite:0.92 alpha:1.0]];
    self.recordHotKeyButton.toolTip = @"Change Hotkey";
    [content addSubview:self.recordHotKeyButton];

    [content addSubview:[self separatorWithFrame:NSMakeRect(0, 36, 500, 1)]];

    self.launchAtLoginCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(left, 7, 200, 24)];
    self.launchAtLoginCheckbox.buttonType = NSButtonTypeSwitch;
    self.launchAtLoginCheckbox.title = @"Launch at login";
    self.launchAtLoginCheckbox.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium];
    self.launchAtLoginCheckbox.target = self;
    self.launchAtLoginCheckbox.action = @selector(toggleLaunchAtLogin:);
    self.launchAtLoginCheckbox.toolTip = @"Start Sidecar Reconnector when you log in";
    [content addSubview:self.launchAtLoginCheckbox];

    NSButton *logButton = [self buttonWithTitle:@"Open Log"
                                          frame:NSMakeRect(304, 8, 82, 24)
                                         action:@selector(openLog:)
                                      fillColor:[NSColor colorWithWhite:0.18 alpha:1.0]
                                      textColor:[NSColor colorWithWhite:0.90 alpha:1.0]];
    [content addSubview:logButton];

    NSButton *quitButton = [self buttonWithTitle:@"Quit"
                                           frame:NSMakeRect(396, 8, 82, 24)
                                          action:@selector(quit:)
                                       fillColor:[NSColor colorWithWhite:0.18 alpha:1.0]
                                       textColor:[NSColor colorWithWhite:0.72 alpha:1.0]];
    [content addSubview:quitButton];
  }

  NSViewController *panelVC = [[NSViewController alloc] init];
  panelVC.view = content;

  self.popover = [[NSPopover alloc] init];
  self.popover.contentViewController = panelVC;
  self.popover.contentSize = NSMakeSize(500, 236);
  self.popover.behavior = NSPopoverBehaviorTransient;  // auto-dismiss on outside click
  self.popover.animates = YES;
  self.popover.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
  self.popover.delegate = self;
}

- (void)popoverDidClose:(NSNotification *)notification {
  (void)notification;
  self.popoverClosedAt = [NSDate date];
}

// Opens the panel as a popover hanging off the menu-bar item (Rectangle-style).
- (void)showControlPanel:(id)sender {
  (void)sender;
  [self ensurePopover];
  [self updateSelectedTargetLabel];
  [self syncLaunchAtLoginControls];
  [self syncPauseControls];
  [self refreshAsyncAllowAutoSelect:NO];

  NSStatusBarButton *button = self.statusItem.button;
  if (button && !self.popover.isShown) {
    self.statusItem.visible = YES;
    [self.popover showRelativeToRect:button.bounds ofView:button preferredEdge:NSRectEdgeMinY];
  }
  // Accessory apps need an explicit activate so the popover takes key focus
  // (text fields, hotkey recording, button clicks).
  [NSApp activateIgnoringOtherApps:YES];
  [self log:@"control panel shown (popover)"];
}

- (void)togglePopover {
  [self ensurePopover];
  if (self.popover.isShown) {
    [self.popover performClose:nil];
    [self log:@"control panel closed (popover)"];
    return;
  }
  // Clicking the icon while the popover is open first triggers the transient
  // auto-dismiss (popoverDidClose), then this action. Without this guard we'd
  // immediately re-open it.
  if (self.popoverClosedAt && [[NSDate date] timeIntervalSinceDate:self.popoverClosedAt] < PopoverReopenGuard) {
    return;
  }
  [self showControlPanel:nil];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
  (void)sender;
  (void)flag;
  [self showControlPanel:nil];
  return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
  (void)notification;
  if (self.reconnectHotKeyRef) {
    UnregisterEventHotKey(self.reconnectHotKeyRef);
    self.reconnectHotKeyRef = NULL;
  }
  if (self.localKeyMonitor) {
    [NSEvent removeMonitor:self.localKeyMonitor];
    self.localKeyMonitor = nil;
  }
}

- (void)updateSelectedTargetLabel {
  if (!self.panelSelectedLabel) return;
  NSString *name = [self selectedTargetName];
  NSString *identifier = [self selectedTargetIdentifier];
  // Show the friendly name; the raw identifier is noise next to it. Fall back to
  // the identifier only when there's no name.
  if (name.length) {
    self.panelSelectedLabel.stringValue = name;
  } else if (identifier.length) {
    self.panelSelectedLabel.stringValue = [NSString stringWithFormat:@"ID %@", identifier];
  } else {
    self.panelSelectedLabel.stringValue = @"No target selected";
  }
}

- (void)chooseTarget:(NSMenuItem *)sender {
  SRCDevice *device = sender.representedObject;
  if (![device isKindOfClass:[SRCDevice class]]) return;
  [self setSelectedDevice:device];
  [self refreshAsyncAllowAutoSelect:NO];
}

- (void)choosePanelTarget:(NSPopUpButton *)sender {
  SRCDevice *device = sender.selectedItem.representedObject;
  if (![device isKindOfClass:[SRCDevice class]]) return;
  [self setSelectedDevice:device];
  [self refreshAsyncAllowAutoSelect:NO];
}

// Discovery does blocking XPC, so it always runs off the main thread; the UI is
// updated back on main from the single fetched device list (targets + status).
- (void)refreshAsyncAllowAutoSelect:(BOOL)allowAutoSelect {
  self.statusMenuItem.title = @"Status: Checking...";
  [self updatePanelStatusAppearance:@"Status: Checking..."];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    NSError *error = nil;
    NSArray<SRCDevice *> *devices = [self.controller listDevicesWithError:&error];
    dispatch_async(dispatch_get_main_queue(), ^{
      [self applyTargetDevices:devices error:error allowAutoSelect:allowAutoSelect];
      [self applyStatusFromDevices:devices error:error];
    });
  });
}

- (void)applyTargetDevices:(NSArray<SRCDevice *> *)devices error:(NSError *)error allowAutoSelect:(BOOL)allowAutoSelect {
  NSMenu *targetMenu = [[NSMenu alloc] initWithTitle:@"Target"];
  [targetMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Refresh Targets" action:@selector(refreshTargetsMenu:) keyEquivalent:@""]];
  if (self.targetPopup) {
    [self.targetPopup removeAllItems];
  }

  if (error) {
    NSMenuItem *errorItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Error: %@", error.localizedDescription] action:nil keyEquivalent:@""];
    errorItem.enabled = NO;
    [targetMenu addItem:errorItem];
    if (self.targetPopup) {
      [self.targetPopup addItemWithTitle:@"Error loading devices"];
      self.targetPopup.enabled = NO;
    }
  } else {
    NSMutableArray<SRCDevice *> *displayDevices = [NSMutableArray array];
    for (SRCDevice *device in devices) {
      if (device.offersDisplay) [displayDevices addObject:device];
    }

    if (allowAutoSelect && ![self hasSelectedTarget]) {
      NSMutableArray<SRCDevice *> *connectedDisplayDevices = [NSMutableArray array];
      for (SRCDevice *device in displayDevices) {
        if (device.connected) [connectedDisplayDevices addObject:device];
      }
      if (connectedDisplayDevices.count == 1) {
        [self setSelectedDevice:connectedDisplayDevices.firstObject];
      } else if (displayDevices.count == 1) {
        [self setSelectedDevice:displayDevices.firstObject];
      } else {
        [self log:[NSString stringWithFormat:@"target auto-select skipped displayCandidates=%lu connectedDisplayCandidates=%lu",
                   (unsigned long)displayDevices.count,
                   (unsigned long)connectedDisplayDevices.count]];
      }
    }

    if (displayDevices.count == 0) {
      NSMenuItem *emptyItem = [[NSMenuItem alloc] initWithTitle:@"No Sidecar devices found" action:nil keyEquivalent:@""];
      emptyItem.enabled = NO;
      [targetMenu addItem:emptyItem];
      if (self.targetPopup) {
        [self.targetPopup addItemWithTitle:@"No Sidecar devices found"];
        self.targetPopup.enabled = NO;
      }
    } else {
      if (self.targetPopup) {
        self.targetPopup.enabled = YES;
      }
      NSString *selectedIdentifier = [self selectedTargetIdentifier];
      NSString *selectedName = [self selectedTargetName];
      for (SRCDevice *device in displayDevices) {
        NSString *title = device.name.length ? device.name : device.identifier;
        if (device.connected) title = [title stringByAppendingString:@" (Connected)"];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(chooseTarget:) keyEquivalent:@""];
        item.representedObject = device;
        item.state = ((selectedIdentifier.length && [device.identifier isEqualToString:selectedIdentifier]) ||
                      (selectedName.length && [device.name isEqualToString:selectedName])) ? NSControlStateValueOn : NSControlStateValueOff;
        [targetMenu addItem:item];
        if (self.targetPopup) {
          [self.targetPopup addItemWithTitle:title];
          NSMenuItem *popupItem = self.targetPopup.lastItem;
          popupItem.representedObject = device;
          if (item.state == NSControlStateValueOn) {
            [self.targetPopup selectItem:popupItem];
          }
        }
      }
    }
  }

  [targetMenu addItem:[NSMenuItem separatorItem]];
  [targetMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Clear Target" action:@selector(clearSelectedTarget:) keyEquivalent:@""]];
  self.targetMenuItem.submenu = targetMenu;
  [self updateSelectedTargetLabel];
}

- (void)refreshTargetsMenu:(id)sender {
  (void)sender;
  [self refreshAsyncAllowAutoSelect:NO];
}

- (void)applyStatusFromDevices:(NSArray<SRCDevice *> *)devices error:(NSError *)error {
  NSString *status = [self isPaused] ? @"Status: Paused" : [self statusTextForDevices:devices error:error];
  self.statusMenuItem.title = status;
  [self updatePanelStatusAppearance:status];
  [self updateStatusItemForStatus:status];
}

// Pure: derives status from an already-fetched device list (no XPC), so it is
// safe to call on the main thread.
- (NSString *)statusTextForDevices:(NSArray<SRCDevice *> *)devices error:(NSError *)error {
  if (![self hasSelectedTarget]) return @"Status: Target not configured";
  if (error) return [NSString stringWithFormat:@"Status: Error %@", @(error.code)];
  SRCResolveResult *result = [self.controller resolveTarget:[self selectedTarget] devices:devices];
  if (result.ambiguous) return @"Status: Ambiguous target";
  if (!result.target) return @"Status: Target not found";
  NSString *name = result.target.name.length ? result.target.name : @"Sidecar";
  return result.target.connected ? [NSString stringWithFormat:@"Status: Connected to %@", name]
                                  : [NSString stringWithFormat:@"Status: Disconnected from %@", name];
}

- (void)reconnectNow:(id)sender {
  (void)sender;
  [self runReconnectWithReason:@"manual menu" notify:SRNotifyAll];
}

- (void)reconnectFromHotKey {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self log:[NSString stringWithFormat:@"hotkey pressed %@", [self hotKeyDisplayString]]];
    [self runReconnectWithReason:@"global hotkey" notify:SRNotifyFailureOnly];
  });
}

- (void)runReconnectWithReason:(NSString *)reason notify:(SRNotify)notify {
  if (self.reconnectRunning) {
    [self log:@"reconnect skipped: already running"];
    return;
  }
  if (![self hasSelectedTarget]) {
    [self log:@"reconnect refused: target not configured"];
    if (notify != SRNotifyNone) [self showAlert:@"Sidecar target not configured" informativeText:@"Choose a target first."];
    [self refreshAsyncAllowAutoSelect:NO];
    return;
  }

  self.reconnectRunning = YES;
  [self log:[NSString stringWithFormat:@"reconnect start reason=%@", reason ? reason : @""]];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    NSError *error = nil;
    SRCDevice *device = nil;
    SRCStatus status = [self.controller statusForTarget:[self selectedTarget] device:&device error:&error];
    if (!error && status == SRCStatusConnected) {
      [self log:[NSString stringWithFormat:@"already connected %@", [SidecarController logLineForDevice:device prefix:@"device"]]];
      dispatch_async(dispatch_get_main_queue(), ^{
        self.reconnectRunning = NO;
        if (notify == SRNotifyAll) [self showAlert:@"Sidecar already connected" informativeText:device.name ? device.name : @""];
        [self refreshAsyncAllowAutoSelect:NO];
      });
      return;
    }

    BOOL ok = !error && [self.controller connectTarget:[self selectedTarget] device:&device error:&error];
    [self log:[NSString stringWithFormat:@"reconnect result ok=%@ error=%@ device=%@",
               ok ? @"true" : @"false",
               error.localizedDescription ? error.localizedDescription : @"",
               device ? [SidecarController logLineForDevice:device prefix:@"device"] : @""]];
    dispatch_async(dispatch_get_main_queue(), ^{
      self.reconnectRunning = NO;
      BOOL announce = (notify == SRNotifyAll) || (notify == SRNotifyFailureOnly && !ok);
      if (announce) {
        [self showAlert:ok ? @"Sidecar reconnect requested" : @"Sidecar reconnect failed"
        informativeText:ok ? (device.name ? device.name : @"") : (error.localizedDescription ? error.localizedDescription : @"Unknown error")];
      }
      [self refreshAsyncAllowAutoSelect:NO];
    });
  });
}

- (void)scheduleRetriesForReason:(NSString *)reason {
  if ([self isPaused]) {
    [self log:[NSString stringWithFormat:@"auto-reconnect skipped (paused) reason=%@", reason ? reason : @""]];
    return;
  }
  [self stopRetryTimers];
  for (NSNumber *delay in @[@8, @15, @30]) {
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:delay.doubleValue repeats:NO block:^(NSTimer *t) {
      (void)t;
      [self runReconnectWithReason:[NSString stringWithFormat:@"%@ retry +%@s", reason ? reason : @"event", delay] notify:SRNotifyNone];
    }];
    [self.retryTimers addObject:timer];
  }
  [self log:[NSString stringWithFormat:@"scheduled reconnect retries reason=%@", reason ? reason : @""]];
}

- (void)stopRetryTimers {
  for (NSTimer *timer in self.retryTimers) {
    [timer invalidate];
  }
  [self.retryTimers removeAllObjects];
}

- (BOOL)isPaused {
  return [[NSUserDefaults standardUserDefaults] boolForKey:PausedKey];
}

// Pause gates only the automatic (wake/unlock/display-change) reconnects; the
// app stays running and manual reconnect still works.
- (void)togglePause:(id)sender {
  (void)sender;
  BOOL paused = ![self isPaused];
  [[NSUserDefaults standardUserDefaults] setBool:paused forKey:PausedKey];
  [self log:paused ? @"paused (auto-reconnect off)" : @"resumed (auto-reconnect on)"];
  if (paused) [self stopRetryTimers];  // cancel any pending auto-reconnect
  [self syncPauseControls];
  [self refreshAsyncAllowAutoSelect:NO];
}

- (void)syncPauseControls {
  NSControlStateValue state = [self isPaused] ? NSControlStateValueOn : NSControlStateValueOff;
  self.pauseSwitch.state = state;
  self.pauseMenuItem.state = state;
}

- (void)workspaceDidWake:(NSNotification *)notification {
  (void)notification;
  [self log:@"event=system wake"];
  [self scheduleRetriesForReason:@"system wake"];
}

- (void)workspaceScreensDidWake:(NSNotification *)notification {
  (void)notification;
  [self log:@"event=screens wake"];
  [self scheduleRetriesForReason:@"screens wake"];
}

- (void)workspaceSessionDidBecomeActive:(NSNotification *)notification {
  (void)notification;
  [self log:@"event=session active"];
  [self scheduleRetriesForReason:@"session active"];
}

- (void)screenParametersChanged:(NSNotification *)notification {
  (void)notification;
  [self log:@"event=screen parameters changed"];
  [self scheduleRetriesForReason:@"screen parameters changed"];
}

- (NSString *)launchAgentPath {
  NSString *agents = [@"~/Library/LaunchAgents" stringByExpandingTildeInPath];
  return [agents stringByAppendingPathComponent:[AppBundleID stringByAppendingString:@".plist"]];
}

- (BOOL)launchAtLoginEnabled {
  return [[NSFileManager defaultManager] fileExistsAtPath:[self launchAgentPath]];
}

- (void)toggleLaunchAtLogin:(id)sender {
  (void)sender;
  NSError *error = nil;
  BOOL enabled = [self launchAtLoginEnabled];
  if (enabled) {
    [[NSFileManager defaultManager] removeItemAtPath:[self launchAgentPath] error:&error];
  } else {
    [self writeLaunchAgent:&error];
  }
  if (error) {
    [self log:[NSString stringWithFormat:@"launch-at-login error=%@", error.localizedDescription]];
    [self showAlert:@"Launch at Login update failed" informativeText:error.localizedDescription];
  } else {
    [self log:enabled ? @"launch-at-login disabled" : @"launch-at-login enabled"];
  }
  [self syncLaunchAtLoginControls];
}

- (void)syncLaunchAtLoginControls {
  NSControlStateValue state = [self launchAtLoginEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
  self.launchAtLoginItem.state = state;
  self.launchAtLoginCheckbox.state = state;
}

- (void)writeLaunchAgent:(NSError **)error {
  NSString *executablePath = [[NSBundle mainBundle] executablePath];
  NSString *agents = [[self launchAgentPath] stringByDeletingLastPathComponent];
  [[NSFileManager defaultManager] createDirectoryAtPath:agents withIntermediateDirectories:YES attributes:nil error:error];
  if (error && *error) return;

  NSDictionary *plist = @{
    @"Label": AppBundleID,
    @"ProgramArguments": @[executablePath],
    @"RunAtLoad": @YES,
  };
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
  if (!data) return;
  [data writeToFile:[self launchAgentPath] options:NSDataWritingAtomic error:error];
}

- (void)openLog:(id)sender {
  (void)sender;
  NSString *path = [self expandedLogPath];
  if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
    [self log:@"created log from Open Log"];
  }
  [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
}

- (void)quit:(id)sender {
  (void)sender;
  [NSApp terminate:nil];
}

- (void)showAlert:(NSString *)title informativeText:(NSString *)text {
  NSAlert *alert = [NSAlert new];
  alert.messageText = title;
  alert.informativeText = text ? text : @"";
  [alert addButtonWithTitle:@"OK"];
  [alert runModal];
}

@end

int main(int argc, const char **argv) {
  (void)argc;
  (void)argv;
  @autoreleasepool {
    NSApplication *app = [NSApplication sharedApplication];
    static AppDelegate *delegate = nil;
    delegate = [AppDelegate new];
    app.delegate = delegate;
    [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [app run];
  }
  return 0;
}
