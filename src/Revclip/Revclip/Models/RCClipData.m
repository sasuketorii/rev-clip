//
//  RCClipData.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "RCClipData.h"

#import <AppKit/AppKit.h>
#import <CommonCrypto/CommonDigest.h>

static NSString * const kRCClipDataStringValueKey = @"stringValue";
static NSString * const kRCClipDataRTFDataKey = @"RTFData";
static NSString * const kRCClipDataRTFDDataKey = @"RTFDData";
static NSString * const kRCClipDataPDFDataKey = @"PDFData";
static NSString * const kRCClipDataFileNamesKey = @"fileNames";
static NSString * const kRCClipDataFileURLsKey = @"fileURLs";
static NSString * const kRCClipDataURLStringKey = @"URLString";
static NSString * const kRCClipDataTIFFDataKey = @"TIFFData";
static NSString * const kRCClipDataPrimaryTypeKey = @"primaryType";

@interface RCClipData ()

+ (NSString *)sha256HexForData:(NSData *)data;
+ (void)appendData:(nullable NSData *)source toBuffer:(NSMutableData *)buffer;
+ (void)appendString:(nullable NSString *)string toBuffer:(NSMutableData *)buffer;
+ (NSString *)truncateString:(NSString *)string length:(NSUInteger)length;

@end

@implementation RCClipData

#pragma mark - Create

+ (instancetype)clipDataFromPasteboard:(NSPasteboard *)pasteboard {
    RCClipData *clipData = [[self alloc] init];

    if (pasteboard == nil) {
        return clipData;
    }

    void (^setPrimaryTypeIfNeeded)(NSString *) = ^(NSString *type) {
        if (clipData.primaryType.length == 0) {
            clipData.primaryType = type;
        }
    };

    NSString *stringValue = [pasteboard stringForType:NSPasteboardTypeString];
    if (stringValue != nil) {
        clipData.stringValue = stringValue;
        setPrimaryTypeIfNeeded(NSPasteboardTypeString);
    }

    NSData *RTFData = [pasteboard dataForType:NSPasteboardTypeRTF];
    if (RTFData != nil) {
        clipData.RTFData = RTFData;
        setPrimaryTypeIfNeeded(NSPasteboardTypeRTF);
    }

    NSData *RTFDData = [pasteboard dataForType:NSPasteboardTypeRTFD];
    if (RTFDData != nil) {
        clipData.RTFDData = RTFDData;
        setPrimaryTypeIfNeeded(NSPasteboardTypeRTFD);
    }

    NSData *PDFData = [pasteboard dataForType:NSPasteboardTypePDF];
    if (PDFData != nil) {
        clipData.PDFData = PDFData;
        setPrimaryTypeIfNeeded(NSPasteboardTypePDF);
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    id rawFileNames = [pasteboard propertyListForType:NSFilenamesPboardType];
#pragma clang diagnostic pop
    if ([rawFileNames isKindOfClass:[NSArray class]]) {
        NSMutableArray<NSString *> *fileNames = [NSMutableArray array];
        for (id value in (NSArray *)rawFileNames) {
            if ([value isKindOfClass:[NSString class]]) {
                [fileNames addObject:value];
            }
        }
        clipData.fileNames = [fileNames copy];
        if (fileNames.count > 0) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            setPrimaryTypeIfNeeded(NSFilenamesPboardType);
#pragma clang diagnostic pop
        }
    }

    NSArray *readObjects = [pasteboard readObjectsForClasses:@[[NSURL class]] options:nil];
    if (readObjects.count > 0) {
        NSMutableArray<NSURL *> *fileURLs = [NSMutableArray array];
        for (id object in readObjects) {
            if ([object isKindOfClass:[NSURL class]] && [(NSURL *)object isFileURL]) {
                [fileURLs addObject:object];
            }
        }
        if (fileURLs.count > 0) {
            clipData.fileURLs = [fileURLs copy];
            setPrimaryTypeIfNeeded(NSPasteboardTypeFileURL);
        }
    }

    NSString *URLString = [pasteboard stringForType:NSPasteboardTypeURL];
    if (URLString != nil) {
        clipData.URLString = URLString;
        setPrimaryTypeIfNeeded(NSPasteboardTypeURL);
    }

    NSData *TIFFData = [pasteboard dataForType:NSPasteboardTypeTIFF];
    if (TIFFData != nil) {
        clipData.TIFFData = TIFFData;
        setPrimaryTypeIfNeeded(NSPasteboardTypeTIFF);
    }

    return clipData;
}

#pragma mark - Hash / Title

