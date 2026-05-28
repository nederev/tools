#import "SidecarController.h"

#import <dlfcn.h>
#import <objc/message.h>

@protocol SidecarDisplayAgent_Interface
- (void)displayAgentDevices:(void (^)(id currentDevice, NSArray *devices, NSError *error))completion;
- (void)displayAgentConnectToDevice:(id)device withConfig:(id)config completion:(void (^)(NSError *error))completion;
- (void)displayAgentDisconnectFromDevice:(id)device completion:(void (^)(NSError *error))completion;
- (void)displayCurrentConfig:(void (^)(id config, NSError *error))completion;
@end

@interface SRCDevice ()
@property(nonatomic, strong) id rawDevice;
@end

@implementation SRCDevice
@end

@implementation SRCTarget
+ (instancetype)targetWithName:(NSString *)name identifier:(NSString *)identifier {
  SRCTarget *target = [SRCTarget new];
  target.name = name.length ? name : nil;
  target.identifier = identifier.length ? identifier : nil;
  return target;
}
@end

@implementation SRCResolveResult
- (instancetype)init {
  self = [super init];
  if (self) {
    _matches = @[];
  }
  return self;
}
@end

static NSString *const SRCErrorDomain = @"SidecarReconnector";

static NSError *SRCError(NSInteger code, NSString *message) {
  return [NSError errorWithDomain:SRCErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message ? message : @""}];
}

static id call0(id obj, SEL sel) {
  if (!obj || ![obj respondsToSelector:sel]) return nil;
  return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}

static NSArray *callArray0(id obj, NSString *selectorName) {
  id value = call0(obj, NSSelectorFromString(selectorName));
  return [value isKindOfClass:[NSArray class]] ? value : @[];
}

static NSString *objectString(id obj, NSString *selectorName) {
  id value = call0(obj, NSSelectorFromString(selectorName));
  return value ? [value description] : @"";
}

static BOOL boolValue(id obj, NSString *selectorName) {
  SEL sel = NSSelectorFromString(selectorName);
  if (!obj || ![obj respondsToSelector:sel]) return NO;
  return ((BOOL (*)(id, SEL))objc_msgSend)(obj, sel);
}

static BOOL isSidecarDevice(id obj) {
  Class deviceClass = NSClassFromString(@"SidecarDevice");
  return deviceClass && [obj isKindOfClass:deviceClass];
}

static NSString *shortIdentifier(NSString *identifier) {
  return identifier.length >= 8 ? [identifier substringToIndex:8] : (identifier ? identifier : @"");
}

static NSString *rawDeviceKey(id device) {
  return [NSString stringWithFormat:@"%@|%@|%@",
          objectString(device, @"identifier"),
          objectString(device, @"name"),
          [device description] ? [device description] : @""];
}

static NSString *deviceKey(SRCDevice *device) {
  return [NSString stringWithFormat:@"%@|%@|%@",
          device.identifier ? device.identifier : @"",
          device.name ? device.name : @"",
          device.deviceDescription ? device.deviceDescription : @""];
}

static SRCDevice *wrapDevice(id rawDevice, NSArray *connectedRawDevices) {
  SRCDevice *device = [SRCDevice new];
  device.rawDevice = rawDevice;
  device.name = objectString(rawDevice, @"name");
  device.identifier = objectString(rawDevice, @"identifier");
  device.model = objectString(rawDevice, @"model");
  device.deviceDescription = [rawDevice description] ? [rawDevice description] : @"";
  device.offersDisplay = boolValue(rawDevice, @"offersAdditionalDisplay");

  NSString *key = rawDeviceKey(rawDevice);
  for (id connected in connectedRawDevices ? connectedRawDevices : @[]) {
    if ([rawDeviceKey(connected) isEqualToString:key]) {
      device.connected = YES;
      break;
    }
  }
  return device;
}

static BOOL targetIsConfigured(SRCTarget *target) {
  return target.name.length || target.identifier.length;
}

