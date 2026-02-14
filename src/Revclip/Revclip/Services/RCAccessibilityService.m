//
//  RCAccessibilityService.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "RCAccessibilityService.h"
#import <ApplicationServices/ApplicationServices.h>

@implementation RCAccessibilityService

+ (instancetype)shared {
    static RCAccessibilityService *sharedService = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedService = [[self alloc] init];
    });
    return sharedService;
}

- (BOOL)isAccessibilityEnabled {
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt : @NO};
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}

- (void)requestAccessibilityPermission {
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt : @YES};
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}

- (void)checkAndRequestAccessibilityWithAlert {
    if ([self isAccessibilityEnabled]) {
        return;
    }

    [self requestAccessibilityPermission];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = NSLocalizedString(@"Revclip requires Accessibility permission", nil);
    alert.informativeText = NSLocalizedString(@"Revclip needs Accessibility permission to paste clipboard items. Please enable it in System Settings > Privacy & Security > Accessibility.", nil);
    [alert addButtonWithTitle:NSLocalizedString(@"Open System Settings", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Later", nil)];

    NSModalResponse response = [alert runModal];
    if (response != NSAlertFirstButtonReturn) {
        return;
    }

    NSURL *settingsURL = nil;
    if (@available(macOS 13, *)) {
        settingsURL = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"];
    } else {
        settingsURL = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    }
    if (settingsURL != nil) {
        [[NSWorkspace sharedWorkspace] openURL:settingsURL];
    }
}

@end
