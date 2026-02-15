//
//  RCPasteService.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "RCPasteService.h"

#import <ApplicationServices/ApplicationServices.h>

#import "RCAccessibilityService.h"
#import "RCClipboardService.h"
#import "RCClipData.h"
#import "RCConstants.h"

static NSTimeInterval const kRCPasteMenuCloseDelay = 0.05;
static NSTimeInterval const kRCPasteActivationPollInterval = 0.01;
static NSTimeInterval const kRCPasteActivationTimeout = 0.5;

@interface RCPasteService ()

@property (nonatomic, assign) NSUInteger pasteGeneration;

- (BOOL)isPressedModifier:(NSInteger)flag;
- (BOOL)boolPreferenceForKey:(NSString *)key defaultValue:(BOOL)defaultValue;
- (NSInteger)integerPreferenceForKey:(NSString *)key defaultValue:(NSInteger)defaultValue;
- (void)writePlainTextToPasteboard:(NSString *)text;
- (void)sendPasteKeyStrokeToApplication:(nullable NSRunningApplication *)application
                        pasteGeneration:(NSUInteger)pasteGeneration;
- (void)sendPasteKeyStrokeWhenApplicationIsReady:(nullable NSRunningApplication *)application
                                        timeoutAt:(CFAbsoluteTime)timeoutAt
                                  pasteGeneration:(NSUInteger)pasteGeneration;
- (void)clearPastingInternallyFlagImmediatelyForGeneration:(NSUInteger)pasteGeneration;

@end

@implementation RCPasteService

+ (instancetype)shared {
    static RCPasteService *sharedService = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedService = [[self alloc] init];
    });
    return sharedService;
}

- (void)pasteClipData:(RCClipData *)clipData {
    if (clipData == nil) {
        return;
    }

    // G3-013: メインスレッド保証。メインスレッド以外から呼ばれた場合は dispatch_async で回す。
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self pasteClipData:clipData];
        });
        return;
    }

    // G3-004: 内部ペースト操作中フラグをセット（ClipboardService のポーリングで重複登録を防ぐ）
    [RCClipboardService shared].isPastingInternally = YES;
    NSUInteger currentPasteGeneration = ++self.pasteGeneration;

    BOOL shouldSendPasteCommand = [self boolPreferenceForKey:kRCPrefInputPasteCommandKey defaultValue:YES];
    BOOL pastePlainTextEnabled = [self boolPreferenceForKey:kRCBetaPastePlainText defaultValue:YES];
    NSInteger plainTextModifier = [self integerPreferenceForKey:kRCBetaPastePlainTextModifier defaultValue:0];
    if (pastePlainTextEnabled
        && clipData.stringValue.length > 0
        && [self isPressedModifier:plainTextModifier]) {
        [self writePlainTextToPasteboard:clipData.stringValue];
        if (!shouldSendPasteCommand) {
            [self clearPastingInternallyFlagImmediatelyForGeneration:currentPasteGeneration];
            return;
        }
        NSRunningApplication *activeApplication = [NSWorkspace sharedWorkspace].frontmostApplication;
        if ([activeApplication.bundleIdentifier isEqualToString:NSBundle.mainBundle.bundleIdentifier]) {
            activeApplication = nil;
        }
        [self sendPasteKeyStrokeToApplication:activeApplication
                              pasteGeneration:currentPasteGeneration];
        return;
    }

    BOOL wrote = [clipData writeToPasteboard:[NSPasteboard generalPasteboard]];
    if (!wrote) {
        [self clearPastingInternallyFlagAfterDelayForGeneration:currentPasteGeneration];
        return;
    }

    if (!shouldSendPasteCommand) {
        [self clearPastingInternallyFlagImmediatelyForGeneration:currentPasteGeneration];
        return;
    }

    NSRunningApplication *activeApplication = [NSWorkspace sharedWorkspace].frontmostApplication;
    if ([activeApplication.bundleIdentifier isEqualToString:NSBundle.mainBundle.bundleIdentifier]) {
        activeApplication = nil;
    }
    [self sendPasteKeyStrokeToApplication:activeApplication
                          pasteGeneration:currentPasteGeneration];
}

- (void)pastePlainText:(NSString *)text {
    // G3-013: メインスレッド保証
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self pastePlainText:text];
        });
        return;
    }

    // G3-004: 内部ペースト操作中フラグをセット
    [RCClipboardService shared].isPastingInternally = YES;
    NSUInteger currentPasteGeneration = ++self.pasteGeneration;

    BOOL shouldSendPasteCommand = [self boolPreferenceForKey:kRCPrefInputPasteCommandKey defaultValue:YES];

    [self writePlainTextToPasteboard:text];

    if (!shouldSendPasteCommand) {
        [self clearPastingInternallyFlagImmediatelyForGeneration:currentPasteGeneration];
        return;
    }

    NSRunningApplication *activeApplication = [NSWorkspace sharedWorkspace].frontmostApplication;
    if ([activeApplication.bundleIdentifier isEqualToString:NSBundle.mainBundle.bundleIdentifier]) {
        activeApplication = nil;
    }
    [self sendPasteKeyStrokeToApplication:activeApplication
                          pasteGeneration:currentPasteGeneration];
}

