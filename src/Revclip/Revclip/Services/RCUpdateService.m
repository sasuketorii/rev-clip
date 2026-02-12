//
//  RCUpdateService.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "RCUpdateService.h"

#import "RCConstants.h"

static NSTimeInterval const kRCDefaultUpdateCheckInterval = 86400.0;
static NSString * const kRCSparkleFrameworkName = @"Sparkle.framework";

@protocol RCSPUUpdater <NSObject>
@property (nonatomic, assign) BOOL automaticallyChecksForUpdates;
@property (nonatomic, assign) NSTimeInterval updateCheckInterval;
@end

@protocol RCSPUStandardUpdaterController <NSObject>
@property (nonatomic, readonly) id<RCSPUUpdater> updater;

@optional
- (instancetype)initWithStartingUpdater:(BOOL)startUpdater
                        updaterDelegate:(nullable id)updaterDelegate
                     userDriverDelegate:(nullable id)userDriverDelegate;
- (instancetype)initWithUpdaterDelegate:(nullable id)updaterDelegate
                     userDriverDelegate:(nullable id)userDriverDelegate;

@required
- (void)checkForUpdates:(nullable id)sender;
@end

@interface RCUpdateService ()

@property (nonatomic, strong, nullable) id<RCSPUStandardUpdaterController> updaterController;
@property (nonatomic, assign) BOOL didAttemptSetup;

@end

@implementation RCUpdateService

+ (instancetype)shared {
    static RCUpdateService *sharedService = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedService = [[self alloc] init];
    });
    return sharedService;
}

- (void)setupUpdater {
    @synchronized (self) {
        if (self.updaterController != nil || self.didAttemptSetup) {
            return;
        }
        self.didAttemptSetup = YES;

        if (![self loadSparkleFrameworkIfAvailable]) {
            return;
        }

        Class updaterControllerClass = NSClassFromString(@"SPUStandardUpdaterController");
        if (updaterControllerClass == Nil) {
            return;
        }

        self.updaterController = [self createUpdaterControllerWithClass:updaterControllerClass];
        if (self.updaterController == nil) {
            return;
        }

        [self applyStoredPreferencesToUpdater];
    }
}

- (void)checkForUpdates {
    [self setupUpdater];
    [self.updaterController checkForUpdates:nil];
}

- (BOOL)isAutomaticallyChecksForUpdates {
    NSNumber *storedValue = [NSUserDefaults.standardUserDefaults objectForKey:kRCEnableAutomaticCheckKey];
    if (storedValue == nil) {
        return YES;
    }
    return storedValue.boolValue;
}

- (void)setAutomaticallyChecksForUpdates:(BOOL)automaticallyChecksForUpdates {
    [NSUserDefaults.standardUserDefaults setBool:automaticallyChecksForUpdates forKey:kRCEnableAutomaticCheckKey];

    id<RCSPUUpdater> updater = [self currentUpdater];
    if (updater != nil && [updater respondsToSelector:@selector(setAutomaticallyChecksForUpdates:)]) {
        updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates;
    }
}

- (NSTimeInterval)updateCheckInterval {
    NSNumber *storedValue = [NSUserDefaults.standardUserDefaults objectForKey:kRCUpdateCheckIntervalKey];
    if (storedValue == nil || storedValue.doubleValue <= 0.0) {
        return kRCDefaultUpdateCheckInterval;
    }
    return storedValue.doubleValue;
}

- (void)setUpdateCheckInterval:(NSTimeInterval)updateCheckInterval {
    NSTimeInterval interval = updateCheckInterval;
    if (interval <= 0.0) {
        interval = kRCDefaultUpdateCheckInterval;
    }

    [NSUserDefaults.standardUserDefaults setDouble:interval forKey:kRCUpdateCheckIntervalKey];

    id<RCSPUUpdater> updater = [self currentUpdater];
    if (updater != nil && [updater respondsToSelector:@selector(setUpdateCheckInterval:)]) {
        updater.updateCheckInterval = interval;
    }
}

