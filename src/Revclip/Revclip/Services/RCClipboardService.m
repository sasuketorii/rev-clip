//
//  RCClipboardService.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "RCClipboardService.h"

#import "RCConstants.h"
#import "RCExcludeAppService.h"
#import "RCDatabaseManager.h"
#import "RCClipData.h"
#import "RCClipItem.h"
#import "NSColor+HexString.h"
#import "NSImage+Resize.h"
#import "RCUtilities.h"

NSString * const RCClipboardDidChangeNotification = @"RCClipboardDidChangeNotification";

static NSTimeInterval const kRCClipboardPollingInterval = 0.5;
static NSString * const kRCClipDataFileExtension = @"rcclip";
static NSString * const kRCStoreTypeString = @"String";
static NSString * const kRCStoreTypeRTF = @"RTF";
static NSString * const kRCStoreTypeRTFD = @"RTFD";
static NSString * const kRCStoreTypePDF = @"PDF";
static NSString * const kRCStoreTypeFilenames = @"Filenames";
static NSString * const kRCStoreTypeURL = @"URL";
static NSString * const kRCStoreTypeTIFF = @"TIFF";

@interface RCClipboardService ()

@property (nonatomic, readwrite, assign) BOOL isMonitoring;
@property (nonatomic, strong, nullable) dispatch_source_t monitorTimer;
@property (nonatomic, strong) dispatch_queue_t monitoringQueue;
@property (nonatomic, strong) dispatch_queue_t fileOperationQueue;
@property (nonatomic, assign) NSInteger cachedChangeCount;

@end

@implementation RCClipboardService

+ (instancetype)shared {
    static RCClipboardService *sharedService = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedService = [[self alloc] init];
    });
    return sharedService;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isMonitoring = NO;
        _monitoringQueue = dispatch_queue_create("com.revclip.clipboard.monitoring", DISPATCH_QUEUE_SERIAL);
        _fileOperationQueue = dispatch_queue_create("com.revclip.clipboard.file", DISPATCH_QUEUE_SERIAL);
        _cachedChangeCount = [NSPasteboard generalPasteboard].changeCount;
    }
    return self;
}

- (void)dealloc {
    [self stopMonitoring];
}

#pragma mark - Public

- (void)startMonitoring {
    @synchronized (self) {
        if (self.isMonitoring) {
            return;
        }

        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.monitoringQueue);
        if (timer == nil) {
            return;
        }

        self.cachedChangeCount = [NSPasteboard generalPasteboard].changeCount;
        uint64_t interval = (uint64_t)(kRCClipboardPollingInterval * (double)NSEC_PER_SEC);
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
            [strongSelf pollPasteboardOnMonitoringQueue];
        });

        self.monitorTimer = timer;
        self.isMonitoring = YES;
        dispatch_resume(timer);
    }
}

- (void)stopMonitoring {
    dispatch_source_t timer = nil;

    @synchronized (self) {
        if (!self.isMonitoring) {
            return;
        }

        timer = self.monitorTimer;
        self.monitorTimer = nil;
        self.isMonitoring = NO;
    }

    if (timer != nil) {
        dispatch_source_cancel(timer);
    }
}

- (void)captureCurrentClipboard {
    if ([[RCExcludeAppService shared] shouldExcludeCurrentApp]) {
        return;
    }

    dispatch_async(self.monitoringQueue, ^{
        [self captureCurrentClipboardOnMonitoringQueue];
    });
}

#pragma mark - Private: Monitor / Capture

- (void)pollPasteboardOnMonitoringQueue {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    NSInteger currentChangeCount = pasteboard.changeCount;
    if (currentChangeCount == self.cachedChangeCount) {
        return;
    }

    self.cachedChangeCount = currentChangeCount;
    [self saveClipFromPasteboardOnMonitoringQueue:pasteboard];
}

- (void)captureCurrentClipboardOnMonitoringQueue {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    self.cachedChangeCount = pasteboard.changeCount;
    [self saveClipFromPasteboardOnMonitoringQueue:pasteboard];
}

