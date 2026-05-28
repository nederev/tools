#import <Foundation/Foundation.h>

#import "SidecarController.h"

typedef NS_ENUM(NSInteger, SidecarCtlCommand) {
  SidecarCtlCommandHelp,
  SidecarCtlCommandInvalid,
  SidecarCtlCommandList,
  SidecarCtlCommandStatus,
  SidecarCtlCommandConnect,
};

static NSString *TargetName = nil;
static NSString *TargetID = nil;

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

static void printDevice(NSString *prefix, SRCDevice *device) {
  fprintf(stdout, "%s\n", [SidecarController logLineForDevice:device prefix:prefix].UTF8String);
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
    return SidecarCtlCommandInvalid;
  }

  for (int i = 2; i < argc; i++) {
    if (strcmp(argv[i], "--name") == 0 && i + 1 < argc) {
      TargetName = [NSString stringWithUTF8String:argv[++i]];
    } else if (strcmp(argv[i], "--id") == 0 && i + 1 < argc) {
      TargetID = [NSString stringWithUTF8String:argv[++i]];
    } else {
      fprintf(stderr, "unknown or incomplete option: %s\n", argv[i]);
      return SidecarCtlCommandInvalid;
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
    if (command == SidecarCtlCommandInvalid) {
      printUsage();
      return 2;
    }

    SidecarController *controller = [SidecarController new];
    NSError *error = nil;
    NSArray<SRCDevice *> *devices = [controller listDevicesWithError:&error];
    if (error) {
      fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
      return (int)error.code;
    }

    if (command == SidecarCtlCommandList) {
      for (SRCDevice *device in devices) {
        printDevice(device.connected ? @"connected" : @"candidate", device);
      }
      return 0;
    }

    SRCTarget *target = [SRCTarget targetWithName:TargetName identifier:TargetID];
    SRCResolveResult *result = [controller resolveTarget:target devices:devices];
    if (result.ambiguous) {
      fprintf(stderr, "ambiguous-target %sMatchCount=%lu\n", result.fuzzy ? "fuzzy" : "exact", (unsigned long)result.matches.count);
      for (SRCDevice *device in result.matches) printDevice(@"match", device);
      return SRCErrorAmbiguousTarget;
    }
    if (!result.target) {
      fprintf(stderr, "target-not-found candidateCount=%lu\n", (unsigned long)devices.count);
      for (SRCDevice *device in devices) printDevice(@"candidate", device);
      return SRCErrorTargetNotFound;
    }

    if (result.target.connected) {
      printDevice(@"already-connected", result.target);
      return 0;
    }

    if (command == SidecarCtlCommandStatus) {
      printDevice(@"disconnected", result.target);
      return 1;
    }

    printDevice(@"target-found", result.target);
    SRCDevice *connectedDevice = nil;
    BOOL ok = [controller connectTarget:target device:&connectedDevice error:&error];
    if (!ok) {
      fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
      return error ? (int)error.code : 2;
    }

    fprintf(stdout, "connect-request-ok\n");
    return 0;
  }
}
