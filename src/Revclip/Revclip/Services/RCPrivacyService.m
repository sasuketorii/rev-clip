//
//  RCPrivacyService.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "RCPrivacyService.h"

NSString * const RCClipboardAccessStateDidChangeNotification = @"RCClipboardAccessStateDidChangeNotification";

static NSString * const kRCPrivacyServiceErrorDomain = @"com.revclip.privacy";

typedef NS_ENUM(NSInteger, RCPrivacyServiceErrorCode) {
    RCPrivacyServiceErrorCodeAPIUnavailable = 1,
    RCPrivacyServiceErrorCodeDetectionUnavailable = 2,
};

@interface RCPrivacyService ()

@property (nonatomic, assign) RCClipboardAccessState cachedClipboardAccessState;

@end

@implementation RCPrivacyService

+ (instancetype)shared {
    static RCPrivacyService *sharedService = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedService = [[self alloc] init];
    });
    return sharedService;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cachedClipboardAccessState = RCClipboardAccessStateUnknown;
    }
    return self;
}

#pragma mark - Public

- (RCClipboardAccessState)clipboardAccessState {
    RCClipboardAccessState state = [self resolvedClipboardAccessState];
    [self postClipboardAccessStateDidChangeIfNeeded:state];
    return state;
}

- (BOOL)canAccessClipboard {
    RCClipboardAccessState state = [self clipboardAccessState];
    return (state == RCClipboardAccessStateGranted || state == RCClipboardAccessStateUnknown);
}

- (BOOL)isClipboardPrivacyAPIAvailable {
    if (![self isMacOS16OrLater]) {
        return NO;
    }

    if (@available(macOS 16.0, *)) {
        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        return [pasteboard respondsToSelector:@selector(accessBehavior)]
            && [pasteboard respondsToSelector:@selector(detectPatternsForPatterns:completionHandler:)];
    }

    return NO;
}

- (void)detectClipboardPatternsWithCompletion:(void (^)(NSSet<NSString *> * _Nullable patterns, NSError * _Nullable error))completion {
    if (completion == nil) {
        return;
    }

    if (![self isClipboardPrivacyAPIAvailable]) {
        completion(nil, [self apiUnavailableError]);
        return;
    }

    if (@available(macOS 16.0, *)) {
        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        if (![pasteboard respondsToSelector:@selector(detectPatternsForPatterns:completionHandler:)]) {
            completion(nil, [self detectionUnavailableError]);
            return;
        }

        NSSet<NSPasteboardDetectionPattern> *patterns = [self supportedDetectionPatterns];
        if (patterns.count == 0) {
            completion([NSSet set], nil);
            return;
        }

        [pasteboard detectPatternsForPatterns:patterns
                            completionHandler:^(NSSet<NSPasteboardDetectionPattern> * _Nullable detectedPatterns,
                                                NSError * _Nullable error) {
            completion((NSSet<NSString *> *)detectedPatterns, error);
        }];
        return;
    }

    completion(nil, [self apiUnavailableError]);
}

- (void)showClipboardAccessGuidance {
    dispatch_block_t showAlert = ^{
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleWarning;
        alert.messageText = @"Revclip needs clipboard access";
        alert.informativeText = @"macOS requires explicit permission for clipboard access. Please allow Revclip to access the clipboard in System Settings.";
        [alert addButtonWithTitle:@"Open System Settings"];
        [alert addButtonWithTitle:@"Later"];

        NSModalResponse response = [alert runModal];
        if (response != NSAlertFirstButtonReturn) {
            return;
        }

        NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
        NSURL *clipboardSettingsURL = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Clipboard"];
        if (clipboardSettingsURL != nil && [workspace openURL:clipboardSettingsURL]) {
            return;
        }

        NSURL *privacySettingsURL = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security"];
        if (privacySettingsURL != nil) {
            [workspace openURL:privacySettingsURL];
        }
    };

    if ([NSThread isMainThread]) {
        showAlert();
    } else {
        dispatch_async(dispatch_get_main_queue(), showAlert);
    }
}

#pragma mark - Private

- (BOOL)isMacOS16OrLater {
    NSOperatingSystemVersion osVersion = [NSProcessInfo processInfo].operatingSystemVersion;
    return (osVersion.majorVersion >= 16);
}

