//
//  RCScreenshotMonitorService.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "RCScreenshotMonitorService.h"

#import <Cocoa/Cocoa.h>

#import "RCConstants.h"
#import "RCClipData.h"
#import "RCClipItem.h"
#import "RCClipboardService.h"
#import "RCDatabaseManager.h"
#import "RCUtilities.h"
#import "NSImage+Resize.h"

static NSString * const kRCMetadataItemIsScreenCapture = @"kMDItemIsScreenCapture";
static NSString * const kRCMetadataItemFSCreationDate = @"kMDItemFSCreationDate";
static NSString * const kRCMetadataItemPath = @"kMDItemPath";
static NSString * const kRCScreenshotClipDataFileExtension = @"rcclip";

@interface RCScreenshotMonitorService ()
@property (nonatomic, strong, nullable) NSMetadataQuery *metadataQuery;
@property (nonatomic, assign, getter=isMonitoring) BOOL monitoring;
@property (nonatomic, strong, nullable) NSDate *monitoringStartDate;
@end

@implementation RCScreenshotMonitorService

+ (instancetype)shared {
    static RCScreenshotMonitorService *sharedService = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedService = [[self alloc] init];
    });
    return sharedService;
}

- (void)dealloc {
    [self stopMonitoring];
}

#pragma mark - Public

- (void)startMonitoring {
    if (![NSThread isMainThread]) {
        return;
    }

    if (![[NSUserDefaults standardUserDefaults] boolForKey:kRCBetaObserveScreenshot]) {
        return;
    }

    if (self.monitoring) {
        return;
    }

    NSMetadataQuery *query = [[NSMetadataQuery alloc] init];
    query.predicate = [NSPredicate predicateWithFormat:@"%K == 1", kRCMetadataItemIsScreenCapture];
    query.searchScopes = @[NSMetadataQueryUserHomeScope];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleMetadataQueryUpdate:)
                                                 name:NSMetadataQueryDidUpdateNotification
                                               object:query];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleMetadataQueryGatherComplete:)
                                                 name:NSMetadataQueryDidFinishGatheringNotification
                                               object:query];

    self.metadataQuery = query;
    self.monitoringStartDate = [NSDate date];

    if (![query startQuery]) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:NSMetadataQueryDidUpdateNotification
                                                      object:query];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:NSMetadataQueryDidFinishGatheringNotification
                                                      object:query];
        self.metadataQuery = nil;
        self.monitoringStartDate = nil;
        return;
    }

    self.monitoring = YES;
}

- (void)stopMonitoring {
    if (![NSThread isMainThread]) {
        return;
    }

    if (self.metadataQuery != nil) {
        [self.metadataQuery stopQuery];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:NSMetadataQueryDidUpdateNotification
                                                      object:self.metadataQuery];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:NSMetadataQueryDidFinishGatheringNotification
                                                      object:self.metadataQuery];
    }

    self.metadataQuery = nil;
    self.monitoringStartDate = nil;
    self.monitoring = NO;
}

#pragma mark - Private

- (void)handleMetadataQueryUpdate:(NSNotification *)notification {
    if (![NSThread isMainThread]) {
        return;
    }

    if (self.metadataQuery == nil || notification.object != self.metadataQuery) {
        return;
    }

    [self.metadataQuery disableUpdates];

    @try {
        NSArray<NSMetadataItem *> *addedItems = notification.userInfo[NSMetadataQueryUpdateAddedItemsKey];
        if (![addedItems isKindOfClass:[NSArray class]] || addedItems.count == 0) {
            return;
        }

        [self processMetadataItems:addedItems];
    } @finally {
        [self.metadataQuery enableUpdates];
    }
}

- (void)handleMetadataQueryGatherComplete:(NSNotification *)notification {
    if (![NSThread isMainThread]) {
        return;
    }

    if (self.metadataQuery == nil || notification.object != self.metadataQuery) {
        return;
    }

    [self.metadataQuery disableUpdates];

    @try {
        NSMutableArray<NSMetadataItem *> *items = [NSMutableArray arrayWithCapacity:self.metadataQuery.resultCount];
        for (NSUInteger index = 0; index < self.metadataQuery.resultCount; index++) {
            id itemObject = [self.metadataQuery resultAtIndex:index];
            if (![itemObject isKindOfClass:[NSMetadataItem class]]) {
                continue;
            }

            [items addObject:(NSMetadataItem *)itemObject];
        }

        [self processMetadataItems:items];
    } @finally {
        [self.metadataQuery enableUpdates];
    }
}

- (void)processMetadataItems:(NSArray<NSMetadataItem *> *)items {
    for (id itemObject in items) {
        if (![itemObject isKindOfClass:[NSMetadataItem class]]) {
            continue;
        }

        [self processScreenshotItem:(NSMetadataItem *)itemObject];
    }
}

- (void)processScreenshotItem:(NSMetadataItem *)item {
    if (![self shouldHandleMetadataItem:item]) {
        return;
    }

    NSString *filePath = [item valueForAttribute:kRCMetadataItemPath];
    if (![filePath isKindOfClass:[NSString class]] || filePath.length == 0) {
        return;
    }

    if (![self isSupportedScreenshotPath:filePath]) {
        return;
    }

    [self saveScreenshotToClipHistory:filePath];
}

- (BOOL)shouldHandleMetadataItem:(NSMetadataItem *)item {
    NSDate *creationDate = [item valueForAttribute:kRCMetadataItemFSCreationDate];
    if (![creationDate isKindOfClass:[NSDate class]]) {
        return NO;
    }

    if (self.monitoringStartDate == nil) {
        return NO;
    }

    return [creationDate compare:self.monitoringStartDate] == NSOrderedDescending;
}