- (void)saveClipFromPasteboardOnMonitoringQueue:(NSPasteboard *)pasteboard {
    if ([self shouldSkipCurrentApplication]) {
        return;
    }

    RCClipData *clipData = [RCClipData clipDataFromPasteboard:pasteboard];
    if (![self hasClipContent:clipData]) {
        return;
    }

    if (![self shouldStoreClipData:clipData]) {
        return;
    }

    NSString *dataHash = [clipData dataHash];
    if (dataHash.length == 0) {
        return;
    }

    RCDatabaseManager *databaseManager = [RCDatabaseManager shared];
    if (![databaseManager setupDatabase]) {
        return;
    }

    NSInteger updateTime = [self currentTimestamp];
    NSDictionary *existingClipDict = [databaseManager clipItemWithDataHash:dataHash];
    if (existingClipDict != nil) {
        [self handleExistingClipWithHash:dataHash
                            existingDict:existingClipDict
                              updateTime:updateTime
                         databaseManager:databaseManager];
        return;
    }

    NSString *directoryPath = [RCUtilities clipDataDirectoryPath];
    if (![RCUtilities ensureDirectoryExists:directoryPath]) {
        return;
    }

    NSString *identifier = [NSUUID UUID].UUIDString;
    NSString *dataFileName = [NSString stringWithFormat:@"%@.%@", identifier, kRCClipDataFileExtension];
    NSString *dataPath = [directoryPath stringByAppendingPathComponent:dataFileName];

    if (![self saveClipData:clipData toPath:dataPath]) {
        return;
    }

    NSString *thumbnailPath = [self generateThumbnailPathForClipData:clipData
                                                           identifier:identifier
                                                        directoryPath:directoryPath];

    BOOL isColorCode = (clipData.stringValue.length > 0
                        && [NSColor isValidHexColorString:clipData.stringValue]);

    NSDictionary *clipDictionary = @{
        @"data_path": dataPath,
        @"title": clipData.title ?: @"",
        @"data_hash": dataHash,
        @"primary_type": clipData.primaryType ?: @"",
        @"update_time": @(updateTime),
        @"thumbnail_path": thumbnailPath ?: @"",
        @"is_color_code": @(isColorCode),
    };

    if (![databaseManager insertClipItem:clipDictionary]) {
        [self deleteFileAtPath:dataPath];
        [self deleteFileAtPath:thumbnailPath];
        return;
    }

    RCClipItem *clipItem = [[RCClipItem alloc] initWithDictionary:clipDictionary];
    [self trimHistoryIfNeededWithDatabaseManager:databaseManager];
    [self postClipboardDidChangeNotificationWithClipItem:clipItem];
}

- (void)handleExistingClipWithHash:(NSString *)dataHash
                      existingDict:(NSDictionary *)existingClipDict
                        updateTime:(NSInteger)updateTime
                   databaseManager:(RCDatabaseManager *)databaseManager {
    BOOL shouldOverwrite = [self boolPreferenceForKey:kRCPrefOverwriteSameHistory defaultValue:YES];
    BOOL shouldReorder = [self boolPreferenceForKey:kRCPrefReorderClipsAfterPasting defaultValue:YES];

    if (!shouldOverwrite && !shouldReorder) {
        return;
    }

    if (![databaseManager updateClipItemUpdateTime:dataHash time:updateTime]) {
        return;
    }

    NSMutableDictionary *updatedDict = [existingClipDict mutableCopy];
    updatedDict[@"update_time"] = @(updateTime);
    RCClipItem *updatedItem = [[RCClipItem alloc] initWithDictionary:updatedDict];
    [self postClipboardDidChangeNotificationWithClipItem:updatedItem];
}

#pragma mark - Private: Filtering

- (BOOL)hasClipContent:(RCClipData *)clipData {
    return (clipData.stringValue.length > 0
            || clipData.RTFData.length > 0
            || clipData.RTFDData.length > 0
            || clipData.PDFData.length > 0
            || clipData.fileNames.count > 0
            || clipData.fileURLs.count > 0
            || clipData.URLString.length > 0
            || clipData.TIFFData.length > 0);
}

- (BOOL)shouldStoreClipData:(RCClipData *)clipData {
    NSDictionary *storeTypes = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kRCPrefStoreTypesKey];
    if (![storeTypes isKindOfClass:[NSDictionary class]]) {
        return YES;
    }

    BOOL hasSupportedType = NO;
    BOOL hasEnabledType = NO;

    BOOL hasString = (clipData.stringValue.length > 0);
    if (hasString) {
        hasSupportedType = YES;
        hasEnabledType = hasEnabledType || [self isStoreTypeEnabledForKey:kRCStoreTypeString inStoreTypes:storeTypes];
    }

    BOOL hasRTF = (clipData.RTFData.length > 0);
    if (hasRTF) {
        hasSupportedType = YES;
        hasEnabledType = hasEnabledType || [self isStoreTypeEnabledForKey:kRCStoreTypeRTF inStoreTypes:storeTypes];
    }

    BOOL hasRTFD = (clipData.RTFDData.length > 0);
    if (hasRTFD) {
        hasSupportedType = YES;
        hasEnabledType = hasEnabledType || [self isStoreTypeEnabledForKey:kRCStoreTypeRTFD inStoreTypes:storeTypes];
    }

    BOOL hasPDF = (clipData.PDFData.length > 0);
    if (hasPDF) {
        hasSupportedType = YES;
        hasEnabledType = hasEnabledType || [self isStoreTypeEnabledForKey:kRCStoreTypePDF inStoreTypes:storeTypes];
    }

    BOOL hasFiles = (clipData.fileNames.count > 0 || clipData.fileURLs.count > 0);
    if (hasFiles) {
        hasSupportedType = YES;
        hasEnabledType = hasEnabledType || [self isStoreTypeEnabledForKey:kRCStoreTypeFilenames inStoreTypes:storeTypes];
    }

    BOOL hasURL = (clipData.URLString.length > 0);
    if (hasURL) {
        hasSupportedType = YES;
        hasEnabledType = hasEnabledType || [self isStoreTypeEnabledForKey:kRCStoreTypeURL inStoreTypes:storeTypes];
    }

    BOOL hasTIFF = (clipData.TIFFData.length > 0);
    if (hasTIFF) {
        hasSupportedType = YES;
        hasEnabledType = hasEnabledType || [self isStoreTypeEnabledForKey:kRCStoreTypeTIFF inStoreTypes:storeTypes];
    }

    if (!hasSupportedType) {
        return YES;
    }

    return hasEnabledType;
}

