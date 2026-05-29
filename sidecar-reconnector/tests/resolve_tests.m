// Device-independent unit tests for SidecarController's pure resolution logic.
// These exercise -resolveTarget:devices: against synthetic device lists and do
// not touch the private Sidecar APIs, so they run anywhere (no iPad required).
//
// Build and run with: make -C sidecar-reconnector test

#import <Foundation/Foundation.h>

#import "SidecarController.h"

static int gChecks = 0;
static int gFailures = 0;

static void check(BOOL condition, const char *description) {
  gChecks++;
  if (!condition) {
    gFailures++;
    fprintf(stderr, "FAIL: %s\n", description);
  }
}

static SRCDevice *device(NSString *name,
                         NSString *identifier,
                         NSString *desc,
                         BOOL offersDisplay,
                         BOOL connected) {
  SRCDevice *d = [SRCDevice new];
  d.name = name;
  d.identifier = identifier;
  d.model = @"iPad";
  d.deviceDescription = desc ? desc : [NSString stringWithFormat:@"desc-%@", identifier ? identifier : @""];
  d.offersDisplay = offersDisplay;
  d.connected = connected;
  return d;
}

int main(void) {
  @autoreleasepool {
    SidecarController *c = [SidecarController new];

    // Exact name match is case-insensitive and unambiguous.
    {
      NSArray *devices = @[ device(@"My iPad", @"AAAA1111", nil, YES, NO),
                            device(@"Other", @"BBBB2222", nil, YES, NO) ];
      SRCResolveResult *r = [c resolveTarget:[SRCTarget targetWithName:@"my ipad" identifier:nil] devices:devices];
      check(r.target != nil && [r.target.identifier isEqualToString:@"AAAA1111"], "exact name match (case-insensitive)");
      check(!r.ambiguous, "exact name match is not ambiguous");
      check(!r.fuzzy, "exact name match is not fuzzy");
    }

    // Exact identifier match is case-insensitive.
    {
      NSArray *devices = @[ device(@"My iPad", @"AAAA1111", nil, YES, NO),
                            device(@"Other", @"BBBB2222", nil, YES, NO) ];
      SRCResolveResult *r = [c resolveTarget:[SRCTarget targetWithName:nil identifier:@"bbbb2222"] devices:devices];
      check(r.target != nil && [r.target.name isEqualToString:@"Other"], "exact identifier match (case-insensitive)");
    }

    // Duplicate exact name matches are ambiguous, with all matches reported.
    {
      NSArray *devices = @[ device(@"iPad", @"AAAA", nil, YES, NO),
                            device(@"iPad", @"BBBB", nil, YES, NO) ];
      SRCResolveResult *r = [c resolveTarget:[SRCTarget targetWithName:@"iPad" identifier:nil] devices:devices];
      check(r.ambiguous, "duplicate names are ambiguous");
      check(r.target == nil, "ambiguous result has no single target");
      check(r.matches.count == 2, "ambiguous result reports all matches");
    }

    // A single substring (fuzzy) match wins when there is no exact match.
    {
      NSArray *devices = @[ device(@"My iPad Air", @"AAAA1111", nil, YES, NO),
                            device(@"Desk Mac", @"BBBB2222", nil, YES, NO) ];
      SRCResolveResult *r = [c resolveTarget:[SRCTarget targetWithName:@"iPad" identifier:nil] devices:devices];
      check(r.target != nil && [r.target.identifier isEqualToString:@"AAAA1111"], "single fuzzy substring match");
      check(r.fuzzy, "fuzzy flag is set for substring match");
      check(!r.ambiguous, "single fuzzy match is not ambiguous");
    }

    // Multiple substring matches are ambiguous and flagged fuzzy.
    {
      NSArray *devices = @[ device(@"My iPad Air", @"AAAA", nil, YES, NO),
                            device(@"Work iPad Pro", @"BBBB", nil, YES, NO) ];
      SRCResolveResult *r = [c resolveTarget:[SRCTarget targetWithName:@"iPad" identifier:nil] devices:devices];
      check(r.ambiguous && r.fuzzy, "multiple fuzzy matches are ambiguous");
      check(r.matches.count == 2, "fuzzy ambiguous reports all matches");
    }

    // An identifier prefix found inside a device description is a fuzzy match.
    {
      NSArray *devices = @[ device(@"Tablet", @"FULLIDENT0000", @"IDS token=XYZ12345PADDING", YES, NO),
                            device(@"Mac", @"CCCC", nil, YES, NO) ];
      SRCResolveResult *r = [c resolveTarget:[SRCTarget targetWithName:nil identifier:@"XYZ12345"] devices:devices];
      check(r.target != nil && [r.target.name isEqualToString:@"Tablet"], "fuzzy match by short identifier in description");
      check(r.fuzzy, "description identifier match is fuzzy");
    }

    // No configured target with a single display-capable device auto-selects it.
    {
      NSArray *devices = @[ device(@"Only iPad", @"AAAA", nil, YES, NO) ];
      SRCResolveResult *r = [c resolveTarget:[SRCTarget targetWithName:nil identifier:nil] devices:devices];
      check(r.target != nil && [r.target.identifier isEqualToString:@"AAAA"], "auto-select single display device");
      check(!r.ambiguous, "auto-select is not ambiguous");
    }

    // No configured target picks the only display-capable device among peers.
    {
      NSArray *devices = @[ device(@"Display iPad", @"AAAA", nil, YES, NO),
                            device(@"Audio thing", @"BBBB", nil, NO, NO) ];
      SRCResolveResult *r = [c resolveTarget:[SRCTarget targetWithName:nil identifier:nil] devices:devices];
      check(r.target != nil && [r.target.identifier isEqualToString:@"AAAA"], "auto-select single display-capable device");
    }

    // No configured target with multiple display devices does not guess.
    {
      NSArray *devices = @[ device(@"A", @"AAAA", nil, YES, NO),
                            device(@"B", @"BBBB", nil, YES, NO) ];
      SRCResolveResult *r = [c resolveTarget:[SRCTarget targetWithName:nil identifier:nil] devices:devices];
      check(r.target == nil, "no auto-select when multiple display devices");
      check(!r.ambiguous, "absent auto-select is not reported as ambiguous");
    }

    // A configured-but-missing target resolves to nothing, not ambiguity.
    {
      NSArray *devices = @[ device(@"My iPad", @"AAAA", nil, YES, NO) ];
      SRCResolveResult *r = [c resolveTarget:[SRCTarget targetWithName:@"Nonexistent" identifier:nil] devices:devices];
      check(r.target == nil && !r.ambiguous, "missing target is not found and not ambiguous");
    }

    // The connected flag survives resolution.
    {
      NSArray *devices = @[ device(@"My iPad", @"AAAA", nil, YES, YES) ];
      SRCResolveResult *r = [c resolveTarget:[SRCTarget targetWithName:@"My iPad" identifier:nil] devices:devices];
      check(r.target != nil && r.target.connected, "resolved target retains connected flag");
    }

    fprintf(stdout, "%d checks, %d failures\n", gChecks, gFailures);
    return gFailures == 0 ? 0 : 1;
  }
}
