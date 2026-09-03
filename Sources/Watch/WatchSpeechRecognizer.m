#import "WatchSpeechRecognizer.h"
#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>

static NSString * const WatchSpeechRecognizerErrorDomain = @"WatchSpeechRecognizer";

@interface WatchSpeechRecognizer ()
@property (nonatomic, strong, nullable) AVAudioEngine *engine;
@property (nonatomic, strong, nullable) SFSpeechAudioBufferRecognitionRequest *request;
@property (nonatomic, strong, nullable) SFSpeechRecognitionTask *task;
@property (nonatomic, copy, readwrite) NSString *transcript;
@property (nonatomic, assign) BOOL tapInstalled;
@end

@implementation WatchSpeechRecognizer

- (instancetype)init {
    self = [super init];
    if (self) {
        _transcript = @"";
    }
    return self;
}

- (void)dealloc {
    [self stopCanceling:YES];
}

- (SFSpeechRecognizer *)preferredRecognizer {
    SFSpeechRecognizer *german = [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:@"de_DE"]];
    if (german != nil) {
        return german;
    }
    return [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale currentLocale]];
}

- (void)requestPermissionsWithCompletion:(void (^)(BOOL granted, NSString * _Nullable denialMessage))completion {
    void (^finish)(BOOL, NSString *) = ^(BOOL granted, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(granted, message);
            }
        });
    };

    void (^afterSpeech)(SFSpeechRecognizerAuthorizationStatus) = ^(SFSpeechRecognizerAuthorizationStatus status) {
        if (status != SFSpeechRecognizerAuthorizationStatusAuthorized) {
            finish(NO, @"Spracherkennung nicht erlaubt.");
            return;
        }
        AVAudioSession *session = [AVAudioSession sharedInstance];
        AVAudioSessionRecordPermission permission = session.recordPermission;
        if (permission == AVAudioSessionRecordPermissionGranted) {
            finish(YES, nil);
            return;
        }
        if (permission == AVAudioSessionRecordPermissionDenied) {
            finish(NO, @"Mikrofon nicht erlaubt.");
            return;
        }
        [session requestRecordPermission:^(BOOL granted) {
            if (granted) {
                finish(YES, nil);
            } else {
                finish(NO, @"Mikrofon nicht erlaubt.");
            }
        }];
    };

    SFSpeechRecognizerAuthorizationStatus current = [SFSpeechRecognizer authorizationStatus];
    if (current != SFSpeechRecognizerAuthorizationStatusNotDetermined) {
        afterSpeech(current);
        return;
    }
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
        afterSpeech(status);
    }];
}

- (BOOL)startAndReturnError:(NSError **)error {
    [self stopCanceling:YES];
    self.transcript = @"";

    SFSpeechRecognizer *recognizer = [self preferredRecognizer];
    if (recognizer == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:WatchSpeechRecognizerErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"unavailable"}];
        }
        return NO;
    }

    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    NSError *sessionError = nil;
    if (![audioSession setCategory:AVAudioSessionCategoryRecord
                              mode:AVAudioSessionModeMeasurement
                           options:AVAudioSessionCategoryOptionDuckOthers
                             error:&sessionError]) {
        if (error != NULL) {
            *error = sessionError;
        }
        return NO;
    }
    if (![audioSession setActive:YES
                     withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                           error:&sessionError]) {
        if (error != NULL) {
            *error = sessionError;
        }
        return NO;
    }

    AVAudioEngine *engine = [[AVAudioEngine alloc] init];
    SFSpeechAudioBufferRecognitionRequest *request = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    request.shouldReportPartialResults = YES;
    if (recognizer.supportsOnDeviceRecognition) {
        request.requiresOnDeviceRecognition = YES;
    }

    AVAudioInputNode *input = engine.inputNode;
    [engine prepare];
    AVAudioFormat *format = [input outputFormatForBus:0];
    if (format.sampleRate == 0 || format.channelCount == 0) {
        format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:16000 channels:1];
        if (format == nil) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:WatchSpeechRecognizerErrorDomain
                                             code:1
                                         userInfo:@{NSLocalizedDescriptionKey: @"unavailable"}];
            }
            return NO;
        }
    }

    [input installTapOnBus:0
                bufferSize:1024
                    format:format
                     block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
                         (void)when;
                         [request appendAudioPCMBuffer:buffer];
                     }];
    self.tapInstalled = YES;
    self.engine = engine;
    self.request = request;

    if (![engine startAndReturnError:&sessionError]) {
        [self stopCanceling:YES];
        if (error != NULL) {
            *error = sessionError;
        }
        return NO;
    }

    __weak typeof(self) weakSelf = self;
    self.task = [recognizer recognitionTaskWithRequest:request
                                         resultHandler:^(SFSpeechRecognitionResult *result, NSError *taskError) {
                                             (void)taskError;
                                             if (result == nil) {
                                                 return;
                                             }
                                             NSString *text = result.bestTranscription.formattedString ?: @"";
                                             dispatch_async(dispatch_get_main_queue(), ^{
                                                 __strong typeof(weakSelf) strongSelf = weakSelf;
                                                 if (strongSelf == nil) {
                                                     return;
                                                 }
                                                 strongSelf.transcript = text;
                                                 if (strongSelf.transcriptHandler) {
                                                     strongSelf.transcriptHandler(text);
                                                 }
                                             });
                                         }];
    return YES;
}

- (void)stopCanceling:(BOOL)cancel {
    [self.request endAudio];
    if (cancel) {
        [self.task cancel];
    } else {
        [self.task finish];
    }
    self.task = nil;
    self.request = nil;
    if (self.engine != nil) {
        [self.engine stop];
        if (self.tapInstalled) {
            [self.engine.inputNode removeTapOnBus:0];
            self.tapInstalled = NO;
        }
    }
    self.engine = nil;
    NSError *err = nil;
    [[AVAudioSession sharedInstance] setActive:NO
                                   withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                         error:&err];
}

@end