- (BOOL)isStoreTypeEnabledForKey:(NSString *)key inStoreTypes:(NSDictionary *)storeTypes {
    id value = storeTypes[key];
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value boolValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value boolValue];
    }
    return YES;
}

- (BOOL)shouldSkipCurrentApplication {
    return [[RCExcludeAppService shared] shouldExcludeCurrentApp];
}

#pragma mark - Private: File / Thumbnail

- (BOOL)saveClipData:(RCClipData *)clipData toPath:(NSString *)path {
    if (path.length == 0) {
        return NO;
    }

    __block BOOL saved = NO;
    dispatch_sync(self.fileOperationQueue, ^{
        saved = [clipData saveToPath:path];
    });
    return saved;
}

- (NSString *)generateThumbnailPathForClipData:(RCClipData *)clipData
                                     identifier:(NSString *)identifier
                                  directoryPath:(NSString *)directoryPath {
    if (clipData.TIFFData.length == 0 || identifier.length == 0 || directoryPath.length == 0) {
        return @"";
    }

    NSImage *image = [[NSImage alloc] initWithData:clipData.TIFFData];
    if (image == nil) {
        return @"";
    }

    NSSize targetSize = [self thumbnailTargetSize];
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

    __block BOOL wrote = NO;
    dispatch_sync(self.fileOperationQueue, ^{
        NSError *error = nil;
        wrote = [thumbnailData writeToFile:thumbnailPath options:NSDataWritingAtomic error:&error];
        if (!wrote) {
            NSLog(@"[RCClipboardService] Failed to save thumbnail at path '%@': %@", thumbnailPath, error.localizedDescription);
        }
    });

    return wrote ? thumbnailPath : @"";
}

- (NSSize)thumbnailTargetSize {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    CGFloat width = [defaults doubleForKey:kRCThumbnailWidthKey];
    CGFloat height = [defaults doubleForKey:kRCThumbnailHeightKey];
    if (width <= 0.0) {
        width = 100.0;
    }
    if (height <= 0.0) {
        height = 32.0;
    }
    return NSMakeSize(width, height);
}

- (void)deleteFileAtPath:(NSString *)path {
    if (path.length == 0) {
        return;
    }

    dispatch_sync(self.fileOperationQueue, ^{
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:path]) {
            return;
        }

        NSError *error = nil;
        BOOL removed = [fileManager removeItemAtPath:path error:&error];
        if (!removed) {
            NSLog(@"[RCClipboardService] Failed to remove file at path '%@': %@", path, error.localizedDescription);
        }
    });
}

- (void)deleteFilesForClipItem:(RCClipItem *)clipItem {
    [self deleteFileAtPath:clipItem.dataPath];
    [self deleteFileAtPath:clipItem.thumbnailPath];
}

#pragma mark - Private: Cleanup / Notification

- (void)trimHistoryIfNeededWithDatabaseManager:(RCDatabaseManager *)databaseManager {
    NSInteger maxHistorySize = [self integerPreferenceForKey:kRCPrefMaxHistorySizeKey defaultValue:30];
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

    for (NSUInteger index = (NSUInteger)maxHistorySize; index < clipDictionaries.count; index++) {
        RCClipItem *oldItem = [[RCClipItem alloc] initWithDictionary:clipDictionaries[index]];
        if (oldItem.dataHash.length == 0) {
            continue;
        }

        if ([databaseManager deleteClipItemWithDataHash:oldItem.dataHash]) {
            [self deleteFilesForClipItem:oldItem];
        }
    }
}

- (NSInteger)currentTimestamp {
    return (NSInteger)([[NSDate date] timeIntervalSince1970] * 1000.0);
}

- (BOOL)boolPreferenceForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id value = [defaults objectForKey:key];
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value boolValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value boolValue];
    }
    return defaultValue;
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
