//
//  RCDataCleanService.m
//  Revpy
//
//  Copyright (c) 2024-2026 Revpy. All rights reserved.
//

#import "RCDataCleanService.h"

#import "RCClipItem.h"
#import "RCConstants.h"
#import "RCDatabaseManager.h"
#import "RCUtilities.h"

static NSTimeInterval const kRCCleanupInterval = 30.0 * 60.0;
static NSInteger const kRCDefaultMaxHistorySize = 30;
static NSTimeInterval const kRCOrphanFileMinimumAge = 60.0;
static NSString * const kRCClipDataFileExtension = @"rcclip";
static NSString * const kRCThumbFileExtension = @"thumb";
static NSString * const kRCLegacyThumbnailFileExtension = @"thumbnail.tiff";
static NSString * const kRCThumbFileSuffix = @".thumb";
static NSString * const kRCLegacyThumbnailFileSuffix = @".thumbnail.tiff";

@interface RCDataCleanService ()

@property (nonatomic, strong, nullable) dispatch_source_t cleanupTimer;
@property (nonatomic, strong) dispatch_queue_t cleanupQueue;

@end

@implementation RCDataCleanService

+ (instancetype)shared {
    static RCDataCleanService *sharedService = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedService = [[self alloc] init];
    });
    return sharedService;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cleanupQueue = dispatch_queue_create("com.revclip.data-cleanup", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc {
    [self stopCleanupTimer];
}

- (void)startCleanupTimer {
    @synchronized (self) {
        if (self.cleanupTimer != nil) {
            return;
        }

        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.cleanupQueue);
        if (timer == nil) {
            return;
        }

        uint64_t interval = (uint64_t)(kRCCleanupInterval * (double)NSEC_PER_SEC);
        uint64_t leeway = interval / 10;
        dispatch_source_set_timer(timer,
                                  dispatch_time(DISPATCH_TIME_NOW, (int64_t)interval),
                                  interval,
                                  leeway);

        __weak typeof(self) weakSelf = self;
        dispatch_source_set_event_handler(timer, ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            [strongSelf performCleanupOnCleanupQueue];
        });

        self.cleanupTimer = timer;
        dispatch_resume(timer);

        // G3-012: 初期 cleanup を @synchronized ブロック内で dispatch して
        // タイマー設定と初期クリーンアップの間に競合が発生しないようにする。
        dispatch_async(self.cleanupQueue, ^{
            [self performCleanupOnCleanupQueue];
        });
    }
}

- (void)stopCleanupTimer {
    dispatch_source_t timer = nil;

    @synchronized (self) {
        timer = self.cleanupTimer;
        self.cleanupTimer = nil;
    }

    if (timer != nil) {
        dispatch_source_cancel(timer);
    }
}

- (void)performCleanup {
    dispatch_async(self.cleanupQueue, ^{
        [self performCleanupOnCleanupQueue];
    });
}

#pragma mark - Private

- (void)performCleanupOnCleanupQueue {
    RCDatabaseManager *databaseManager = [RCDatabaseManager shared];
    if (![databaseManager setupDatabase]) {
        return;
    }

    [self trimHistoryIfNeededWithDatabaseManager:databaseManager];
    [self removeOrphanClipFilesWithDatabaseManager:databaseManager];
}

- (void)trimHistoryIfNeededWithDatabaseManager:(RCDatabaseManager *)databaseManager {
    NSInteger maxHistorySize = [self integerPreferenceForKey:kRCPrefMaxHistorySizeKey
                                                defaultValue:kRCDefaultMaxHistorySize];
    if (maxHistorySize <= 0) {
        return;
    }

    NSInteger count = [databaseManager clipItemCount];
    if (count <= maxHistorySize) {
        return;
    }

    NSArray<NSDictionary *> *clipDictionaries = [databaseManager fetchClipItemsWithLimit:count];
    if (clipDictionaries.count <= (NSUInteger)maxHistorySize) {
        return;
    }

    for (NSUInteger index = clipDictionaries.count; index > (NSUInteger)maxHistorySize; index--) {
        RCClipItem *oldItem = [[RCClipItem alloc] initWithDictionary:clipDictionaries[index - 1]];
        if (oldItem.dataHash.length == 0) {
            continue;
        }

        if ([databaseManager deleteClipItemWithDataHash:oldItem.dataHash]) {
            [self removeFilesForClipItem:oldItem];
        }
    }
}