- (void)sendPasteKeyStroke {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self sendPasteKeyStroke];
        });
        return;
    }

    if (![[RCAccessibilityService shared] isAccessibilityEnabled]) {
        NSLog(@"[RCPasteService] Accessibility permission is required to send paste keystroke.");
        return;
    }

    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    if (source == NULL) {
        NSLog(@"[RCPasteService] Failed to create CGEvent source.");
        return;
    }

    CGEventRef keyDown = CGEventCreateKeyboardEvent(source, (CGKeyCode)9, true);
    CGEventRef keyUp = CGEventCreateKeyboardEvent(source, (CGKeyCode)9, false);

    // G3-005: 両方のイベント作成が成功した場合のみ post する。
    // 片方だけ post するとキー入力が不完全になる。
    if (keyDown != NULL && keyUp != NULL) {
        CGEventSetFlags(keyDown, kCGEventFlagMaskCommand);
        CGEventSetFlags(keyUp, kCGEventFlagMaskCommand);
        CGEventPost(kCGAnnotatedSessionEventTap, keyDown);
        CGEventPost(kCGAnnotatedSessionEventTap, keyUp);
    } else {
        NSLog(@"[RCPasteService] Failed to create keyboard events for paste keystroke.");
    }

    if (keyDown != NULL) {
        CFRelease(keyDown);
    }
    if (keyUp != NULL) {
        CFRelease(keyUp);
    }

    CFRelease(source);
}

#pragma mark - Private

- (void)sendPasteKeyStrokeToApplication:(nullable NSRunningApplication *)application
                        pasteGeneration:(NSUInteger)pasteGeneration {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRCPasteMenuCloseDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        CFAbsoluteTime timeoutAt = CFAbsoluteTimeGetCurrent() + kRCPasteActivationTimeout;
        if (application != nil && !application.terminated) {
            [application activateWithOptions:0];
        }
        [self sendPasteKeyStrokeWhenApplicationIsReady:application
                                             timeoutAt:timeoutAt
                                       pasteGeneration:pasteGeneration];
    });
}

- (void)sendPasteKeyStrokeWhenApplicationIsReady:(nullable NSRunningApplication *)application
                                        timeoutAt:(CFAbsoluteTime)timeoutAt
                                  pasteGeneration:(NSUInteger)pasteGeneration {
    if (application == nil || application.terminated || application.active || CFAbsoluteTimeGetCurrent() >= timeoutAt) {
        [self sendPasteKeyStroke];
        [self clearPastingInternallyFlagAfterDelayForGeneration:pasteGeneration];
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRCPasteActivationPollInterval * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self sendPasteKeyStrokeWhenApplicationIsReady:application
                                             timeoutAt:timeoutAt
                                       pasteGeneration:pasteGeneration];
    });
}

// G3-004: ペースト操作完了後に isPastingInternally フラグをクリアする。
// ClipboardService のポーリング間隔 (0.5s) より長い遅延で解除して
// ポーリングが確実にスキップされるようにする。
- (void)clearPastingInternallyFlagImmediatelyForGeneration:(NSUInteger)pasteGeneration {
    if (self.pasteGeneration == pasteGeneration) {
        [RCClipboardService shared].isPastingInternally = NO;
    }
}

- (void)clearPastingInternallyFlagAfterDelayForGeneration:(NSUInteger)pasteGeneration {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (self.pasteGeneration == pasteGeneration) {
            [RCClipboardService shared].isPastingInternally = NO;
        }
    });
}

- (BOOL)isPressedModifier:(NSInteger)flag {
    NSEventModifierFlags flags = [NSEvent modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask;
    switch (flag) {
        case 0:
            return (flags & NSEventModifierFlagCommand) != 0;
        case 1:
            return (flags & NSEventModifierFlagShift) != 0;
        case 2:
            return (flags & NSEventModifierFlagControl) != 0;
        case 3:
            return (flags & NSEventModifierFlagOption) != 0;
        default:
            return NO;
    }
}

- (BOOL)boolPreferenceForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
    id rawValue = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if ([rawValue isKindOfClass:[NSNumber class]]) {
        return [rawValue boolValue];
    }
    if ([rawValue isKindOfClass:[NSString class]]) {
        return [(NSString *)rawValue boolValue];
    }
    return defaultValue;
}

- (NSInteger)integerPreferenceForKey:(NSString *)key defaultValue:(NSInteger)defaultValue {
    id rawValue = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if ([rawValue isKindOfClass:[NSNumber class]]) {
        return [rawValue integerValue];
    }
    if ([rawValue isKindOfClass:[NSString class]]) {
        return [(NSString *)rawValue integerValue];
    }
    return defaultValue;
}

- (void)writePlainTextToPasteboard:(NSString *)text {
    NSString *safeText = text ?: @"";
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:safeText forType:NSPasteboardTypeString];
}

@end