- (BOOL)isSupportedScreenshotPath:(NSString *)filePath {
    NSString *fileExtension = filePath.pathExtension.lowercaseString;
    return [fileExtension isEqualToString:@"png"]
        || [fileExtension isEqualToString:@"tiff"]
        || [fileExtension isEqualToString:@"tif"];
}

/// Saves the screenshot at the given path directly into clip history
/// without overwriting the user's current clipboard contents.
- (void)saveScreenshotToClipHistory:(NSString *)filePath {
    NSData *imageData = [NSData dataWithContentsOfFile:filePath];
    if (imageData.length == 0) {
        return;
    }

    NSImage *image = [[NSImage alloc] initWithData:imageData];
    if (image == nil) {
        return;
    }

    // Convert to TIFF data, which is how RCClipboardService stores images
    NSData *tiffData = [image TIFFRepresentation];
    if (tiffData.length == 0) {
        return;
    }

    // Build an RCClipData representing this screenshot image
    RCClipData *clipData = [[RCClipData alloc] init];
    clipData.TIFFData = tiffData;
    clipData.primaryType = NSPasteboardTypeTIFF;

    NSString *dataHash = [clipData dataHash];
    if (dataHash.length == 0) {
        return;
    }

    RCDatabaseManager *databaseManager = [RCDatabaseManager shared];
    if (![databaseManager setupDatabase]) {
        return;
    }

    NSInteger updateTime = (NSInteger)([[NSDate date] timeIntervalSince1970] * 1000.0);

    // If an identical screenshot already exists in history, just update its timestamp
    NSDictionary *existingClipDict = [databaseManager clipItemWithDataHash:dataHash];
    if (existingClipDict != nil) {
        if ([databaseManager updateClipItemUpdateTime:dataHash time:updateTime]) {
            NSMutableDictionary *updatedDict = [existingClipDict mutableCopy];
            updatedDict[@"update_time"] = @(updateTime);
            RCClipItem *updatedItem = [[RCClipItem alloc] initWithDictionary:updatedDict];
            [self postClipboardDidChangeNotificationWithClipItem:updatedItem];
        }
        return;
    }

    // Ensure the clip data directory exists
    NSString *directoryPath = [RCUtilities clipDataDirectoryPath];
    if (![RCUtilities ensureDirectoryExists:directoryPath]) {
        return;
    }

    // Save clip data to file
    NSString *identifier = [NSUUID UUID].UUIDString;
    NSString *dataFileName = [NSString stringWithFormat:@"%@.%@", identifier, kRCScreenshotClipDataFileExtension];
    NSString *dataPath = [directoryPath stringByAppendingPathComponent:dataFileName];

    if (![clipData saveToPath:dataPath]) {
        return;
    }

    // Generate thumbnail
    NSString *thumbnailPath = [self generateThumbnailForImage:image
                                                   identifier:identifier
                                                directoryPath:directoryPath];

    NSDictionary *clipDictionary = @{
        @"data_path": dataPath,
        @"title": [clipData title] ?: @"",
        @"data_hash": dataHash,
        @"primary_type": clipData.primaryType ?: @"",
        @"update_time": @(updateTime),
        @"thumbnail_path": thumbnailPath ?: @"",
        @"is_color_code": @(NO),
    };

    if (![databaseManager insertClipItem:clipDictionary]) {
        [[NSFileManager defaultManager] removeItemAtPath:dataPath error:nil];
        if (thumbnailPath.length > 0) {
            [[NSFileManager defaultManager] removeItemAtPath:thumbnailPath error:nil];
        }
        return;
    }

    RCClipItem *clipItem = [[RCClipItem alloc] initWithDictionary:clipDictionary];
    [self postClipboardDidChangeNotificationWithClipItem:clipItem];
}

- (NSString *)generateThumbnailForImage:(NSImage *)image
                             identifier:(NSString *)identifier
                          directoryPath:(NSString *)directoryPath {
    if (image == nil || identifier.length == 0 || directoryPath.length == 0) {
        return @"";
    }

    CGFloat width = [[NSUserDefaults standardUserDefaults] doubleForKey:kRCThumbnailWidthKey];
    CGFloat height = [[NSUserDefaults standardUserDefaults] doubleForKey:kRCThumbnailHeightKey];
    if (width <= 0.0) width = 100.0;
    if (height <= 0.0) height = 32.0;
    NSSize targetSize = NSMakeSize(width, height);
    NSImage *thumbnailImage = [image resizedImageToFitSize:targetSize];
    if (thumbnailImage == nil) {
        thumbnailImage = [image resizedImageToSize:targetSize];
    }
    if (thumbnailImage == nil) {
        return @"";
    }

    NSData *thumbnailData = [thumbnailImage TIFFRepresentation];
    if (thumbnailData.length == 0) {
        return @"";
    }

    NSString *thumbnailFileName = [NSString stringWithFormat:@"%@.thumbnail.tiff", identifier];
    NSString *thumbnailPath = [directoryPath stringByAppendingPathComponent:thumbnailFileName];

    NSError *error = nil;
    BOOL wrote = [thumbnailData writeToFile:thumbnailPath options:NSDataWritingAtomic error:&error];
    if (!wrote) {
        NSLog(@"[RCScreenshotMonitorService] Failed to save thumbnail at path '%@': %@", thumbnailPath, error.localizedDescription);
        return @"";
    }

    return thumbnailPath;
}

- (void)postClipboardDidChangeNotificationWithClipItem:(RCClipItem *)clipItem {
    if (clipItem == nil) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:RCClipboardDidChangeNotification
                                                            object:self
                                                          userInfo:@{ @"clipItem": clipItem }];
    });
}

@end
