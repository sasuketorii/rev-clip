//
//  RCSnippetImportExportService.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "RCSnippetImportExportService.h"

#import "FMDB.h"
#import "RCDatabaseManager.h"

NSErrorDomain const RCSnippetImportExportErrorDomain = @"com.revclip.snippet-import-export";

static NSString * const kRCXMLRootElement = @"folders";
static NSString * const kRCXMLLegacyRootElement = @"snippets";
static NSString * const kRCXMLFolderElement = @"folder";
static NSString * const kRCXMLFolderIdentifierElement = @"identifier";
static NSString * const kRCXMLFolderTitleElement = @"title";
static NSString * const kRCXMLFolderEnabledElement = @"enabled";
static NSString * const kRCXMLFolderSnippetsElement = @"snippets";
static NSString * const kRCXMLSnippetElement = @"snippet";
static NSString * const kRCXMLSnippetIdentifierElement = @"identifier";
static NSString * const kRCXMLSnippetTitleElement = @"title";
static NSString * const kRCXMLSnippetContentElement = @"content";
static NSString * const kRCXMLSnippetEnabledElement = @"enabled";

@interface RCSnippetImportExportService ()

- (BOOL)persistParsedFolders:(NSArray<NSDictionary *> *)folders merge:(BOOL)merge error:(NSError **)error;
- (nullable NSArray<NSDictionary *> *)parseFoldersFromRootElement:(NSXMLElement *)rootElement error:(NSError **)error;
- (nullable NSXMLElement *)firstChildElementNamed:(NSString *)name inElement:(NSXMLElement *)element;
- (nullable NSString *)trimmedValueForElement:(NSString *)name inElement:(NSXMLElement *)element;
- (nullable NSString *)valueForElement:(NSString *)name inElement:(NSXMLElement *)element;
- (BOOL)boolValueFromXMLString:(nullable NSString *)value defaultValue:(BOOL)defaultValue;
- (NSString *)xmlBooleanStringFromBool:(BOOL)value;
- (NSString *)trimmedString:(nullable NSString *)value;
- (NSString *)uniqueIdentifierExcludingSet:(NSSet<NSString *> *)reservedIdentifiers;
- (nullable NSError *)snippetErrorWithCode:(RCSnippetImportExportErrorCode)code
                                description:(NSString *)description
                            underlyingError:(nullable NSError *)underlyingError;
- (BOOL)assignSnippetError:(NSError **)error
                      code:(RCSnippetImportExportErrorCode)code
               description:(NSString *)description
           underlyingError:(nullable NSError *)underlyingError;
- (NSInteger)nextFolderIndexFromExistingFolders:(NSArray<NSDictionary *> *)folders;
- (NSString *)stringValueFromDictionary:(NSDictionary *)dictionary key:(NSString *)key defaultValue:(NSString *)defaultValue;
- (BOOL)boolValueFromDictionary:(NSDictionary *)dictionary key:(NSString *)key defaultValue:(BOOL)defaultValue;

@end

@implementation RCSnippetImportExportService

+ (instancetype)shared {
    static RCSnippetImportExportService *sharedService = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedService = [[self alloc] init];
    });
    return sharedService;
}

#pragma mark - Export

- (BOOL)exportSnippetsToURL:(NSURL *)fileURL error:(NSError **)error {
    if (![fileURL isFileURL]) {
        return [self assignSnippetError:error
                                   code:RCSnippetImportExportErrorFileWrite
                            description:@"Export destination is invalid."
                        underlyingError:nil];
    }

    NSData *xmlData = [self exportSnippetsAsXMLData:error];
    if (xmlData == nil) {
        return NO;
    }

    NSError *writeError = nil;
    BOOL written = [xmlData writeToURL:fileURL options:NSDataWritingAtomic error:&writeError];
    if (!written) {
        return [self assignSnippetError:error
                                   code:RCSnippetImportExportErrorFileWrite
                            description:@"Failed to write snippets XML file."
                        underlyingError:writeError];
    }

    return YES;
}