- (void)removeOrphanClipFilesWithDatabaseManager:(RCDatabaseManager *)databaseManager {
    NSString *clipDirectoryPath = [RCUtilities clipDataDirectoryPath];
    if (![RCUtilities ensureDirectoryExists:clipDirectoryPath]) {
        return;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *directoryError = nil;
    NSArray<NSString *> *fileNames = [fileManager contentsOfDirectoryAtPath:clipDirectoryPath
                                                                       error:&directoryError];
    if (fileNames == nil) {
        NSLog(@"[RCDataCleanService] Failed to enumerate clip directory '%@': %@",
              clipDirectoryPath, directoryError.localizedDescription);
        return;
    }

    NSMutableSet<NSString *> *databaseClipPaths = [NSMutableSet set];
    NSMutableSet<NSString *> *databaseThumbnailPaths = [NSMutableSet set];
    NSInteger count = [databaseManager clipItemCount];
    if (count > 0) {
        NSArray<NSDictionary *> *clipDictionaries = [databaseManager fetchClipItemsWithLimit:count];
        for (NSDictionary *clipDictionary in clipDictionaries) {
            RCClipItem *clipItem = [[RCClipItem alloc] initWithDictionary:clipDictionary];
            NSString *standardizedPath = [self standardizedPath:clipItem.dataPath];
            if (standardizedPath.length > 0) {
                [databaseClipPaths addObject:standardizedPath];
            }

            NSString *standardizedThumbnailPath = [self standardizedPath:clipItem.thumbnailPath];
            if (standardizedThumbnailPath.length > 0) {
                [databaseThumbnailPaths addObject:standardizedThumbnailPath];
            }
        }
    }

    for (NSString *fileName in fileNames) {
        if (![self isClipDataFileName:fileName]) {
            continue;
        }

        NSString *clipFilePath = [self standardizedPath:[clipDirectoryPath stringByAppendingPathComponent:fileName]];
        if (clipFilePath.length == 0) {
            continue;
        }

        if ([databaseClipPaths containsObject:clipFilePath]) {
            continue;
        }

        if (![self isOldEnoughForOrphanDeletionAtPath:clipFilePath fileManager:fileManager]) {
            continue;
        }

        [self removeFileAtPath:clipFilePath];
        [self removeCompanionThumbFilesForClipPath:clipFilePath];
    }

    for (NSString *fileName in fileNames) {
        if (![self isThumbnailFileName:fileName]) {
            continue;
        }

        NSString *thumbnailFilePath = [self standardizedPath:[clipDirectoryPath stringByAppendingPathComponent:fileName]];
        if (thumbnailFilePath.length == 0) {
            continue;
        }

        if ([databaseThumbnailPaths containsObject:thumbnailFilePath]) {
            continue;
        }

        NSString *correspondingClipPath = [self clipPathForThumbnailFileName:fileName
                                                             clipDirectoryPath:clipDirectoryPath];
        if (correspondingClipPath.length > 0 && [databaseClipPaths containsObject:correspondingClipPath]) {
            continue;
        }
        if (correspondingClipPath.length > 0 && [self isRegularFileAtPath:correspondingClipPath fileManager:fileManager]) {
            continue;
        }

        if (![self isOldEnoughForOrphanDeletionAtPath:thumbnailFilePath fileManager:fileManager]) {
            continue;
        }

        [self removeFileAtPath:thumbnailFilePath];
    }
}

- (void)removeFilesForClipItem:(RCClipItem *)clipItem {
    if (clipItem == nil) {
        return;
    }

    [self removeFileAtPath:clipItem.dataPath];
    [self removeFileAtPath:clipItem.thumbnailPath];
    [self removeCompanionThumbFilesForClipPath:clipItem.dataPath];
}

- (void)removeCompanionThumbFilesForClipPath:(NSString *)clipPath {
    NSString *standardizedClipPath = [self standardizedPath:clipPath];
    if (standardizedClipPath.length == 0) {
        return;
    }

    NSString *basePath = [standardizedClipPath stringByDeletingPathExtension];
    if (basePath.length == 0) {
        return;
    }

    NSString *thumbPath = [basePath stringByAppendingPathExtension:kRCThumbFileExtension];
    NSString *legacyThumbnailPath = [basePath stringByAppendingPathExtension:kRCLegacyThumbnailFileExtension];

    [self removeFileAtPath:thumbPath];
    [self removeFileAtPath:legacyThumbnailPath];
}

- (BOOL)isClipDataFileName:(NSString *)fileName {
    NSString *fileExtension = [[fileName pathExtension] lowercaseString];
    return [fileExtension isEqualToString:kRCClipDataFileExtension];
}

- (BOOL)isThumbnailFileName:(NSString *)fileName {
    NSString *lowercaseFileName = [fileName lowercaseString];
    return [lowercaseFileName hasSuffix:kRCThumbFileSuffix]
    || [lowercaseFileName hasSuffix:kRCLegacyThumbnailFileSuffix];
}

- (NSString *)clipPathForThumbnailFileName:(NSString *)thumbnailFileName
                         clipDirectoryPath:(NSString *)clipDirectoryPath {
    if (thumbnailFileName.length == 0 || clipDirectoryPath.length == 0) {
        return @"";
    }

    NSString *lowercaseFileName = [thumbnailFileName lowercaseString];
    NSString *baseFileName = nil;
    if ([lowercaseFileName hasSuffix:kRCThumbFileSuffix] && thumbnailFileName.length > kRCThumbFileSuffix.length) {
        baseFileName = [thumbnailFileName substringToIndex:(thumbnailFileName.length - kRCThumbFileSuffix.length)];
    } else if ([lowercaseFileName hasSuffix:kRCLegacyThumbnailFileSuffix]
               && thumbnailFileName.length > kRCLegacyThumbnailFileSuffix.length) {
        baseFileName = [thumbnailFileName substringToIndex:(thumbnailFileName.length - kRCLegacyThumbnailFileSuffix.length)];
    } else {
        return @"";
    }

    NSString *clipFileName = [baseFileName stringByAppendingPathExtension:kRCClipDataFileExtension];
    return [self standardizedPath:[clipDirectoryPath stringByAppendingPathComponent:clipFileName]];
}

- (BOOL)isRegularFileAtPath:(NSString *)path fileManager:(NSFileManager *)fileManager {
    NSString *standardizedPath = [self standardizedPath:path];
    if (standardizedPath.length == 0) {
        return NO;
    }

    BOOL isDirectory = NO;
    return [fileManager fileExistsAtPath:standardizedPath isDirectory:&isDirectory] && !isDirectory;
}

- (BOOL)isOldEnoughForOrphanDeletionAtPath:(NSString *)path fileManager:(NSFileManager *)fileManager {
    NSString *standardizedPath = [self standardizedPath:path];
    if (standardizedPath.length == 0) {
        return NO;
    }

    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:standardizedPath isDirectory:&isDirectory] || isDirectory) {
        return NO;
    }

    NSError *attributesError = nil;
    NSDictionary *attributes = [fileManager attributesOfItemAtPath:standardizedPath error:&attributesError];
    if (attributes == nil) {
        NSLog(@"[RCDataCleanService] Failed to get file attributes '%@': %@",
              standardizedPath, attributesError.localizedDescription);
        return NO;
    }

    NSDate *modifiedDate = attributes[NSFileModificationDate];
    if (![modifiedDate isKindOfClass:[NSDate class]]) {
        return NO;
    }

    NSTimeInterval age = [[NSDate date] timeIntervalSinceDate:modifiedDate];
    return age >= kRCOrphanFileMinimumAge;
}