static BOOL matchesTargetExactly(SRCDevice *device, SRCTarget *target) {
  if (!targetIsConfigured(target)) return NO;
  if (target.name.length && [device.name localizedCaseInsensitiveCompare:target.name] == NSOrderedSame) return YES;
  if (target.identifier.length && [device.identifier localizedCaseInsensitiveCompare:target.identifier] == NSOrderedSame) return YES;
  return NO;
}

static BOOL matchesTargetFuzzy(SRCDevice *device, SRCTarget *target) {
  if (!targetIsConfigured(target)) return NO;
  if (target.name.length && [device.name localizedCaseInsensitiveContainsString:target.name]) return YES;
  if (target.identifier.length && [device.identifier localizedCaseInsensitiveContainsString:target.identifier]) return YES;
  if (target.identifier.length && [device.deviceDescription localizedCaseInsensitiveContainsString:shortIdentifier(target.identifier)]) return YES;
  return NO;
}

static void appendUniqueRawDevices(NSMutableArray *target, NSArray *source) {
  NSMutableSet *seen = [NSMutableSet set];
  for (id device in target) {
    [seen addObject:rawDeviceKey(device)];
  }

  for (id device in source ? source : @[]) {
    if (!isSidecarDevice(device)) continue;
    NSString *key = rawDeviceKey(device);
    if ([seen containsObject:key]) continue;
    [target addObject:device];
    [seen addObject:key];
  }
}

@interface SidecarController ()
@property(nonatomic, strong) NSArray *lastRawDevices;
@end

@implementation SidecarController

- (id)managerWithError:(NSError **)error {
  void *handle = dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_LAZY | RTLD_GLOBAL);
  if (!handle) {
    if (error) *error = SRCError(SRCErrorSidecarCoreUnavailable, [NSString stringWithFormat:@"failed to load SidecarCore: %s", dlerror()]);
    return nil;
  }

  Class managerClass = NSClassFromString(@"SidecarDisplayManager");
  id manager = call0(managerClass, @selector(sharedManager));
  if (!manager && error) {
    *error = SRCError(SRCErrorManagerUnavailable, @"SidecarDisplayManager.sharedManager unavailable");
  }
  return manager;
}

- (NSArray *)displayAgentDevices {
  NSXPCInterface *iface = [NSXPCInterface interfaceWithProtocol:@protocol(SidecarDisplayAgent_Interface)];
  NSSet *classes = [self allowedXpcClasses];

  for (NSUInteger i = 0; i < 3; i++) {
    [iface setClasses:classes forSelector:@selector(displayAgentDevices:) argumentIndex:i ofReply:YES];
  }
  [iface setClasses:classes forSelector:@selector(displayAgentConnectToDevice:withConfig:completion:) argumentIndex:0 ofReply:NO];
  [iface setClasses:classes forSelector:@selector(displayAgentConnectToDevice:withConfig:completion:) argumentIndex:1 ofReply:NO];
  [iface setClasses:classes forSelector:@selector(displayAgentConnectToDevice:withConfig:completion:) argumentIndex:0 ofReply:YES];
  [iface setClasses:classes forSelector:@selector(displayAgentDisconnectFromDevice:completion:) argumentIndex:0 ofReply:NO];
  [iface setClasses:classes forSelector:@selector(displayAgentDisconnectFromDevice:completion:) argumentIndex:0 ofReply:YES];
  for (NSUInteger i = 0; i < 2; i++) {
    [iface setClasses:classes forSelector:@selector(displayCurrentConfig:) argumentIndex:i ofReply:YES];
  }

  NSXPCConnection *conn = [[NSXPCConnection alloc] initWithMachServiceName:@"com.apple.sidecar-display-agent" options:0];
  conn.remoteObjectInterface = iface;
  [conn resume];

  id proxy = [conn remoteObjectProxyWithErrorHandler:^(NSError *error) {
    fprintf(stderr, "display-agent-xpc-error: %s\n", error.description.UTF8String);
    CFRunLoopStop(CFRunLoopGetMain());
  }];

  NSMutableArray *out = [NSMutableArray array];
  __block BOOL done = NO;
  [proxy displayAgentDevices:^(id currentDevice, NSArray *devices, NSError *error) {
    if (error) {
      fprintf(stderr, "display-agent-devices-error: %s\n", error.description.UTF8String);
    }
    if (isSidecarDevice(currentDevice)) [out addObject:currentDevice];
    for (id device in devices ? devices : @[]) {
      if (isSidecarDevice(device)) [out addObject:device];
    }
    done = YES;
    CFRunLoopStop(CFRunLoopGetMain());
  }];

  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
  while (!done && [deadline timeIntervalSinceNow] > 0) {
    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
  }
  [conn invalidate];
  return out;
}