- (NSData *)exportSnippetsAsXMLData:(NSError **)error {
    RCDatabaseManager *databaseManager = [RCDatabaseManager shared];
    if (![databaseManager setupDatabase]) {
        [self assignSnippetError:error
                            code:RCSnippetImportExportErrorDatabase
                     description:@"Database is not ready."
                 underlyingError:nil];
        return nil;
    }

    NSArray<NSDictionary *> *folders = [databaseManager fetchAllSnippetFolders];
    NSXMLElement *rootElement = [NSXMLElement elementWithName:kRCXMLRootElement];
    [rootElement addAttribute:[NSXMLNode attributeWithName:@"version" stringValue:@"1.0"]];

    for (NSDictionary *folder in folders) {
        NSString *folderIdentifier = [self stringValueFromDictionary:folder key:@"identifier" defaultValue:@""];
        if (folderIdentifier.length == 0) {
            continue;
        }

        NSXMLElement *folderElement = [NSXMLElement elementWithName:kRCXMLFolderElement];
        [folderElement addChild:[NSXMLElement elementWithName:kRCXMLFolderTitleElement
                                                  stringValue:[self stringValueFromDictionary:folder
                                                                                         key:@"title"
                                                                                defaultValue:@"untitled folder"]]];
        [folderElement addChild:[NSXMLElement elementWithName:kRCXMLFolderIdentifierElement stringValue:folderIdentifier]];
        [folderElement addChild:[NSXMLElement elementWithName:kRCXMLFolderEnabledElement
                                                  stringValue:[self xmlBooleanStringFromBool:[self boolValueFromDictionary:folder
                                                                                                                       key:@"enabled"
                                                                                                              defaultValue:YES]]]];

        NSXMLElement *snippetsElement = [NSXMLElement elementWithName:kRCXMLFolderSnippetsElement];
        NSArray<NSDictionary *> *snippets = [databaseManager fetchSnippetsForFolder:folderIdentifier];
        for (NSDictionary *snippet in snippets) {
            NSString *snippetIdentifier = [self stringValueFromDictionary:snippet key:@"identifier" defaultValue:@""];
            if (snippetIdentifier.length == 0) {
                snippetIdentifier = [NSUUID UUID].UUIDString;
            }

            NSXMLElement *snippetElement = [NSXMLElement elementWithName:kRCXMLSnippetElement];
            [snippetElement addChild:[NSXMLElement elementWithName:kRCXMLSnippetIdentifierElement stringValue:snippetIdentifier]];
            [snippetElement addChild:[NSXMLElement elementWithName:kRCXMLSnippetTitleElement
                                                       stringValue:[self stringValueFromDictionary:snippet
                                                                                              key:@"title"
                                                                                     defaultValue:@"untitled snippet"]]];
            [snippetElement addChild:[NSXMLElement elementWithName:kRCXMLSnippetContentElement
                                                       stringValue:[self stringValueFromDictionary:snippet
                                                                                              key:@"content"
                                                                                     defaultValue:@""]]];

            [snippetElement addChild:[NSXMLElement elementWithName:kRCXMLSnippetEnabledElement
                                                       stringValue:[self xmlBooleanStringFromBool:[self boolValueFromDictionary:snippet
                                                                                                                            key:@"enabled"
                                                                                                                   defaultValue:YES]]]];
            [snippetsElement addChild:snippetElement];
        }

        [folderElement addChild:snippetsElement];
        [rootElement addChild:folderElement];
    }

    NSXMLDocument *document = [[NSXMLDocument alloc] initWithRootElement:rootElement];
    document.version = @"1.0";
    document.characterEncoding = @"UTF-8";

    NSData *xmlData = [document XMLDataWithOptions:NSXMLNodePrettyPrint];
    if (xmlData.length == 0) {
        [self assignSnippetError:error
                            code:RCSnippetImportExportErrorFileWrite
                     description:@"Failed to build snippets XML data."
                 underlyingError:nil];
        return nil;
    }

    return xmlData;
}

#pragma mark - Import

- (BOOL)importSnippetsFromURL:(NSURL *)fileURL merge:(BOOL)merge error:(NSError **)error {
    if (![fileURL isFileURL]) {
        return [self assignSnippetError:error
                                   code:RCSnippetImportExportErrorFileRead
                            description:@"Import source is invalid."
                        underlyingError:nil];
    }

    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfURL:fileURL options:NSDataReadingMappedIfSafe error:&readError];
    if (data == nil) {
        return [self assignSnippetError:error
                                   code:RCSnippetImportExportErrorFileRead
                            description:@"Failed to read snippets XML file."
                        underlyingError:readError];
    }

    return [self importSnippetsFromData:data merge:merge error:error];
}

