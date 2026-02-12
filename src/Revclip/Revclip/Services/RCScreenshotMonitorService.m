//
//  RCScreenshotMonitorService.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "RCScreenshotMonitorService.h"

#import <Cocoa/Cocoa.h>

static NSString * const kRCBetaScreenshotMonitoring = @"RCBetaScreenshotMonitoring";
static NSString * const kRCMetadataItemIsScreenCapture = @"kMDItemIsScreenCapture";
static NSString * const kRCMetadataItemFSCreationDate = @"kMDItemFSCreationDate";
static NSString * const kRCMetadataItemPath = @"kMDItemPath";

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

    if (![[NSUserDefaults standardUserDefaults] boolForKey:kRCBetaScreenshotMonitoring]) {
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

    [self copyImageAtPathToPasteboard:filePath];
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

- (void)copyImageAtPathToPasteboard:(NSString *)filePath {
    NSData *imageData = [NSData dataWithContentsOfFile:filePath];
    if (imageData.length == 0) {
        return;
    }

    NSImage *image = [[NSImage alloc] initWithData:imageData];
    if (image == nil) {
        return;
    }

    NSString *fileExtension = filePath.pathExtension.lowercaseString;
    NSPasteboardType pasteboardType = [fileExtension isEqualToString:@"png"] ? NSPasteboardTypePNG : NSPasteboardTypeTIFF;

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    if (![pasteboard setData:imageData forType:pasteboardType]) {
        [pasteboard clearContents];
        [pasteboard writeObjects:@[image]];
    }
}

@end