#pragma mark - Private

- (void)applyStoredPreferencesToUpdater {
    id<RCSPUUpdater> updater = [self currentUpdater];
    if (updater == nil) {
        return;
    }

    if ([updater respondsToSelector:@selector(setAutomaticallyChecksForUpdates:)]) {
        updater.automaticallyChecksForUpdates = self.automaticallyChecksForUpdates;
    }
    if ([updater respondsToSelector:@selector(setUpdateCheckInterval:)]) {
        updater.updateCheckInterval = self.updateCheckInterval;
    }
}

- (nullable id<RCSPUUpdater>)currentUpdater {
    id<RCSPUStandardUpdaterController> controller = self.updaterController;
    if (controller == nil || ![controller respondsToSelector:@selector(updater)]) {
        return nil;
    }

    id updater = controller.updater;
    if (updater == nil) {
        return nil;
    }

    return (id<RCSPUUpdater>)updater;
}

- (nullable id<RCSPUStandardUpdaterController>)createUpdaterControllerWithClass:(Class)updaterControllerClass {
    if ([updaterControllerClass instancesRespondToSelector:@selector(initWithStartingUpdater:updaterDelegate:userDriverDelegate:)]) {
        return [(id<RCSPUStandardUpdaterController>)[updaterControllerClass alloc] initWithStartingUpdater:YES
                                                                                             updaterDelegate:nil
                                                                                          userDriverDelegate:nil];
    }

    if ([updaterControllerClass instancesRespondToSelector:@selector(initWithUpdaterDelegate:userDriverDelegate:)]) {
        return [(id<RCSPUStandardUpdaterController>)[updaterControllerClass alloc] initWithUpdaterDelegate:nil
                                                                                          userDriverDelegate:nil];
    }

    return nil;
}

- (BOOL)loadSparkleFrameworkIfAvailable {
    NSBundle *sparkleBundle = [self sparkleFrameworkBundle];
    if (sparkleBundle == nil) {
        return NO;
    }

    if (sparkleBundle.loaded) {
        return YES;
    }

    NSError *error = nil;
    BOOL loaded = [sparkleBundle loadAndReturnError:&error];
    if (!loaded) {
        NSLog(@"[RCUpdateService] Failed to load Sparkle.framework: %@", error.localizedDescription ?: @"Unknown error");
    }
    return loaded;
}

- (nullable NSBundle *)sparkleFrameworkBundle {
    for (NSString *frameworkPath in [self sparkleFrameworkCandidatePaths]) {
        if (frameworkPath.length == 0) {
            continue;
        }

        NSBundle *bundle = [NSBundle bundleWithPath:frameworkPath];
        if (bundle != nil) {
            return bundle;
        }
    }

    return nil;
}

- (NSArray<NSString *> *)sparkleFrameworkCandidatePaths {
    NSMutableOrderedSet<NSString *> *paths = [NSMutableOrderedSet orderedSet];

    NSString *privateFrameworksPath = NSBundle.mainBundle.privateFrameworksPath;
    if (privateFrameworksPath.length > 0) {
        [paths addObject:[privateFrameworksPath stringByAppendingPathComponent:kRCSparkleFrameworkName]];
    }

    NSString *mainBundlePath = NSBundle.mainBundle.bundlePath;
    if (mainBundlePath.length > 0) {
        [paths addObject:[[mainBundlePath stringByAppendingPathComponent:@"Contents/Frameworks"]
                          stringByAppendingPathComponent:kRCSparkleFrameworkName]];

        [paths addObject:[[[mainBundlePath stringByAppendingPathComponent:@"../Frameworks"]
                           stringByAppendingPathComponent:kRCSparkleFrameworkName] stringByStandardizingPath]];
    }

    return paths.array;
}

@end