- (BOOL)importSnippetsFromData:(NSData *)data merge:(BOOL)merge error:(NSError **)error {
    if (data.length == 0) {
        return [self assignSnippetError:error
                                   code:RCSnippetImportExportErrorInvalidXMLFormat
                            description:@"Snippets XML data is empty."
                        underlyingError:nil];
    }

    RCDatabaseManager *databaseManager = [RCDatabaseManager shared];
    if (![databaseManager setupDatabase]) {
        return [self assignSnippetError:error
                                   code:RCSnippetImportExportErrorDatabase
                            description:@"Database is not ready."
                        underlyingError:nil];
    }

    NSError *parseError = nil;
    NSXMLDocument *document = [[NSXMLDocument alloc] initWithData:data options:0 error:&parseError];
    if (document == nil) {
        return [self assignSnippetError:error
                                   code:RCSnippetImportExportErrorInvalidXMLFormat
                            description:@"Failed to parse snippets XML."
                        underlyingError:parseError];
    }

    NSXMLElement *rootElement = document.rootElement;
    NSString *rootName = rootElement.name ?: @"";
    BOOL isRootSupported = [rootName isEqualToString:kRCXMLRootElement] || [rootName isEqualToString:kRCXMLLegacyRootElement];
    if (!isRootSupported) {
        return [self assignSnippetError:error
                                   code:RCSnippetImportExportErrorInvalidXMLFormat
                            description:@"Root element must be <folders> or <snippets>."
                        underlyingError:nil];
    }

    NSArray<NSDictionary *> *parsedFolders = [self parseFoldersFromRootElement:rootElement error:error];
    if (parsedFolders == nil) {
        return NO;
    }

    return [self persistParsedFolders:parsedFolders merge:merge error:error];
}

#pragma mark - Private: Persist

