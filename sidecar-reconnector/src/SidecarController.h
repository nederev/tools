#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SRCStatus) {
  SRCStatusDisconnected = 0,
  SRCStatusConnected = 1,
};

typedef NS_ENUM(NSInteger, SRCErrorCode) {
  SRCErrorSidecarCoreUnavailable = 10,
  SRCErrorManagerUnavailable = 11,
  SRCErrorConnectUnavailable = 12,
  SRCErrorTargetNotFound = 20,
  SRCErrorAmbiguousTarget = 21,
  SRCErrorConnectFailed = 30,
  SRCErrorConnectTimeout = 31,
};

@interface SRCDevice : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *model;
@property(nonatomic, copy) NSString *deviceDescription;
@property(nonatomic, assign) BOOL offersDisplay;
@property(nonatomic, assign) BOOL connected;
@end

@interface SRCTarget : NSObject
@property(nonatomic, copy, nullable) NSString *name;
@property(nonatomic, copy, nullable) NSString *identifier;
+ (instancetype)targetWithName:(nullable NSString *)name identifier:(nullable NSString *)identifier;
@end

@interface SRCResolveResult : NSObject
@property(nonatomic, strong, nullable) SRCDevice *target;
@property(nonatomic, copy) NSArray<SRCDevice *> *matches;
@property(nonatomic, assign) BOOL ambiguous;
@property(nonatomic, assign) BOOL fuzzy;
@end

@interface SidecarController : NSObject
- (NSArray<SRCDevice *> *)listDevicesWithError:(NSError *_Nullable *_Nullable)error;
- (SRCResolveResult *)resolveTarget:(SRCTarget *)target devices:(NSArray<SRCDevice *> *)devices;
- (SRCStatus)statusForTarget:(SRCTarget *)target
                      device:(SRCDevice *_Nullable *_Nullable)device
                       error:(NSError *_Nullable *_Nullable)error;
- (BOOL)connectTarget:(SRCTarget *)target
               device:(SRCDevice *_Nullable *_Nullable)device
                error:(NSError *_Nullable *_Nullable)error;
+ (NSString *)logLineForDevice:(SRCDevice *)device prefix:(NSString *)prefix;
@end

NS_ASSUME_NONNULL_END