- (NSSet *)allowedXpcClasses {
  NSMutableSet *classes = [NSMutableSet setWithArray:@[
    [NSArray class], [NSMutableArray class], [NSDictionary class], [NSMutableDictionary class],
    [NSString class], [NSNumber class], [NSData class], [NSDate class], [NSURL class],
    [NSUUID class], [NSNull class], [NSError class]
  ]];

  for (NSString *name in @[@"SidecarDevice", @"SidecarDisplayConfig", @"SidecarService", @"SidecarItem"]) {
    Class cls = NSClassFromString(name);
    if (cls) [classes addObject:cls];
  }

  return classes;
}

- (NSArray *)discoverRawDevicesWithManager:(id)manager {
  NSMutableArray *devices = [NSMutableArray array];
  appendUniqueRawDevices(devices, callArray0(manager, @"devices"));
  appendUniqueRawDevices(devices, callArray0(manager, @"recentDevices"));

  Class deviceClass = NSClassFromString(@"SidecarDevice");
  if ([deviceClass respondsToSelector:@selector(allDevicesByForcingFetchFromRelay:)]) {
    NSArray *forced = ((id (*)(id, SEL, BOOL))objc_msgSend)(deviceClass, @selector(allDevicesByForcingFetchFromRelay:), YES);
    if ([forced isKindOfClass:[NSArray class]]) appendUniqueRawDevices(devices, forced);
  }
  if ([deviceClass respondsToSelector:@selector(allDevices)]) {
    NSArray *all = call0(deviceClass, @selector(allDevices));
    if ([all isKindOfClass:[NSArray class]]) appendUniqueRawDevices(devices, all);
  }

  appendUniqueRawDevices(devices, [self displayAgentDevices]);
  return devices;
}

- (NSArray<SRCDevice *> *)listDevicesWithError:(NSError **)error {
  id manager = [self managerWithError:error];
  if (!manager) return @[];

  NSArray *connectedRaw = callArray0(manager, @"connectedDevices");
  NSMutableArray *allRaw = [NSMutableArray array];
  appendUniqueRawDevices(allRaw, connectedRaw);
  appendUniqueRawDevices(allRaw, [self discoverRawDevicesWithManager:manager]);
  self.lastRawDevices = allRaw;

  NSMutableArray *devices = [NSMutableArray array];
  for (id rawDevice in allRaw) {
    [devices addObject:wrapDevice(rawDevice, connectedRaw)];
  }
  return devices;
}

- (SRCResolveResult *)resolveTarget:(SRCTarget *)target devices:(NSArray<SRCDevice *> *)devices {
  SRCResolveResult *result = [SRCResolveResult new];
  NSMutableArray *exactMatches = [NSMutableArray array];
  NSMutableArray *fuzzyMatches = [NSMutableArray array];

  for (SRCDevice *device in devices ? devices : @[]) {
    if (matchesTargetExactly(device, target)) [exactMatches addObject:device];
  }

  if (exactMatches.count == 1) {
    result.target = exactMatches.firstObject;
    result.matches = exactMatches;
    return result;
  }
  if (exactMatches.count > 1) {
    result.ambiguous = YES;
    result.matches = exactMatches;
    return result;
  }

  if (targetIsConfigured(target)) {
    for (SRCDevice *device in devices ? devices : @[]) {
      if (matchesTargetFuzzy(device, target)) [fuzzyMatches addObject:device];
    }
    if (fuzzyMatches.count == 1) {
      result.target = fuzzyMatches.firstObject;
      result.matches = fuzzyMatches;
      result.fuzzy = YES;
      return result;
    }
    if (fuzzyMatches.count > 1) {
      result.ambiguous = YES;
      result.matches = fuzzyMatches;
      result.fuzzy = YES;
      return result;
    }
  } else {
    NSMutableArray *displayDevices = [NSMutableArray array];
    for (SRCDevice *device in devices ? devices : @[]) {
      if (device.offersDisplay) [displayDevices addObject:device];
    }
    if (displayDevices.count == 1) {
      result.target = displayDevices.firstObject;
      result.matches = displayDevices;
    }
  }

  return result;
}