- (BOOL)persistParsedFolders:(NSArray<NSDictionary *> *)folders merge:(BOOL)merge error:(NSError **)error {
    RCDatabaseManager *databaseManager = [RCDatabaseManager shared];
    NSArray<NSDictionary *> *existingFolders = merge ? [databaseManager fetchAllSnippetFolders] : @[];

    NSMutableSet<NSString *> *plannedFolderIdentifiers = [NSMutableSet setWithCapacity:existingFolders.count + folders.count];
    NSMutableSet<NSString *> *reservedSnippetIdentifiers = [NSMutableSet set];
    if (merge) {
        for (NSDictionary *folder in existingFolders) {
            NSString *folderIdentifier = [self trimmedString:[self stringValueFromDictionary:folder key:@"identifier" defaultValue:@""]];
            if (folderIdentifier.length == 0) {
                continue;
            }

            [plannedFolderIdentifiers addObject:folderIdentifier];
            NSArray<NSDictionary *> *existingSnippets = [databaseManager fetchSnippetsForFolder:folderIdentifier];
            for (NSDictionary *snippet in existingSnippets) {
                NSString *snippetIdentifier = [self trimmedString:[self stringValueFromDictionary:snippet key:@"identifier" defaultValue:@""]];
                if (snippetIdentifier.length > 0) {
                    [reservedSnippetIdentifiers addObject:snippetIdentifier];
                }
            }
        }
    }

    NSInteger nextFolderIndex = merge ? [self nextFolderIndexFromExistingFolders:existingFolders] : 0;
    NSMutableArray<NSDictionary *> *foldersToInsert = [NSMutableArray arrayWithCapacity:folders.count];

    for (NSDictionary *parsedFolder in folders) {
        NSString *folderIdentifier = [self trimmedString:[self stringValueFromDictionary:parsedFolder key:@"identifier" defaultValue:@""]];
        if (folderIdentifier.length == 0) {
            folderIdentifier = [self uniqueIdentifierExcludingSet:plannedFolderIdentifiers];
        }

        if ([plannedFolderIdentifiers containsObject:folderIdentifier]) {
            continue;
        }

        NSArray<NSDictionary *> *parsedSnippets = [parsedFolder[@"snippets"] isKindOfClass:[NSArray class]]
            ? parsedFolder[@"snippets"]
            : @[];
        NSMutableArray<NSDictionary *> *snippetsToInsert = [NSMutableArray arrayWithCapacity:parsedSnippets.count];
        NSInteger snippetIndex = 0;
        for (NSDictionary *parsedSnippet in parsedSnippets) {
            NSString *snippetIdentifier = [self trimmedString:[self stringValueFromDictionary:parsedSnippet key:@"identifier" defaultValue:@""]];
            if (snippetIdentifier.length == 0) {
                snippetIdentifier = [self uniqueIdentifierExcludingSet:reservedSnippetIdentifiers];
            } else if ([reservedSnippetIdentifiers containsObject:snippetIdentifier]) {
                continue;
            }

            [reservedSnippetIdentifiers addObject:snippetIdentifier];

            NSDictionary *snippetDictionary = @{
                @"identifier": snippetIdentifier,
                @"folder_id": folderIdentifier,
                @"snippet_index": @(snippetIndex),
                @"enabled": @([self boolValueFromDictionary:parsedSnippet key:@"enabled" defaultValue:YES]),
                @"title": [self stringValueFromDictionary:parsedSnippet key:@"title" defaultValue:@"untitled snippet"],
                @"content": [self stringValueFromDictionary:parsedSnippet key:@"content" defaultValue:@""],
            };
            [snippetsToInsert addObject:snippetDictionary];
            snippetIndex += 1;
        }

        NSDictionary *folderDictionary = @{
            @"identifier": folderIdentifier,
            @"folder_index": @(nextFolderIndex),
            @"enabled": @([self boolValueFromDictionary:parsedFolder key:@"enabled" defaultValue:YES]),
            @"title": [self stringValueFromDictionary:parsedFolder key:@"title" defaultValue:@"untitled folder"],
            @"snippets": [snippetsToInsert copy],
        };
        [foldersToInsert addObject:folderDictionary];

        [plannedFolderIdentifiers addObject:folderIdentifier];
        nextFolderIndex += 1;
    }

    __block NSError *transactionError = nil;
    BOOL persisted = [databaseManager performTransaction:^BOOL(FMDatabase *db, BOOL *rollback) {
        if (!merge) {
            BOOL deleted = [db executeUpdate:@"DELETE FROM snippet_folders"];
            if (!deleted) {
                transactionError = [NSError errorWithDomain:@"com.revclip.database"
                                                       code:db.lastErrorCode
                                                   userInfo:@{NSLocalizedDescriptionKey: db.lastErrorMessage ?: @"Failed to delete all snippet_folders rows."}];
                *rollback = YES;
                return NO;
            }
        }

        for (NSDictionary *folderDictionary in foldersToInsert) {
            BOOL insertedFolder = [db executeUpdate:@"INSERT INTO snippet_folders (identifier, folder_index, enabled, title) VALUES (?, ?, ?, ?)"
                               withArgumentsInArray:@[
                                   [self stringValueFromDictionary:folderDictionary key:@"identifier" defaultValue:@""],
                                   folderDictionary[@"folder_index"] ?: @0,
                                   folderDictionary[@"enabled"] ?: @1,
                                   [self stringValueFromDictionary:folderDictionary key:@"title" defaultValue:@"untitled folder"],
                               ]];
            if (!insertedFolder) {
                transactionError = [NSError errorWithDomain:@"com.revclip.database"
                                                       code:db.lastErrorCode
                                                   userInfo:@{NSLocalizedDescriptionKey: db.lastErrorMessage ?: @"Failed to insert snippet folder."}];
                *rollback = YES;
                return NO;
            }

            NSArray<NSDictionary *> *snippets = [folderDictionary[@"snippets"] isKindOfClass:[NSArray class]]
                ? folderDictionary[@"snippets"]
                : @[];
            for (NSDictionary *snippetDictionary in snippets) {
                BOOL insertedSnippet = [db executeUpdate:@"INSERT INTO snippets (identifier, folder_id, snippet_index, enabled, title, content) VALUES (?, ?, ?, ?, ?, ?)"
                                    withArgumentsInArray:@[
                                        [self stringValueFromDictionary:snippetDictionary key:@"identifier" defaultValue:@""],
                                        [self stringValueFromDictionary:snippetDictionary key:@"folder_id" defaultValue:@""],
                                        snippetDictionary[@"snippet_index"] ?: @0,
                                        snippetDictionary[@"enabled"] ?: @1,
                                        [self stringValueFromDictionary:snippetDictionary key:@"title" defaultValue:@"untitled snippet"],
                                        [self stringValueFromDictionary:snippetDictionary key:@"content" defaultValue:@""],
                                    ]];
                if (!insertedSnippet) {
                    transactionError = [NSError errorWithDomain:@"com.revclip.database"
                                                           code:db.lastErrorCode
                                                       userInfo:@{NSLocalizedDescriptionKey: db.lastErrorMessage ?: @"Failed to insert snippet."}];
                    *rollback = YES;
                    return NO;
                }
            }
        }

        return YES;
    }];

    if (!persisted) {
        return [self assignSnippetError:error
                                   code:RCSnippetImportExportErrorDatabase
                            description:@"Failed to persist imported snippets."
                        underlyingError:transactionError];
    }

    return YES;
}

