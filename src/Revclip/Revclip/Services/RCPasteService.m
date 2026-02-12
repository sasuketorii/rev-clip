//
//  RCPasteService.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "RCPasteService.h"

#import <ApplicationServices/ApplicationServices.h>

#import "RCAccessibilityService.h"
#import "RCClipData.h"
#import "RCConstants.h"

static NSTimeInterval const kRCPasteMenuCloseDelay = 0.05;

@interface RCPasteService ()

- (BOOL)isPressedModifier:(NSInteger)flag;
- (BOOL)boolPreferenceForKey:(NSString *)key defaultValue:(BOOL)defaultValue;
- (NSInteger)integerPreferenceForKey:(NSString *)key defaultValue:(NSInteger)defaultValue;
- (void)writePlainTextToPasteboard:(NSString *)text;
- (void)sendPasteKeyStrokeToApplication:(nullable NSRunningApplication *)application;

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

    BOOL shouldSendPasteCommand = [self boolPreferenceForKey:kRCPrefInputPasteCommandKey defaultValue:YES];
    BOOL pastePlainTextEnabled = [self boolPreferenceForKey:kRCBetaPastePlainText defaultValue:YES];
    NSInteger plainTextModifier = [self integerPreferenceForKey:kRCBetaPastePlainTextModifier defaultValue:0];
    if (pastePlainTextEnabled
        && clipData.stringValue.length > 0
        && [self isPressedModifier:plainTextModifier]) {
        [self writePlainTextToPasteboard:clipData.stringValue];
        if (!shouldSendPasteCommand) {
            return;
        }
        NSRunningApplication *activeApplication = [NSWorkspace sharedWorkspace].frontmostApplication;
        [self sendPasteKeyStrokeToApplication:activeApplication];
        return;
    }

    [clipData writeToPasteboard:[NSPasteboard generalPasteboard]];

    if (!shouldSendPasteCommand) {
        return;
    }

    NSRunningApplication *activeApplication = [NSWorkspace sharedWorkspace].frontmostApplication;
    [self sendPasteKeyStrokeToApplication:activeApplication];
}

- (void)pastePlainText:(NSString *)text {
    BOOL shouldSendPasteCommand = [self boolPreferenceForKey:kRCPrefInputPasteCommandKey defaultValue:YES];

    [self writePlainTextToPasteboard:text];

    if (!shouldSendPasteCommand) {
        return;
    }

    NSRunningApplication *activeApplication = [NSWorkspace sharedWorkspace].frontmostApplication;
    [self sendPasteKeyStrokeToApplication:activeApplication];
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

    if (keyDown != NULL) {
        CGEventSetFlags(keyDown, kCGEventFlagMaskCommand);
        CGEventPost(kCGAnnotatedSessionEventTap, keyDown);
        CFRelease(keyDown);
    }
    if (keyUp != NULL) {
        CGEventSetFlags(keyUp, kCGEventFlagMaskCommand);
        CGEventPost(kCGAnnotatedSessionEventTap, keyUp);
        CFRelease(keyUp);
    }

    CFRelease(source);
}

#pragma mark - Private

- (void)sendPasteKeyStrokeToApplication:(nullable NSRunningApplication *)application {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRCPasteMenuCloseDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (application != nil && !application.terminated) {
            [application activateWithOptions:0];
        }
        [self sendPasteKeyStroke];
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