- (RCClipboardAccessState)resolvedClipboardAccessState {
    if (![self isMacOS16OrLater]) {
        return RCClipboardAccessStateGranted;
    }

    if (@available(macOS 16.0, *)) {
        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        if (![pasteboard respondsToSelector:@selector(accessBehavior)]) {
            return RCClipboardAccessStateGranted;
        }

        NSPasteboardAccessBehavior behavior = pasteboard.accessBehavior;
        switch (behavior) {
            case NSPasteboardAccessBehaviorDefault:
            case NSPasteboardAccessBehaviorAsk:
                return RCClipboardAccessStateNotDetermined;

            case NSPasteboardAccessBehaviorAlwaysAllow:
                return RCClipboardAccessStateGranted;

            case NSPasteboardAccessBehaviorAlwaysDeny:
                return RCClipboardAccessStateDenied;
        }
    }

    return RCClipboardAccessStateUnknown;
}

- (NSSet<NSPasteboardDetectionPattern> *)supportedDetectionPatterns API_AVAILABLE(macos(15.4)) {
    NSMutableSet<NSPasteboardDetectionPattern> *patterns = [NSMutableSet set];

    if (NSPasteboardDetectionPatternProbableWebURL != nil) {
        [patterns addObject:NSPasteboardDetectionPatternProbableWebURL];
    }
    if (NSPasteboardDetectionPatternProbableWebSearch != nil) {
        [patterns addObject:NSPasteboardDetectionPatternProbableWebSearch];
    }
    if (NSPasteboardDetectionPatternNumber != nil) {
        [patterns addObject:NSPasteboardDetectionPatternNumber];
    }
    if (NSPasteboardDetectionPatternLink != nil) {
        [patterns addObject:NSPasteboardDetectionPatternLink];
    }
    if (NSPasteboardDetectionPatternPhoneNumber != nil) {
        [patterns addObject:NSPasteboardDetectionPatternPhoneNumber];
    }
    if (NSPasteboardDetectionPatternEmailAddress != nil) {
        [patterns addObject:NSPasteboardDetectionPatternEmailAddress];
    }
    if (NSPasteboardDetectionPatternPostalAddress != nil) {
        [patterns addObject:NSPasteboardDetectionPatternPostalAddress];
    }
    if (NSPasteboardDetectionPatternCalendarEvent != nil) {
        [patterns addObject:NSPasteboardDetectionPatternCalendarEvent];
    }
    if (NSPasteboardDetectionPatternShipmentTrackingNumber != nil) {
        [patterns addObject:NSPasteboardDetectionPatternShipmentTrackingNumber];
    }
    if (NSPasteboardDetectionPatternFlightNumber != nil) {
        [patterns addObject:NSPasteboardDetectionPatternFlightNumber];
    }
    if (NSPasteboardDetectionPatternMoneyAmount != nil) {
        [patterns addObject:NSPasteboardDetectionPatternMoneyAmount];
    }

    return [patterns copy];
}

- (void)postClipboardAccessStateDidChangeIfNeeded:(RCClipboardAccessState)newState {
    RCClipboardAccessState oldState = RCClipboardAccessStateUnknown;
    BOOL hasChange = NO;

    @synchronized (self) {
        oldState = self.cachedClipboardAccessState;
        if (oldState != newState) {
            self.cachedClipboardAccessState = newState;
            hasChange = YES;
        }
    }

    if (!hasChange) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:RCClipboardAccessStateDidChangeNotification
                                                            object:self
                                                          userInfo:@{
                                                              @"state": @(newState),
                                                              @"previousState": @(oldState),
                                                          }];
    });
}

- (NSError *)apiUnavailableError {
    return [NSError errorWithDomain:kRCPrivacyServiceErrorDomain
                               code:RCPrivacyServiceErrorCodeAPIUnavailable
                           userInfo:@{
                               NSLocalizedDescriptionKey: @"Clipboard privacy API is not available on this macOS version.",
                           }];
}

- (NSError *)detectionUnavailableError {
    return [NSError errorWithDomain:kRCPrivacyServiceErrorDomain
                               code:RCPrivacyServiceErrorCodeDetectionUnavailable
                           userInfo:@{
                               NSLocalizedDescriptionKey: @"Pattern detection is not available for this pasteboard.",
                           }];
}

@end