#pragma mark - Private: Parse

- (NSArray<NSDictionary *> *)parseFoldersFromRootElement:(NSXMLElement *)rootElement error:(NSError **)error {
    NSArray<NSXMLElement *> *folderElements = [rootElement elementsForName:kRCXMLFolderElement];
    NSMutableArray<NSDictionary *> *parsedFolders = [NSMutableArray arrayWithCapacity:folderElements.count];
    NSMutableSet<NSString *> *seenFolderIdentifiers = [NSMutableSet setWithCapacity:folderElements.count];

    for (NSXMLElement *folderElement in folderElements) {
        NSString *folderIdentifier = [self trimmedValueForElement:kRCXMLFolderIdentifierElement inElement:folderElement];
        if (folderIdentifier.length == 0) {
            folderIdentifier = [self uniqueIdentifierExcludingSet:seenFolderIdentifiers];
        }
        if ([seenFolderIdentifiers containsObject:folderIdentifier]) {
            continue;
        }
        [seenFolderIdentifiers addObject:folderIdentifier];

        NSString *folderTitle = [self valueForElement:kRCXMLFolderTitleElement inElement:folderElement] ?: @"untitled folder";
        BOOL folderEnabled = [self boolValueFromXMLString:[self valueForElement:kRCXMLFolderEnabledElement inElement:folderElement]
                                             defaultValue:YES];

        NSXMLElement *snippetsElement = [self firstChildElementNamed:kRCXMLFolderSnippetsElement inElement:folderElement];
        if (snippetsElement == nil) {
            [self assignSnippetError:error
                                code:RCSnippetImportExportErrorMissingRequiredElement
                         description:@"Missing required <snippets> element in <folder>."
                     underlyingError:nil];
            return nil;
        }

        NSArray<NSXMLElement *> *snippetElements = [snippetsElement elementsForName:kRCXMLSnippetElement];
        NSMutableArray<NSDictionary *> *parsedSnippets = [NSMutableArray arrayWithCapacity:snippetElements.count];
        for (NSXMLElement *snippetElement in snippetElements) {
            NSString *snippetIdentifier = [self trimmedValueForElement:kRCXMLSnippetIdentifierElement inElement:snippetElement];
            if (snippetIdentifier.length == 0) {
                snippetIdentifier = [NSUUID UUID].UUIDString;
            }
            NSString *snippetTitle = [self valueForElement:kRCXMLSnippetTitleElement inElement:snippetElement] ?: @"untitled snippet";
            NSString *snippetContent = [self valueForElement:kRCXMLSnippetContentElement inElement:snippetElement] ?: @"";
            BOOL snippetEnabled = [self boolValueFromXMLString:[self valueForElement:kRCXMLSnippetEnabledElement inElement:snippetElement]
                                                  defaultValue:YES];

            NSDictionary *parsedSnippet = @{
                @"identifier": snippetIdentifier,
                @"title": snippetTitle,
                @"content": snippetContent,
                @"enabled": @(snippetEnabled),
            };
            [parsedSnippets addObject:parsedSnippet];
        }

        NSDictionary *parsedFolder = @{
            @"identifier": folderIdentifier,
            @"title": folderTitle,
            @"enabled": @(folderEnabled),
            @"snippets": [parsedSnippets copy],
        };
        [parsedFolders addObject:parsedFolder];
    }

    return [parsedFolders copy];
}

