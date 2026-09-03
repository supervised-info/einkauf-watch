#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Watch-only ObjC-Shim um Speech/AVFoundation. Keine Speech-Typen in diesem Header,
/// damit der Swift-Bridging-Header das Speech-Modul nicht anfassen muss.
@interface WatchSpeechRecognizer : NSObject

@property (nonatomic, copy, nullable) void (^transcriptHandler)(NSString *transcript);
@property (nonatomic, copy, readonly) NSString *transcript;

- (void)requestPermissionsWithCompletion:(void (^)(BOOL granted, NSString * _Nullable denialMessage))completion
    NS_SWIFT_NAME(requestPermissions(completion:));
- (BOOL)startAndReturnError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(start());
- (void)stopCanceling:(BOOL)cancel NS_SWIFT_NAME(stop(canceling:));

@end

NS_ASSUME_NONNULL_END