- (NSString *)dataHash {
    NSMutableData *buffer = [NSMutableData data];
    [[self class] appendString:self.stringValue toBuffer:buffer];
    [[self class] appendData:self.RTFData toBuffer:buffer];
    [[self class] appendData:self.RTFDData toBuffer:buffer];
    [[self class] appendData:self.PDFData toBuffer:buffer];
    [[self class] appendData:self.TIFFData toBuffer:buffer];
    for (NSString *fileName in self.fileNames) {
        [[self class] appendString:fileName toBuffer:buffer];
    }
    for (NSURL *fileURL in self.fileURLs) {
        [[self class] appendString:fileURL.absoluteString toBuffer:buffer];
    }
    [[self class] appendString:self.URLString toBuffer:buffer];
    // Include primaryType in hash to differentiate items with identical data but different primary types
    [[self class] appendString:self.primaryType toBuffer:buffer];

    if (buffer.length == 0) {
        return @"";
    }

    return [[self class] sha256HexForData:buffer];
}

- (NSString *)title {
    if (self.stringValue.length > 0) {
        return [[self class] truncateString:self.stringValue length:50];
    }

    if (self.URLString.length > 0) {
        return self.URLString;
    }

    if (self.fileNames.count > 0) {
        NSString *firstName = self.fileNames.firstObject;
        NSString *fileName = firstName.lastPathComponent;
        return fileName.length > 0 ? fileName : (firstName ?: @"");
    }

    if (self.fileURLs.count > 0) {
        NSURL *firstURL = self.fileURLs.firstObject;
        NSString *fileName = firstURL.lastPathComponent;
        return fileName.length > 0 ? fileName : (firstURL.absoluteString ?: @"");
    }

    BOOL hasNonImageData = self.RTFData.length > 0
        || self.RTFDData.length > 0
        || self.PDFData.length > 0
        || self.fileNames.count > 0
        || self.fileURLs.count > 0
        || self.URLString.length > 0;
    if (self.TIFFData.length > 0 && !hasNonImageData) {
        return NSLocalizedString(@"(Image)", @"Title for image-only clipboard data");
    }

    return @"";
}

#pragma mark - Equality

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }
    if (![object isKindOfClass:[RCClipData class]]) {
        return NO;
    }
    RCClipData *other = (RCClipData *)object;
    return [[self dataHash] isEqualToString:[other dataHash]];
}

- (NSUInteger)hash {
    return [[self dataHash] hash];
}

#pragma mark - Write

- (void)writeToPasteboard:(NSPasteboard *)pasteboard {
    if (pasteboard == nil) {
        return;
    }

    [pasteboard clearContents];

    // File URLs conform to NSPasteboardWriting, so use writeObjects: for them.
    // Other data types (NSData, NSString for specific UTIs) do not conform to
    // NSPasteboardWriting and must be set individually via setData:/setString:.
    // clearContents above ensures the pasteboard is fresh before writing.
    if (self.fileURLs.count > 0) {
        [pasteboard writeObjects:self.fileURLs];
    }

    if (self.stringValue != nil) {
        [pasteboard setString:self.stringValue forType:NSPasteboardTypeString];
    }
    if (self.RTFData != nil) {
        [pasteboard setData:self.RTFData forType:NSPasteboardTypeRTF];
    }
    if (self.RTFDData != nil) {
        [pasteboard setData:self.RTFDData forType:NSPasteboardTypeRTFD];
    }
    if (self.PDFData != nil) {
        [pasteboard setData:self.PDFData forType:NSPasteboardTypePDF];
    }
    if (self.fileNames.count > 0) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [pasteboard setPropertyList:self.fileNames forType:NSFilenamesPboardType];
#pragma clang diagnostic pop
    }
    if (self.URLString != nil) {
        [pasteboard setString:self.URLString forType:NSPasteboardTypeURL];
    }
    if (self.TIFFData != nil) {
        [pasteboard setData:self.TIFFData forType:NSPasteboardTypeTIFF];
    }
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.stringValue forKey:kRCClipDataStringValueKey];
    [coder encodeObject:self.RTFData forKey:kRCClipDataRTFDataKey];
    [coder encodeObject:self.RTFDData forKey:kRCClipDataRTFDDataKey];
    [coder encodeObject:self.PDFData forKey:kRCClipDataPDFDataKey];
    [coder encodeObject:self.fileNames forKey:kRCClipDataFileNamesKey];
    [coder encodeObject:self.fileURLs forKey:kRCClipDataFileURLsKey];
    [coder encodeObject:self.URLString forKey:kRCClipDataURLStringKey];
    [coder encodeObject:self.TIFFData forKey:kRCClipDataTIFFDataKey];
    [coder encodeObject:self.primaryType forKey:kRCClipDataPrimaryTypeKey];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        NSSet<Class> *stringArrayClasses = [NSSet setWithArray:@[[NSArray class], [NSString class]]];
        NSSet<Class> *urlArrayClasses = [NSSet setWithArray:@[[NSArray class], [NSURL class]]];

        self.stringValue = [coder decodeObjectOfClass:[NSString class] forKey:kRCClipDataStringValueKey];
        self.RTFData = [coder decodeObjectOfClass:[NSData class] forKey:kRCClipDataRTFDataKey];
        self.RTFDData = [coder decodeObjectOfClass:[NSData class] forKey:kRCClipDataRTFDDataKey];
        self.PDFData = [coder decodeObjectOfClass:[NSData class] forKey:kRCClipDataPDFDataKey];
        self.fileNames = [coder decodeObjectOfClasses:stringArrayClasses forKey:kRCClipDataFileNamesKey];
        self.fileURLs = [coder decodeObjectOfClasses:urlArrayClasses forKey:kRCClipDataFileURLsKey];
        self.URLString = [coder decodeObjectOfClass:[NSString class] forKey:kRCClipDataURLStringKey];
        self.TIFFData = [coder decodeObjectOfClass:[NSData class] forKey:kRCClipDataTIFFDataKey];
        self.primaryType = [coder decodeObjectOfClass:[NSString class] forKey:kRCClipDataPrimaryTypeKey];
    }
    return self;
}