- (void)removeFileAtPath:(NSString *)path {
    NSString *standardizedPath = [self standardizedPath:path];
    if (standardizedPath.length == 0) {
        return;
    }

    NSString *canonicalPath = [self canonicalPath:standardizedPath];
    NSString *canonicalClipDataDirectoryPath = [self canonicalPath:[RCUtilities clipDataDirectoryPath]];
    if (![self isPath:canonicalPath withinDirectory:canonicalClipDataDirectoryPath]) {
        NSLog(@"[RCDataCleanService] Refusing to delete path outside clip data directory: '%@'", canonicalPath);
        return;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:standardizedPath isDirectory:&isDirectory] || isDirectory) {
        return;
    }

    NSError *error = nil;
    BOOL removed = [fileManager removeItemAtPath:standardizedPath error:&error];
    if (!removed) {
        NSLog(@"[RCDataCleanService] Failed to remove file '%@': %@",
              standardizedPath, error.localizedDescription);
    }
}

- (NSInteger)integerPreferenceForKey:(NSString *)key defaultValue:(NSInteger)defaultValue {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id value = [defaults objectForKey:key];
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value integerValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value integerValue];
    }
    return defaultValue;
}

- (NSString *)standardizedPath:(NSString *)path {
    if (path.length == 0) {
        return @"";
    }
    return [[path stringByExpandingTildeInPath] stringByStandardizingPath];
}

- (NSString *)canonicalPath:(NSString *)path {
    NSString *standardizedPath = [self standardizedPath:path];
    if (standardizedPath.length == 0) {
        return @"";
    }

    return [standardizedPath stringByResolvingSymlinksInPath];
}

- (BOOL)isPath:(NSString *)path withinDirectory:(NSString *)directoryPath {
    if (path.length == 0 || directoryPath.length == 0) {
        return NO;
    }

    if ([path isEqualToString:directoryPath]) {
        return YES;
    }

    NSString *directoryPrefix = [directoryPath hasSuffix:@"/"]
        ? directoryPath
        : [directoryPath stringByAppendingString:@"/"];
    return [path hasPrefix:directoryPrefix];
}

@end
