//
//  RCMoveToApplicationsService.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "RCMoveToApplicationsService.h"
#import <Cocoa/Cocoa.h>

static NSString * const kRCApplicationsBundlePath = @"/Applications/Revclip.app";

@interface RCMoveToApplicationsService ()

- (BOOL)isRunningFromBuildDirectory;
- (void)moveApplicationToApplicationsFromPath:(NSString *)sourcePath;
- (void)showMoveFailedAlertWithError:(NSError *)error;
- (void)relaunchApplicationAtPath:(NSString *)applicationPath;

@end

@implementation RCMoveToApplicationsService

+ (instancetype)shared {
    static RCMoveToApplicationsService *sharedService = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedService = [[self alloc] init];
    });
    return sharedService;
}

- (void)checkAndMoveIfNeeded {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self checkAndMoveIfNeeded];
        });
        return;
    }

    NSString *bundlePath = NSBundle.mainBundle.bundlePath;
    if (bundlePath.length == 0) {
        return;
    }

    if ([bundlePath hasPrefix:@"/Applications/"]) {
        return;
    }

    if ([self isRunningFromBuildDirectory]) {
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = NSLocalizedString(@"Move to Applications folder?", nil);
    alert.informativeText = NSLocalizedString(@"Revclip needs to be in the Applications folder to work properly. Would you like to move it there?", nil);
    [alert addButtonWithTitle:NSLocalizedString(@"Move to Applications", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Do Not Move", nil)];

    NSModalResponse response = [alert runModal];
    if (response != NSAlertFirstButtonReturn) {
        return;
    }

    [self moveApplicationToApplicationsFromPath:bundlePath];
}

- (BOOL)isRunningFromBuildDirectory {
    NSString *bundlePath = [NSBundle mainBundle].bundlePath;
    NSArray<NSString *> *buildPaths = @[@"DerivedData", @"Build/Products", @"Xcode"];
    for (NSString *path in buildPaths) {
        if ([bundlePath containsString:path]) {
            return YES;
        }
    }
    return NO;
}

- (void)moveApplicationToApplicationsFromPath:(NSString *)sourcePath {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *destinationURL = [NSURL fileURLWithPath:kRCApplicationsBundlePath];
    NSString *applicationsDirectoryPath = [kRCApplicationsBundlePath stringByDeletingLastPathComponent];
    NSString *temporaryBundlePath = [applicationsDirectoryPath stringByAppendingPathComponent:[NSString stringWithFormat:@".Revclip_installing_%@.app", [NSUUID UUID].UUIDString]];
    NSURL *temporaryBundleURL = [NSURL fileURLWithPath:temporaryBundlePath];

    [fileManager removeItemAtPath:temporaryBundlePath error:NULL];

    NSError *copyError = nil;
    if (![fileManager copyItemAtPath:sourcePath toPath:temporaryBundlePath error:&copyError]) {
        [self showMoveFailedAlertWithError:copyError];
        return;
    }

    NSError *replaceError = nil;
    if ([fileManager fileExistsAtPath:kRCApplicationsBundlePath]) {
        NSURL *resultingURL = nil;
        if (![fileManager replaceItemAtURL:destinationURL
                               withItemAtURL:temporaryBundleURL
                              backupItemName:nil
                                     options:0
                            resultingItemURL:&resultingURL
                                       error:&replaceError]) {
            [fileManager removeItemAtURL:temporaryBundleURL error:NULL];
            [self showMoveFailedAlertWithError:replaceError];
            return;
        }
    } else {
        if (![fileManager moveItemAtPath:temporaryBundlePath
                                  toPath:kRCApplicationsBundlePath
                                   error:&replaceError]) {
            [fileManager removeItemAtURL:temporaryBundleURL error:NULL];
            [self showMoveFailedAlertWithError:replaceError];
            return;
        }
    }

    [self relaunchApplicationAtPath:kRCApplicationsBundlePath];
}

- (void)relaunchApplicationAtPath:(NSString *)applicationPath {
    NSTask *openTask = [[NSTask alloc] init];
    openTask.executableURL = [NSURL fileURLWithPath:@"/usr/bin/open"];
    openTask.arguments = @[@"-n", applicationPath];

    NSError *launchError = nil;
    if (![openTask launchAndReturnError:&launchError]) {
        [self showMoveFailedAlertWithError:launchError];
        return;
    }

    [openTask waitUntilExit];
    if (openTask.terminationStatus == 0) {
        [NSApp terminate:nil];
        return;
    }

    NSError *error = [NSError errorWithDomain:@"com.revclip.movetoapplications"
                                         code:(NSInteger)openTask.terminationStatus
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: NSLocalizedString(@"Failed to relaunch the app from Applications.", nil),
                                         NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"open exited with status %d", openTask.terminationStatus],
                                     }];
    [self showMoveFailedAlertWithError:error];
}

- (void)showMoveFailedAlertWithError:(NSError *)error {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showMoveFailedAlertWithError:error];
        });
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleCritical;
    alert.messageText = NSLocalizedString(@"Could not move Revclip to Applications folder", nil);
    alert.informativeText = error.localizedDescription ?: NSLocalizedString(@"An unknown error occurred while moving Revclip.", nil);
    [alert addButtonWithTitle:NSLocalizedString(@"OK", nil)];
    [alert runModal];
}

@end