- (SRCStatus)statusForTarget:(SRCTarget *)target device:(SRCDevice **)device error:(NSError **)error {
  NSArray *devices = [self listDevicesWithError:error];
  if (error && *error) return SRCStatusDisconnected;
  SRCResolveResult *result = [self resolveTarget:target devices:devices];
  if (result.ambiguous) {
    if (error) *error = SRCError(SRCErrorAmbiguousTarget, @"ambiguous-target");
    return SRCStatusDisconnected;
  }
  if (!result.target) {
    if (error) *error = SRCError(SRCErrorTargetNotFound, [NSString stringWithFormat:@"target-not-found candidateCount=%lu", (unsigned long)devices.count]);
    return SRCStatusDisconnected;
  }
  if (device) *device = result.target;
  return result.target.connected ? SRCStatusConnected : SRCStatusDisconnected;
}

- (BOOL)connectTarget:(SRCTarget *)target device:(SRCDevice **)device error:(NSError **)error {
  SRCDevice *resolved = nil;
  SRCStatus status = [self statusForTarget:target device:&resolved error:error];
  if (error && *error) return NO;
  if (device) *device = resolved;
  if (status == SRCStatusConnected) return YES;

  id manager = [self managerWithError:error];
  if (!manager) return NO;

  id rawTarget = nil;
  for (id rawDevice in self.lastRawDevices ? self.lastRawDevices : @[]) {
    if ([rawDeviceKey(rawDevice) isEqualToString:deviceKey(resolved)]) {
      rawTarget = rawDevice;
      break;
    }
  }
  if (!rawTarget) {
    if (error) *error = SRCError(SRCErrorTargetNotFound, @"target raw device unavailable");
    return NO;
  }

  __block BOOL done = NO;
  __block NSError *connectError = nil;
  if ([manager respondsToSelector:@selector(connectToDevice:completion:)]) {
    void (^completion)(NSError *) = ^(NSError *callbackError) {
      connectError = callbackError;
      done = YES;
      CFRunLoopStop(CFRunLoopGetMain());
    };
    ((void (*)(id, SEL, id, id))objc_msgSend)(manager, @selector(connectToDevice:completion:), rawTarget, completion);
  } else {
    if (error) *error = SRCError(SRCErrorConnectUnavailable, @"connectToDevice:completion: unavailable");
    return NO;
  }

  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20];
  while (!done && [deadline timeIntervalSinceNow] > 0) {
    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
  }
  if (!done) {
    if (error) *error = SRCError(SRCErrorConnectTimeout, @"connect-timeout");
    return NO;
  }
  if (connectError) {
    if (error) *error = SRCError(SRCErrorConnectFailed, [NSString stringWithFormat:@"connect-error: %@", connectError.localizedDescription]);
    return NO;
  }
  return YES;
}

+ (NSString *)logLineForDevice:(SRCDevice *)device prefix:(NSString *)prefix {
  return [NSString stringWithFormat:@"%@ name=%@ identifier=%@ model=%@ desc=%@ offersDisplay=%@",
          prefix ? prefix : @"device",
          device.name ? device.name : @"",
          device.identifier ? device.identifier : @"",
          device.model ? device.model : @"",
          device.deviceDescription ? device.deviceDescription : @"",
          device.offersDisplay ? @"true" : @"false"];
}

@end
