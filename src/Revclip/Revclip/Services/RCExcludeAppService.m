//
//  RCExcludeAppService.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "RCExcludeAppService.h"

#import <Cocoa/Cocoa.h>

#import "RCConstants.h"

@interface RCExcludeAppService ()

@property (nonatomic, strong) NSUserDefaults *userDefaults;

@end

@implementation RCExcludeAppService

+ (instancetype)shared {
    static RCExcludeAppService *sharedService = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedService = [[self alloc] init];
    });
    return sharedService;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _userDefaults = [NSUserDefaults standardUserDefaults];
    }
    return self;
}

#pragma mark - Public

- (BOOL)shouldExcludeCurrentApp {
    NSString *bundleIdentifier = [self frontmostApplicationBundleIdentifier];
    if (bundleIdentifier.length == 0) {
        return NO;
    }

    return [[self excludedBundleIdentifiers] containsObject:bundleIdentifier];
}

- (NSArray<NSString *> *)excludedBundleIdentifiers {
    @synchronized(self) {
        NSArray *storedIdentifiers = [self.userDefaults objectForKey:kRCExcludeApplications];
        if (![storedIdentifiers isKindOfClass:[NSArray class]]) {
            return @[];
        }

        return [self sanitizedBundleIdentifiersFromArray:storedIdentifiers];
    }
}

- (void)setExcludedBundleIdentifiers:(NSArray<NSString *> *)identifiers {
    @synchronized(self) {
        NSArray<NSString *> *sanitizedIdentifiers = [self sanitizedBundleIdentifiersFromArray:identifiers ?: @[]];
        [self.userDefaults setObject:sanitizedIdentifiers forKey:kRCExcludeApplications];
    }
}

- (void)addExcludedBundleIdentifier:(NSString *)bundleId {
    NSString *normalizedBundleId = [self normalizedBundleIdentifier:bundleId];
    if (normalizedBundleId.length == 0) {
        return;
    }

    @synchronized(self) {
        NSArray<NSString *> *currentIdentifiers = [self excludedBundleIdentifiers];
        if ([currentIdentifiers containsObject:normalizedBundleId]) {
            return;
        }

        NSMutableArray<NSString *> *updatedIdentifiers = [currentIdentifiers mutableCopy];
        [updatedIdentifiers addObject:normalizedBundleId];
        [self setExcludedBundleIdentifiers:[updatedIdentifiers copy]];
    }
}

- (void)removeExcludedBundleIdentifier:(NSString *)bundleId {
    NSString *normalizedBundleId = [self normalizedBundleIdentifier:bundleId];
    if (normalizedBundleId.length == 0) {
        return;
    }

    @synchronized(self) {
        NSMutableArray<NSString *> *updatedIdentifiers = [[self excludedBundleIdentifiers] mutableCopy];
        [updatedIdentifiers removeObject:normalizedBundleId];
        [self setExcludedBundleIdentifiers:[updatedIdentifiers copy]];
    }
}

#pragma mark - Private

- (NSString *)frontmostApplicationBundleIdentifier {
    __block NSString *bundleIdentifier = @"";
    dispatch_block_t resolveBlock = ^{
        NSRunningApplication *application = [NSWorkspace sharedWorkspace].frontmostApplication;
        bundleIdentifier = application.bundleIdentifier ?: @"";
    };

    if ([NSThread isMainThread]) {
        resolveBlock();
    } else {
        dispatch_sync(dispatch_get_main_queue(), resolveBlock);
    }

    return bundleIdentifier;
}

- (NSArray<NSString *> *)sanitizedBundleIdentifiersFromArray:(NSArray *)identifiers {
    if (identifiers.count == 0) {
        return @[];
    }

    NSMutableArray<NSString *> *sanitizedIdentifiers = [NSMutableArray arrayWithCapacity:identifiers.count];
    NSMutableSet<NSString *> *seenIdentifiers = [NSMutableSet setWithCapacity:identifiers.count];

    for (id identifier in identifiers) {
        if (![identifier isKindOfClass:[NSString class]]) {
            continue;
        }

        NSString *normalizedIdentifier = [self normalizedBundleIdentifier:identifier];
        if (normalizedIdentifier.length == 0 || [seenIdentifiers containsObject:normalizedIdentifier]) {
            continue;
        }

        [seenIdentifiers addObject:normalizedIdentifier];
        [sanitizedIdentifiers addObject:normalizedIdentifier];
    }

    return [sanitizedIdentifiers copy];
}

- (NSString *)normalizedBundleIdentifier:(NSString *)bundleIdentifier {
    if (![bundleIdentifier isKindOfClass:[NSString class]]) {
        return @"";
    }

    NSString *trimmed = [bundleIdentifier stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed ?: @"";
}

@end