- (NSXMLElement *)firstChildElementNamed:(NSString *)name inElement:(NSXMLElement *)element {
    NSArray<NSXMLElement *> *elements = [element elementsForName:name];
    return elements.firstObject;
}

- (NSString *)trimmedValueForElement:(NSString *)name inElement:(NSXMLElement *)element {
    NSString *value = [self valueForElement:name inElement:element];
    return [self trimmedString:value];
}

- (NSString *)valueForElement:(NSString *)name inElement:(NSXMLElement *)element {
    NSXMLElement *childElement = [self firstChildElementNamed:name inElement:element];
    if (childElement == nil) {
        return nil;
    }

    return childElement.stringValue;
}

- (BOOL)boolValueFromXMLString:(NSString *)value defaultValue:(BOOL)defaultValue {
    NSString *normalized = [[value ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if ([normalized isEqualToString:@"true"] || [normalized isEqualToString:@"yes"] || [normalized isEqualToString:@"1"]) {
        return YES;
    }
    if ([normalized isEqualToString:@"false"] || [normalized isEqualToString:@"no"] || [normalized isEqualToString:@"0"]) {
        return NO;
    }
    return defaultValue;
}

- (NSString *)xmlBooleanStringFromBool:(BOOL)value {
    return value ? @"true" : @"false";
}

- (NSString *)trimmedString:(NSString *)value {
    return [[value ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
}

- (NSString *)uniqueIdentifierExcludingSet:(NSSet<NSString *> *)reservedIdentifiers {
    NSString *identifier = [NSUUID UUID].UUIDString;
    while ([reservedIdentifiers containsObject:identifier]) {
        identifier = [NSUUID UUID].UUIDString;
    }
    return identifier;
}

#pragma mark - Private: Error

- (NSError *)snippetErrorWithCode:(RCSnippetImportExportErrorCode)code
                       description:(NSString *)description
                   underlyingError:(NSError *)underlyingError {
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    if (description.length > 0) {
        userInfo[NSLocalizedDescriptionKey] = description;
    }
    if (underlyingError != nil) {
        userInfo[NSUnderlyingErrorKey] = underlyingError;
    }

    return [NSError errorWithDomain:RCSnippetImportExportErrorDomain code:code userInfo:[userInfo copy]];
}

- (BOOL)assignSnippetError:(NSError **)error
                      code:(RCSnippetImportExportErrorCode)code
               description:(NSString *)description
           underlyingError:(NSError *)underlyingError {
    if (error != NULL) {
        *error = [self snippetErrorWithCode:code description:description underlyingError:underlyingError];
    }
    return NO;
}

#pragma mark - Private: Helpers

- (NSInteger)nextFolderIndexFromExistingFolders:(NSArray<NSDictionary *> *)folders {
    NSInteger maxIndex = -1;
    for (NSDictionary *folder in folders) {
        id rawIndex = folder[@"folder_index"];
        NSInteger folderIndex = 0;
        if ([rawIndex isKindOfClass:[NSNumber class]]) {
            folderIndex = [rawIndex integerValue];
        } else if ([rawIndex isKindOfClass:[NSString class]]) {
            folderIndex = [(NSString *)rawIndex integerValue];
        } else {
            continue;
        }
        if (folderIndex > maxIndex) {
            maxIndex = folderIndex;
        }
    }
    return maxIndex + 1;
}

- (NSString *)stringValueFromDictionary:(NSDictionary *)dictionary key:(NSString *)key defaultValue:(NSString *)defaultValue {
    id rawValue = dictionary[key];
    if ([rawValue isKindOfClass:[NSString class]]) {
        return (NSString *)rawValue;
    }
    if ([rawValue respondsToSelector:@selector(stringValue)]) {
        return [rawValue stringValue];
    }
    return defaultValue;
}

- (BOOL)boolValueFromDictionary:(NSDictionary *)dictionary key:(NSString *)key defaultValue:(BOOL)defaultValue {
    id rawValue = dictionary[key];
    if ([rawValue isKindOfClass:[NSNumber class]]) {
        return [rawValue boolValue];
    }
    if ([rawValue isKindOfClass:[NSString class]]) {
        return [self boolValueFromXMLString:(NSString *)rawValue defaultValue:defaultValue];
    }
    return defaultValue;
}

@end
