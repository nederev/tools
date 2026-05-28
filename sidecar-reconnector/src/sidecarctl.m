#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/message.h>

@protocol SidecarDisplayAgent_Interface
- (void)displayAgentDevices:(void (^)(id currentDevice, NSArray *devices, NSError *error))completion;
- (void)displayAgentConnectToDevice:(id)device withConfig:(id)config completion:(void (^)(NSError *error))completion;
- (void)displayAgentDisconnectFromDevice:(id)device completion:(void (^)(NSError *error))completion;
- (void)displayCurrentConfig:(void (^)(id config, NSError *error))completion;
@end

typedef NS_ENUM(NSInteger, SidecarCtlCommand) {
  SidecarCtlCommandHelp,
  SidecarCtlCommandList,
  SidecarCtlCommandStatus,
  SidecarCtlCommandConnect,
};

static NSString *TargetName = nil;
static NSString *TargetID = nil;

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
  if (identifier.length >= 8) {
    return [identifier substringToIndex:8];
  }
  return identifier ? identifier : @"";
}

static BOOL matchesTarget(id device) {
  if (!TargetName.length && !TargetID.length) {
    return NO;
  }

  NSString *name = objectString(device, @"name");
  NSString *identifier = objectString(device, @"identifier");
  NSString *desc = [device description] ? [device description] : @"";

  if (TargetName.length && [name localizedCaseInsensitiveContainsString:TargetName]) return YES;
  if (TargetID.length && [identifier localizedCaseInsensitiveContainsString:TargetID]) return YES;
  if (TargetID.length && [desc localizedCaseInsensitiveContainsString:shortIdentifier(TargetID)]) return YES;
  return NO;
}

static void printDevice(NSString *prefix, id device) {
  fprintf(stdout, "%s name=%s identifier=%s model=%s desc=%s offersDisplay=%s\n",
          prefix.UTF8String,
          objectString(device, @"name").UTF8String,
          objectString(device, @"identifier").UTF8String,
          objectString(device, @"model").UTF8String,
          ([device description] ? [device description] : @"").UTF8String,
          boolValue(device, @"offersAdditionalDisplay") ? "true" : "false");
}

static void printUsage(void) {
  fprintf(stderr,
          "Usage:\n"
          "  sidecarctl list\n"
          "  sidecarctl status --name <ipad-name> [--id <identifier>]\n"
          "  sidecarctl connect --name <ipad-name> [--id <identifier>]\n"
          "\n"
          "Options:\n"
          "  --name <name>    Match a Sidecar device by display name.\n"
          "  --id <id>        Match a Sidecar device by identifier/IDS prefix.\n");
}