#pragma mark - File

- (BOOL)saveToPath:(NSString *)path {
    if (path.length == 0) {
        return NO;
    }

    NSString *directoryPath = [path stringByDeletingLastPathComponent];
    if (directoryPath.length > 0) {
        NSError *directoryError = nil;
        BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:directoryPath
                                                 withIntermediateDirectories:YES
                                                                  attributes:nil
                                                                       error:&directoryError];
        if (!created) {
            NSLog(@"[RCClipData] Failed to create directory at path '%@': %@", directoryPath, directoryError.localizedDescription);
            return NO;
        }
    }

    NSError *archiveError = nil;
    NSData *archiveData = [NSKeyedArchiver archivedDataWithRootObject:self
                                                 requiringSecureCoding:YES
                                                                 error:&archiveError];
    if (archiveData == nil) {
        NSLog(@"[RCClipData] Failed to archive clip data: %@", archiveError.localizedDescription);
        return NO;
    }

    NSError *writeError = nil;
    BOOL wrote = [archiveData writeToFile:path options:NSDataWritingAtomic error:&writeError];
    if (!wrote) {
        NSLog(@"[RCClipData] Failed to save clip data at path '%@': %@", path, writeError.localizedDescription);
    }
    return wrote;
}

+ (instancetype)clipDataFromPath:(NSString *)path {
    if (path.length == 0) {
        return nil;
    }

    NSError *readError = nil;
    NSData *archiveData = [NSData dataWithContentsOfFile:path options:0 error:&readError];
    if (archiveData == nil) {
        return nil;
    }

    NSError *unarchiveError = nil;
    RCClipData *decodedObject = [NSKeyedUnarchiver unarchivedObjectOfClass:[RCClipData class]
                                                                   fromData:archiveData
                                                                      error:&unarchiveError];
    if (decodedObject == nil && unarchiveError != nil) {
        NSLog(@"[RCClipData] Failed to unarchive clip data at path '%@': %@", path, unarchiveError.localizedDescription);
    }
    return decodedObject;
}

#pragma mark - Helpers

+ (NSString *)sha256HexForData:(NSData *)data {
    NSAssert(data.length <= UINT32_MAX, @"Data length %lu exceeds CC_LONG (uint32_t) maximum", (unsigned long)data.length);
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);

    NSMutableString *hexString = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
        [hexString appendFormat:@"%02x", digest[index]];
    }
    return [hexString copy];
}

+ (void)appendData:(nullable NSData *)source toBuffer:(NSMutableData *)buffer {
    if (source.length == 0) {
        return;
    }

    NSAssert(source.length <= UINT32_MAX, @"Source data length %lu exceeds uint32_t maximum", (unsigned long)source.length);
    uint32_t length = CFSwapInt32HostToBig((uint32_t)source.length);
    [buffer appendBytes:&length length:sizeof(length)];
    [buffer appendData:source];
}

+ (void)appendString:(nullable NSString *)string toBuffer:(NSMutableData *)buffer {
    if (string.length == 0) {
        return;
    }
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    [self appendData:data toBuffer:buffer];
}

+ (NSString *)truncateString:(NSString *)string length:(NSUInteger)length {
    if (string.length <= length) {
        return string;
    }
    NSRange range = [string rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, length)];
    return [string substringWithRange:range];
}

@end