static NSSet *allowedXpcClasses(void) {
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

static NSArray *displayAgentDevices(void) {
  NSXPCInterface *iface = [NSXPCInterface interfaceWithProtocol:@protocol(SidecarDisplayAgent_Interface)];
  NSSet *classes = allowedXpcClasses();

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

static void appendUniqueDevices(NSMutableArray *target, NSArray *source) {
  NSMutableSet *seen = [NSMutableSet set];
  for (id device in target) {
    NSString *key = [NSString stringWithFormat:@"%@|%@|%@",
                     objectString(device, @"identifier"),
                     objectString(device, @"name"),
                     [device description] ? [device description] : @""];
    [seen addObject:key];
  }

  for (id device in source ? source : @[]) {
    if (!isSidecarDevice(device)) continue;
    NSString *key = [NSString stringWithFormat:@"%@|%@|%@",
                     objectString(device, @"identifier"),
                     objectString(device, @"name"),
                     [device description] ? [device description] : @""];
    if ([seen containsObject:key]) continue;
    [target addObject:device];
    [seen addObject:key];
  }
}

static NSArray *discoverDevices(id manager) {
  NSMutableArray *devices = [NSMutableArray array];
  appendUniqueDevices(devices, callArray0(manager, @"devices"));
  appendUniqueDevices(devices, callArray0(manager, @"recentDevices"));

  Class deviceClass = NSClassFromString(@"SidecarDevice");
  if ([deviceClass respondsToSelector:@selector(allDevicesByForcingFetchFromRelay:)]) {
    NSArray *forced = ((id (*)(id, SEL, BOOL))objc_msgSend)(deviceClass, @selector(allDevicesByForcingFetchFromRelay:), YES);
    if ([forced isKindOfClass:[NSArray class]]) appendUniqueDevices(devices, forced);
  }
  if ([deviceClass respondsToSelector:@selector(allDevices)]) {
    NSArray *all = call0(deviceClass, @selector(allDevices));
    if ([all isKindOfClass:[NSArray class]]) appendUniqueDevices(devices, all);
  }

  appendUniqueDevices(devices, displayAgentDevices());
  return devices;
}

static id firstMatchingDevice(NSArray *devices) {
  for (id device in devices) {
    if (matchesTarget(device)) return device;
  }
  return nil;
}

static id onlyDisplayCandidate(NSArray *devices) {
  NSMutableArray *displayDevices = [NSMutableArray array];
  for (id device in devices) {
    if (boolValue(device, @"offersAdditionalDisplay")) {
      [displayDevices addObject:device];
    }
  }
  return displayDevices.count == 1 ? displayDevices.firstObject : nil;
}

static SidecarCtlCommand parseArgs(int argc, const char **argv) {
  if (argc < 2) return SidecarCtlCommandHelp;

  SidecarCtlCommand command = SidecarCtlCommandHelp;
  if (strcmp(argv[1], "list") == 0) {
    command = SidecarCtlCommandList;
  } else if (strcmp(argv[1], "status") == 0) {
    command = SidecarCtlCommandStatus;
  } else if (strcmp(argv[1], "connect") == 0) {
    command = SidecarCtlCommandConnect;
  } else if (strcmp(argv[1], "help") == 0 || strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0) {
    return SidecarCtlCommandHelp;
  } else {
    fprintf(stderr, "unknown command: %s\n", argv[1]);
    return SidecarCtlCommandHelp;
  }

  for (int i = 2; i < argc; i++) {
    if (strcmp(argv[i], "--name") == 0 && i + 1 < argc) {
      TargetName = [NSString stringWithUTF8String:argv[++i]];
    } else if (strcmp(argv[i], "--id") == 0 && i + 1 < argc) {
      TargetID = [NSString stringWithUTF8String:argv[++i]];
    } else {
      fprintf(stderr, "unknown or incomplete option: %s\n", argv[i]);
      return SidecarCtlCommandHelp;
    }
  }

  return command;
}

int main(int argc, const char **argv) {
  @autoreleasepool {
    SidecarCtlCommand command = parseArgs(argc, argv);
    if (command == SidecarCtlCommandHelp) {
      printUsage();
      return argc < 2 ? 2 : 0;
    }

    void *handle = dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_LAZY | RTLD_GLOBAL);
    if (!handle) {
      fprintf(stderr, "failed to load SidecarCore: %s\n", dlerror());
      return 10;
    }

    Class managerClass = NSClassFromString(@"SidecarDisplayManager");
    id manager = call0(managerClass, @selector(sharedManager));
    if (!manager) {
      fprintf(stderr, "SidecarDisplayManager.sharedManager unavailable\n");
      return 11;
    }

    NSMutableArray *allKnownDevices = [NSMutableArray array];
    NSArray *connected = callArray0(manager, @"connectedDevices");
    appendUniqueDevices(allKnownDevices, connected);
    appendUniqueDevices(allKnownDevices, discoverDevices(manager));

    if (command == SidecarCtlCommandList) {
      for (id device in allKnownDevices) {
        printDevice([connected containsObject:device] ? @"connected" : @"candidate", device);
      }
      return 0;
    }

    id target = firstMatchingDevice(allKnownDevices);
    if (!target && !TargetName.length && !TargetID.length) {
      target = onlyDisplayCandidate(allKnownDevices);
    }

    if (!target) {
      fprintf(stderr, "target-not-found candidateCount=%lu\n", (unsigned long)allKnownDevices.count);
      for (id device in allKnownDevices) printDevice(@"candidate", device);
      return 20;
    }

    id connectedTarget = firstMatchingDevice(connected);
    if (!connectedTarget && target && [connected containsObject:target]) {
      connectedTarget = target;
    }

    if (connectedTarget) {
      printDevice(@"already-connected", connectedTarget);
      return 0;
    }

    if (command == SidecarCtlCommandStatus) {
      printDevice(@"disconnected", target);
      return 1;
    }

    printDevice(@"target-found", target);

    __block BOOL done = NO;
    __block int exitCode = 2;
    if ([manager respondsToSelector:@selector(connectToDevice:completion:)]) {
      void (^completion)(NSError *) = ^(NSError *error) {
        if (error) {
          fprintf(stderr, "connect-error: %s\n", error.description.UTF8String);
          exitCode = 30;
        } else {
          fprintf(stdout, "connect-request-ok\n");
          exitCode = 0;
        }
        done = YES;
        CFRunLoopStop(CFRunLoopGetMain());
      };
      ((void (*)(id, SEL, id, id))objc_msgSend)(manager, @selector(connectToDevice:completion:), target, completion);
    } else {
      fprintf(stderr, "connectToDevice:completion: unavailable\n");
      return 12;
    }

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20];
    while (!done && [deadline timeIntervalSinceNow] > 0) {
      [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
    }
    if (!done) {
      fprintf(stderr, "connect-timeout\n");
      return 31;
    }
    return exitCode;
  }
}
