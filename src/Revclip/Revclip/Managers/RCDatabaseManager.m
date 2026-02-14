//
//  RCDatabaseManager.m
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import "RCDatabaseManager.h"

#import "FMDB.h"

static NSInteger const kRCCurrentSchemaVersion = 1;

@interface RCDatabaseManager ()

@property (nonatomic, strong, nullable) FMDatabaseQueue *databaseQueue;
@property (nonatomic, readwrite, copy) NSString *databasePath;
@property (nonatomic, assign) BOOL setupCompleted;

@end

@implementation RCDatabaseManager

+ (instancetype)shared {
    static RCDatabaseManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] initPrivate];
    });
    return sharedManager;
}

- (instancetype)init {
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:@"Use +[RCDatabaseManager shared]."
                                 userInfo:nil];
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _databasePath = [[self class] defaultDatabasePath];
        _setupCompleted = NO;
    }
    return self;
}

#pragma mark - Public: Setup / Migration

- (BOOL)setupDatabase {
    @synchronized (self) {
        if (self.setupCompleted) {
            return YES;
        }

        if (![self ensureDatabaseQueue]) {
            return NO;
        }

        __block BOOL setupSucceeded = YES;
        [self.databaseQueue inDatabase:^(FMDatabase * _Nonnull db) {
            if (![self enableForeignKeysForDatabase:db]) {
                setupSucceeded = NO;
                return;
            }

            setupSucceeded = [self createBaseSchemaInDatabase:db];
        }];

        if (!setupSucceeded) {
            return NO;
        }

        BOOL migrated = [self migrateIfNeeded];
        if (!migrated) {
            return NO;
        }

        self.setupCompleted = YES;
        return YES;
    }
}

- (NSInteger)currentSchemaVersion {
    if (![self ensureDatabaseQueue]) {
        return 0;
    }

    __block NSInteger version = 0;
    [self.databaseQueue inDatabase:^(FMDatabase * _Nonnull db) {
        if (![self enableForeignKeysForDatabase:db]) {
            return;
        }

        if (![db executeUpdate:@"CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL)"]) {
            [self logDatabaseError:db context:@"Failed to create schema_version table before reading version"];
            return;
        }

        FMResultSet *resultSet = [db executeQuery:@"SELECT MAX(version) AS version FROM schema_version"];
        if (!resultSet) {
            [self logDatabaseError:db context:@"Failed to fetch schema version"];
            return;
        }

        if ([resultSet next]) {
            version = [resultSet intForColumn:@"version"];
        }
        [resultSet close];
    }];

    return version;
}

- (BOOL)migrateIfNeeded {
    if (![self ensureDatabaseQueue]) {
        return NO;
    }

    NSInteger version = [self currentSchemaVersion];
    if (version >= kRCCurrentSchemaVersion) {
        return YES;
    }

    __block BOOL migrated = YES;
    [self.databaseQueue inTransaction:^(FMDatabase * _Nonnull db, BOOL * _Nonnull rollback) {
        if (![self enableForeignKeysForDatabase:db]) {
            migrated = NO;
            *rollback = YES;
            return;
        }

        if (version == 0 && ![self createBaseSchemaInDatabase:db]) {
            migrated = NO;
            *rollback = YES;
            return;
        }

        // v1 is the baseline schema.
        NSInteger workingVersion = version;
        while (workingVersion < kRCCurrentSchemaVersion) {
            NSInteger nextVersion = workingVersion + 1;
            switch (nextVersion) {
                case 1:
                    break;
                default:
                    migrated = NO;
                    *rollback = YES;
                    NSLog(@"[RCDatabaseManager] Unknown migration target version: %ld", (long)nextVersion);
                    return;
            }
            workingVersion = nextVersion;
        }

        if (![db executeUpdate:@"DELETE FROM schema_version"]) {
            [self logDatabaseError:db context:@"Failed to clear schema_version during migration"];
            migrated = NO;
            *rollback = YES;
            return;
        }

        if (![db executeUpdate:@"INSERT INTO schema_version (version) VALUES (?)", @(kRCCurrentSchemaVersion)]) {
            [self logDatabaseError:db context:@"Failed to write schema_version during migration"];
            migrated = NO;
            *rollback = YES;
            return;
        }
    }];

    return migrated;
}

- (BOOL)performTransaction:(BOOL (^)(FMDatabase *db, BOOL *rollback))block {
    if (block == nil || ![self ensureDatabaseReadyForOperation]) {
        return NO;
    }

    __block BOOL succeeded = YES;
    [self.databaseQueue inTransaction:^(FMDatabase * _Nonnull db, BOOL * _Nonnull rollback) {
        if (![self enableForeignKeysForDatabase:db]) {
            succeeded = NO;
            *rollback = YES;
            return;
        }

        BOOL operationSucceeded = block(db, rollback);
        if (!operationSucceeded || *rollback) {
            succeeded = NO;
            *rollback = YES;
        }
    }];

    return succeeded;
}

#pragma mark - Public: clip_items

- (BOOL)insertClipItem:(NSDictionary *)clipDict {
    if (![self ensureDatabaseReadyForOperation]) {
        return NO;
    }

    NSString *dataPath = [self stringValueInDictionary:clipDict keys:@[@"data_path", @"dataPath"] defaultValue:nil];
    NSString *dataHash = [self stringValueInDictionary:clipDict keys:@[@"data_hash", @"dataHash"] defaultValue:nil];
    NSNumber *updateTime = [self numberValueInDictionary:clipDict keys:@[@"update_time", @"updateTime"] defaultValue:nil];

    if (dataPath.length == 0 || dataHash.length == 0 || updateTime == nil) {
        return NO;
    }

    NSString *title = [self stringValueInDictionary:clipDict keys:@[@"title"] defaultValue:@""];
    NSString *primaryType = [self stringValueInDictionary:clipDict keys:@[@"primary_type", @"primaryType"] defaultValue:@""];
    NSString *thumbnailPath = [self stringValueInDictionary:clipDict keys:@[@"thumbnail_path", @"thumbnailPath"] defaultValue:@""];
    NSNumber *isColorCode = [self numberValueInDictionary:clipDict keys:@[@"is_color_code", @"isColorCode"] defaultValue:@0];

    __block BOOL inserted = NO;
    [self.databaseQueue inDatabase:^(FMDatabase * _Nonnull db) {
        if (![self enableForeignKeysForDatabase:db]) {
            return;
        }

        inserted = [db executeUpdate:@"INSERT INTO clip_items (data_path, title, data_hash, primary_type, update_time, thumbnail_path, is_color_code) VALUES (?, ?, ?, ?, ?, ?, ?)"
                     withArgumentsInArray:@[dataPath, title, dataHash, primaryType, updateTime, thumbnailPath, isColorCode]];
        if (!inserted) {
            [self logDatabaseError:db context:@"Failed to insert clip_items row"];
        }
    }];

    return inserted;
}

- (BOOL)updateClipItemUpdateTime:(NSString *)dataHash time:(NSInteger)updateTime {
    if (dataHash.length == 0 || ![self ensureDatabaseReadyForOperation]) {
        return NO;
    }

    __block BOOL updated = NO;
    [self.databaseQueue inDatabase:^(FMDatabase * _Nonnull db) {
        if (![self enableForeignKeysForDatabase:db]) {
            return;
        }

        updated = [db executeUpdate:@"UPDATE clip_items SET update_time = ? WHERE data_hash = ?"
               withArgumentsInArray:@[@(updateTime), dataHash]];
        if (!updated) {
            [self logDatabaseError:db context:@"Failed to update clip_items.update_time"];
        }
    }];

    return updated;
}

- (BOOL)deleteClipItemWithDataHash:(NSString *)dataHash {
    if (dataHash.length == 0 || ![self ensureDatabaseReadyForOperation]) {
        return NO;
    }

    __block BOOL deleted = NO;
    [self.databaseQueue inDatabase:^(FMDatabase * _Nonnull db) {
        if (![self enableForeignKeysForDatabase:db]) {
            return;
        }

        deleted = [db executeUpdate:@"DELETE FROM clip_items WHERE data_hash = ?" withArgumentsInArray:@[dataHash]];
        if (!deleted) {
            [self logDatabaseError:db context:@"Failed to delete clip_items row by data_hash"];
        }
    }];

    return deleted;
}

- (BOOL)deleteClipItemsOlderThan:(NSInteger)updateTime {
    if (![self ensureDatabaseReadyForOperation]) {
        return NO;
    }

    __block BOOL deleted = NO;
    [self.databaseQueue inDatabase:^(FMDatabase * _Nonnull db) {
        if (![self enableForeignKeysForDatabase:db]) {
            return;
        }

        deleted = [db executeUpdate:@"DELETE FROM clip_items WHERE update_time < ?" withArgumentsInArray:@[@(updateTime)]];
        if (!deleted) {
            [self logDatabaseError:db context:@"Failed to delete old clip_items rows"];
        }
    }];

    return deleted;
}

- (NSArray *)fetchClipItemsWithLimit:(NSInteger)limit {
    if (limit <= 0 || ![self ensureDatabaseReadyForOperation]) {
        return @[];
    }

    __block NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    [self.databaseQueue inDatabase:^(FMDatabase * _Nonnull db) {
        if (![self enableForeignKeysForDatabase:db]) {
            return;
        }

        FMResultSet *resultSet = [db executeQuery:@"SELECT id, data_path, title, data_hash, primary_type, update_time, thumbnail_path, is_color_code FROM clip_items ORDER BY update_time DESC LIMIT ?"
                             withArgumentsInArray:@[@(limit)]];
        if (!resultSet) {
            [self logDatabaseError:db context:@"Failed to fetch clip_items list"];
            return;
        }

        while ([resultSet next]) {
            [rows addObject:[self clipItemDictionaryFromResultSet:resultSet]];
        }
        [resultSet close];
    }];

    return [rows copy];
}

- (NSDictionary *)clipItemWithDataHash:(NSString *)dataHash {
    if (dataHash.length == 0 || ![self ensureDatabaseReadyForOperation]) {
        return nil;
    }

    __block NSDictionary *clipItem = nil;
    [self.databaseQueue inDatabase:^(FMDatabase * _Nonnull db) {
        if (![self enableForeignKeysForDatabase:db]) {
            return;
        }

        FMResultSet *resultSet = [db executeQuery:@"SELECT id, data_path, title, data_hash, primary_type, update_time, thumbnail_path, is_color_code FROM clip_items WHERE data_hash = ? LIMIT 1"
                             withArgumentsInArray:@[dataHash]];
        if (!resultSet) {
            [self logDatabaseError:db context:@"Failed to fetch clip_items row by data_hash"];
            return;
        }

        if ([resultSet next]) {
            clipItem = [self clipItemDictionaryFromResultSet:resultSet];
        }
        [resultSet close];
    }];

    return clipItem;
}

- (NSInteger)clipItemCount {
    if (![self ensureDatabaseReadyForOperation]) {
        return 0;
    }

    __block NSInteger count = 0;
    [self.databaseQueue inDatabase:^(FMDatabase * _Nonnull db) {
        if (![self enableForeignKeysForDatabase:db]) {
            return;
        }

        FMResultSet *resultSet = [db executeQuery:@"SELECT COUNT(*) AS total FROM clip_items"];
        if (!resultSet) {
            [self logDatabaseError:db context:@"Failed to count clip_items rows"];
            return;
        }

        if ([resultSet next]) {
            count = [resultSet intForColumn:@"total"];
        }
        [resultSet close];
    }];

    return count;
}

- (BOOL)deleteAllClipItems {
    if (![self ensureDatabaseReadyForOperation]) {
        return NO;
    }

    __block BOOL deleted = NO;
    [self.databaseQueue inDatabase:^(FMDatabase * _Nonnull db) {
        if (![self enableForeignKeysForDatabase:db]) {
            return;
        }

        deleted = [db executeUpdate:@"DELETE FROM clip_items"];
        if (!deleted) {
            [self logDatabaseError:db context:@"Failed to delete all clip_items rows"];
        }
    }];

    return deleted;
}

#pragma mark - Public: snippet_folders

- (BOOL)insertSnippetFolder:(NSDictionary *)folderDict {
    if (![self ensureDatabaseReadyForOperation]) {
        return NO;
    }

    NSString *identifier = [self stringValueInDictionary:folderDict keys:@[@"identifier"] defaultValue:nil];
    if (identifier.length == 0) {
        return NO;
    }

    NSNumber *folderIndex = [self numberValueInDictionary:folderDict keys:@[@"folder_index", @"folderIndex"] defaultValue:@0];
    NSNumber *enabled = [self numberValueInDictionary:folderDict keys:@[@"enabled"] defaultValue:@1];
    NSString *title = [self stringValueInDictionary:folderDict keys:@[@"title"] defaultValue:@"untitled folder"];

    __block BOOL inserted = NO;
    [self.databaseQueue inDatabase:^(FMDatabase * _Nonnull db) {
        if (![self enableForeignKeysForDatabase:db]) {
            return;
        }

        inserted = [db executeUpdate:@"INSERT INTO snippet_folders (identifier, folder_index, enabled, title) VALUES (?, ?, ?, ?)"
                withArgumentsInArray:@[identifier, folderIndex, enabled, title]];
        if (!inserted) {
            [self logDatabaseError:db context:@"Failed to insert snippet_folders row"];
        }
    }];

    return inserted;
}

- (BOOL)updateSnippetFolder:(NSDictionary *)folderDict {
    NSString *identifier = [self stringValueInDictionary:folderDict keys:@[@"identifier"] defaultValue:nil];
    if (identifier.length == 0) {
        return NO;
    }

    NSMutableDictionary *mutableDict = [folderDict mutableCopy];
    [mutableDict removeObjectForKey:@"identifier"];
    return [self updateSnippetFolder:identifier withDict:[mutableDict copy]];
}

- (BOOL)updateSnippetFolder:(NSString *)identifier withDict:(NSDictionary *)dict {
    if (identifier.length == 0 || ![self ensureDatabaseReadyForOperation]) {
        return NO;
    }

    NSMutableArray<NSString *> *setClauses = [NSMutableArray array];
    NSMutableArray *arguments = [NSMutableArray array];

    NSNumber *folderIndex = [self numberValueInDictionary:dict keys:@[@"folder_index", @"folderIndex"] defaultValue:nil];
    if (folderIndex != nil) {
        [setClauses addObject:@"folder_index = ?"];
        [arguments addObject:folderIndex];
    }

    NSNumber *enabled = [self numberValueInDictionary:dict keys:@[@"enabled"] defaultValue:nil];
    if (enabled != nil) {
        [setClauses addObject:@"enabled = ?"];
        [arguments addObject:enabled];
    }

    NSString *title = [self stringValueInDictionary:dict keys:@[@"title"] defaultValue:nil];
    if (title != nil) {
        [setClauses addObject:@"title = ?"];
        [arguments addObject:title];
    }

    if (setClauses.count == 0) {
        return YES;
    }

    NSString *sql = [NSString stringWithFormat:@"UPDATE snippet_folders SET %@ WHERE identifier = ?", [setClauses componentsJoinedByString:@", "]];
    [arguments addObject:identifier];

    __block BOOL updated = NO;
    [self.databaseQueue inDatabase:^(FMDatabase * _Nonnull db) {
        if (![self enableForeignKeysForDatabase:db]) {
            return;
        }

        updated = [db executeUpdate:sql withArgumentsInArray:arguments];
        if (!updated) {
            [self logDatabaseError:db context:@"Failed to update snippet_folders row"];
        } else if (db.changes == 0) {
            updated = NO;
            NSLog(@"[RCDatabaseManager] updateSnippetFolder: no rows matched identifier");
        }
    }];

    return updated;
}

- (BOOL)deleteSnippetFolder:(NSString *)identifier {
    if (identifier.length == 0 || ![self ensureDatabaseReadyForOperation]) {
        return NO;
    }

    __block BOOL deleted = NO;
    [self.databaseQueue inDatabase:^(FMDatabase * _Nonnull db) {
        if (![self enableForeignKeysForDatabase:db]) {
            return;
        }

        deleted = [db executeUpdate:@"DELETE FROM snippet_folders WHERE identifier = ?" withArgumentsInArray:@[identifier]];
        if (!deleted) {
            [self logDatabaseError:db context:@"Failed to delete snippet_folders row"];
        }
    }];

    return deleted;
}

- (BOOL)deleteAllSnippetFolders {
    if (![self ensureDatabaseReadyForOperation]) {
        return NO;
    }

    __block BOOL deleted = NO;
    [self.databaseQueue inDatabase:^(FMDatabase * _Nonnull db) {
        if (![self enableForeignKeysForDatabase:db]) {
            return;
        }

        deleted = [db executeUpdate:@"DELETE FROM snippet_folders"];
        if (!deleted) {
            [self logDatabaseError:db context:@"Failed to delete all snippet_folders rows"];
        }
    }];

    return deleted;
}

- (NSArray *)fetchAllSnippetFolders {
    if (![self ensureDatabaseReadyForOperation]) {
        return @[];
    }

    __block NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    [self.databaseQueue inDatabase:^(FMDatabase * _Nonnull db) {
        if (![self enableForeignKeysForDatabase:db]) {
            return;
        }

        FMResultSet *resultSet = [db executeQuery:@"SELECT id, identifier, folder_index, enabled, title FROM snippet_folders ORDER BY folder_index ASC, id ASC"];
        if (!resultSet) {
            [self logDatabaseError:db context:@"Failed to fetch snippet_folders rows"];
            return;
        }

        while ([resultSet next]) {
            [rows addObject:[self snippetFolderDictionaryFromResultSet:resultSet]];
        }
        [resultSet close];
    }];

    return [rows copy];
}

- (BOOL)snippetFolderExistsWithIdentifier:(NSString *)identifier {
    if (identifier.length == 0 || ![self ensureDatabaseReadyForOperation]) {
        return NO;
    }

    __block BOOL exists = NO;
    [self.databaseQueue inDatabase:^(FMDatabase * _Nonnull db) {
        if (![self enableForeignKeysForDatabase:db]) {
            return;
        }

        FMResultSet *resultSet = [db executeQuery:@"SELECT 1 FROM snippet_folders WHERE identifier = ? LIMIT 1"
                             withArgumentsInArray:@[identifier]];
        if (!resultSet) {
            [self logDatabaseError:db context:@"Failed to check snippet_folders identifier"];
            return;
        }

        exists = [resultSet next];
        [resultSet close];
    }];

    return exists;
}

#pragma mark - Public: snippets

- (BOOL)insertSnippet:(NSDictionary *)snippetDict {
    if (![self ensureDatabaseReadyForOperation]) {
        return NO;
    }

    NSString *identifier = [self stringValueInDictionary:snippetDict keys:@[@"identifier"] defaultValue:nil];
    NSString *folderID = [self stringValueInDictionary:snippetDict keys:@[@"folder_id", @"folderId"] defaultValue:nil];

    if (identifier.length == 0 || folderID.length == 0) {
        return NO;
    }

    NSNumber *snippetIndex = [self numberValueInDictionary:snippetDict keys:@[@"snippet_index", @"snippetIndex"] defaultValue:@0];
    NSNumber *enabled = [self numberValueInDictionary:snippetDict keys:@[@"enabled"] defaultValue:@1];
    NSString *title = [self stringValueInDictionary:snippetDict keys:@[@"title"] defaultValue:@"untitled snippet"];
    NSString *content = [self stringValueInDictionary:snippetDict keys:@[@"content"] defaultValue:@""];

    __block BOOL inserted = NO;
    [self.databaseQueue inDatabase:^(FMDatabase * _Nonnull db) {
        if (![self enableForeignKeysForDatabase:db]) {
            return;
        }

        inserted = [db executeUpdate:@"INSERT INTO snippets (identifier, folder_id, snippet_index, enabled, title, content) VALUES (?, ?, ?, ?, ?, ?)"
                withArgumentsInArray:@[identifier, folderID, snippetIndex, enabled, title, content]];
        if (!inserted) {
            [self logDatabaseError:db context:@"Failed to insert snippets row"];
        }
    }];

    return inserted;
}

- (BOOL)insertSnippet:(NSDictionary *)snippetDict inFolder:(NSString *)folderIdentifier {
    if (folderIdentifier.length == 0) {
        return NO;
    }

    NSMutableDictionary *mutableDict = [snippetDict mutableCopy];
    if (mutableDict == nil) {
        mutableDict = [NSMutableDictionary dictionary];
    }
    mutableDict[@"folder_id"] = folderIdentifier;
    return [self insertSnippet:[mutableDict copy]];
}

- (BOOL)updateSnippet:(NSDictionary *)snippetDict {
    NSString *identifier = [self stringValueInDictionary:snippetDict keys:@[@"identifier"] defaultValue:nil];
    if (identifier.length == 0) {
        return NO;
    }

    NSMutableDictionary *mutableDict = [snippetDict mutableCopy];
    [mutableDict removeObjectForKey:@"identifier"];
    return [self updateSnippet:identifier withDict:[mutableDict copy]];
}

- (BOOL)updateSnippet:(NSString *)identifier withDict:(NSDictionary *)dict {
    if (identifier.length == 0 || ![self ensureDatabaseReadyForOperation]) {
        return NO;
    }

    NSMutableArray<NSString *> *setClauses = [NSMutableArray array];
    NSMutableArray *arguments = [NSMutableArray array];

    NSString *folderID = [self stringValueInDictionary:dict keys:@[@"folder_id", @"folderId"] defaultValue:nil];
    if (folderID != nil) {
        [setClauses addObject:@"folder_id = ?"];
        [arguments addObject:folderID];
    }

    NSNumber *snippetIndex = [self numberValueInDictionary:dict keys:@[@"snippet_index", @"snippetIndex"] defaultValue:nil];
    if (snippetIndex != nil) {
        [setClauses addObject:@"snippet_index = ?"];
        [arguments addObject:snippetIndex];
    }

    NSNumber *enabled = [self numberValueInDictionary:dict keys:@[@"enabled"] defaultValue:nil];
    if (enabled != nil) {
        [setClauses addObject:@"enabled = ?"];
        [arguments addObject:enabled];
    }

    NSString *title = [self stringValueInDictionary:dict keys:@[@"title"] defaultValue:nil];
    if (title != nil) {
        [setClauses addObject:@"title = ?"];
        [arguments addObject:title];
    }

    NSString *content = [self stringValueInDictionary:dict keys:@[@"content"] defaultValue:nil];
    if (content != nil) {
        [setClauses addObject:@"content = ?"];
        [arguments addObject:content];
    }

    if (setClauses.count == 0) {
        return YES;
    }

    NSString *sql = [NSString stringWithFormat:@"UPDATE snippets SET %@ WHERE identifier = ?", [setClauses componentsJoinedByString:@", "]];
    [arguments addObject:identifier];

    __block BOOL updated = NO;
    [self.databaseQueue inDatabase:^(FMDatabase * _Nonnull db) {
        if (![self enableForeignKeysForDatabase:db]) {
            return;
        }

        updated = [db executeUpdate:sql withArgumentsInArray:arguments];
        if (!updated) {
            [self logDatabaseError:db context:@"Failed to update snippets row"];
        } else if (db.changes == 0) {
            updated = NO;
            NSLog(@"[RCDatabaseManager] updateSnippet: no rows matched identifier");
        }
    }];

    return updated;
}

- (BOOL)deleteSnippet:(NSString *)identifier {
    if (identifier.length == 0 || ![self ensureDatabaseReadyForOperation]) {
        return NO;
    }

    __block BOOL deleted = NO;
    [self.databaseQueue inDatabase:^(FMDatabase * _Nonnull db) {
        if (![self enableForeignKeysForDatabase:db]) {
            return;
        }

        deleted = [db executeUpdate:@"DELETE FROM snippets WHERE identifier = ?" withArgumentsInArray:@[identifier]];
        if (!deleted) {
            [self logDatabaseError:db context:@"Failed to delete snippets row"];
        }
    }];

    return deleted;
}

- (NSArray *)fetchSnippetsForFolder:(NSString *)folderIdentifier {
    if (folderIdentifier.length == 0 || ![self ensureDatabaseReadyForOperation]) {
        return @[];
    }

    __block NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    [self.databaseQueue inDatabase:^(FMDatabase * _Nonnull db) {
        if (![self enableForeignKeysForDatabase:db]) {
            return;
        }

        FMResultSet *resultSet = [db executeQuery:@"SELECT id, identifier, folder_id, snippet_index, enabled, title, content FROM snippets WHERE folder_id = ? ORDER BY snippet_index ASC, id ASC"
                             withArgumentsInArray:@[folderIdentifier]];
        if (!resultSet) {
            [self logDatabaseError:db context:@"Failed to fetch snippets rows"];
            return;
        }

        while ([resultSet next]) {
            [rows addObject:[self snippetDictionaryFromResultSet:resultSet]];
        }
        [resultSet close];
    }];

    return [rows copy];
}

- (BOOL)snippetExistsWithIdentifier:(NSString *)identifier {
    if (identifier.length == 0 || ![self ensureDatabaseReadyForOperation]) {
        return NO;
    }

    __block BOOL exists = NO;
    [self.databaseQueue inDatabase:^(FMDatabase * _Nonnull db) {
        if (![self enableForeignKeysForDatabase:db]) {
            return;
        }

        FMResultSet *resultSet = [db executeQuery:@"SELECT 1 FROM snippets WHERE identifier = ? LIMIT 1"
                             withArgumentsInArray:@[identifier]];
        if (!resultSet) {
            [self logDatabaseError:db context:@"Failed to check snippets identifier"];
            return;
        }

        exists = [resultSet next];
        [resultSet close];
    }];

    return exists;
}

#pragma mark - Private: Database setup

+ (NSString *)defaultDatabasePath {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *applicationSupportPath = paths.firstObject;
    if (applicationSupportPath.length == 0) {
        applicationSupportPath = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library"] stringByAppendingPathComponent:@"Application Support"];
    }

    NSString *revclipDirectoryPath = [applicationSupportPath stringByAppendingPathComponent:@"Revclip"];
    return [revclipDirectoryPath stringByAppendingPathComponent:@"revclip.db"];
}

- (BOOL)ensureDatabaseReadyForOperation {
    if (self.setupCompleted) {
        return YES;
    }

    return [self setupDatabase];
}

- (BOOL)ensureDatabaseQueue {
    if (self.databaseQueue != nil) {
        return YES;
    }

    NSString *directoryPath = [self.databasePath stringByDeletingLastPathComponent];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    BOOL exists = [fileManager fileExistsAtPath:directoryPath isDirectory:&isDirectory];

    if (exists && !isDirectory) {
        NSLog(@"[RCDatabaseManager] Expected directory but found file at path: %@", directoryPath);
        return NO;
    }

    if (!exists) {
        NSError *directoryError = nil;
        BOOL created = [fileManager createDirectoryAtPath:directoryPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&directoryError];
        if (!created || directoryError != nil) {
            NSLog(@"[RCDatabaseManager] Failed to create Application Support directory: %@", directoryError);
            return NO;
        }
    }

    self.databaseQueue = [FMDatabaseQueue databaseQueueWithPath:self.databasePath];
    if (self.databaseQueue == nil) {
        NSLog(@"[RCDatabaseManager] Failed to create FMDatabaseQueue for path: %@", self.databasePath);
        return NO;
    }

    return YES;
}

- (BOOL)createBaseSchemaInDatabase:(FMDatabase *)db {
    NSArray<NSString *> *schemaStatements = @[
        @"CREATE TABLE IF NOT EXISTS clip_items (id INTEGER PRIMARY KEY AUTOINCREMENT, data_path TEXT NOT NULL, title TEXT DEFAULT '', data_hash TEXT UNIQUE NOT NULL, primary_type TEXT DEFAULT '', update_time INTEGER NOT NULL, thumbnail_path TEXT DEFAULT '', is_color_code INTEGER DEFAULT 0)",
        @"CREATE INDEX IF NOT EXISTS idx_clip_update_time ON clip_items(update_time DESC)",
        @"CREATE INDEX IF NOT EXISTS idx_clip_data_hash ON clip_items(data_hash)",
        @"CREATE TABLE IF NOT EXISTS snippet_folders (id INTEGER PRIMARY KEY AUTOINCREMENT, identifier TEXT UNIQUE NOT NULL, folder_index INTEGER DEFAULT 0, enabled INTEGER DEFAULT 1, title TEXT DEFAULT 'untitled folder')",
        @"CREATE INDEX IF NOT EXISTS idx_folder_index ON snippet_folders(folder_index)",
        @"CREATE TABLE IF NOT EXISTS snippets (id INTEGER PRIMARY KEY AUTOINCREMENT, identifier TEXT UNIQUE NOT NULL, folder_id TEXT NOT NULL REFERENCES snippet_folders(identifier) ON DELETE CASCADE, snippet_index INTEGER DEFAULT 0, enabled INTEGER DEFAULT 1, title TEXT DEFAULT 'untitled snippet', content TEXT DEFAULT '')",
        @"CREATE INDEX IF NOT EXISTS idx_snippet_folder ON snippets(folder_id)",
        @"CREATE INDEX IF NOT EXISTS idx_snippet_index ON snippets(snippet_index)",
        @"CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL)",
    ];

    for (NSString *statement in schemaStatements) {
        if (![db executeUpdate:statement]) {
            [self logDatabaseError:db context:[NSString stringWithFormat:@"Failed to execute schema statement: %@", statement]];
            return NO;
        }
    }

    BOOL insertedVersion = [db executeUpdate:@"INSERT INTO schema_version (version) SELECT ? WHERE NOT EXISTS (SELECT 1 FROM schema_version)"
                        withArgumentsInArray:@[@(kRCCurrentSchemaVersion)]];
    if (!insertedVersion) {
        [self logDatabaseError:db context:@"Failed to initialize schema_version row"];
        return NO;
    }

    return YES;
}

- (BOOL)enableForeignKeysForDatabase:(FMDatabase *)db {
    BOOL enabled = [db executeUpdate:@"PRAGMA foreign_keys = ON"];
    if (!enabled) {
        [self logDatabaseError:db context:@"Failed to enable foreign_keys pragma"];
    }
    return enabled;
}

- (void)logDatabaseError:(FMDatabase *)db context:(NSString *)context {
    NSLog(@"[RCDatabaseManager] %@ (code=%d, message=%@)", context, db.lastErrorCode, db.lastErrorMessage);
}

#pragma mark - Private: Dictionary helpers

- (nullable id)nonNullValueInDictionary:(NSDictionary *)dictionary keys:(NSArray<NSString *> *)keys {
    for (NSString *key in keys) {
        id value = dictionary[key];
        if (value != nil && value != [NSNull null]) {
            return value;
        }
    }
    return nil;
}

- (nullable NSString *)stringValueInDictionary:(NSDictionary *)dictionary
                                          keys:(NSArray<NSString *> *)keys
                                   defaultValue:(nullable NSString *)defaultValue {
    id rawValue = [self nonNullValueInDictionary:dictionary keys:keys];
    if (rawValue == nil) {
        return defaultValue;
    }

    if ([rawValue isKindOfClass:[NSString class]]) {
        return rawValue;
    }

    if ([rawValue respondsToSelector:@selector(stringValue)]) {
        return [rawValue stringValue];
    }

    return defaultValue;
}

- (nullable NSNumber *)numberValueInDictionary:(NSDictionary *)dictionary
                                          keys:(NSArray<NSString *> *)keys
                                   defaultValue:(nullable NSNumber *)defaultValue {
    id rawValue = [self nonNullValueInDictionary:dictionary keys:keys];
    if (rawValue == nil) {
        return defaultValue;
    }

    if ([rawValue isKindOfClass:[NSNumber class]]) {
        return rawValue;
    }

    if ([rawValue isKindOfClass:[NSString class]]) {
        return @([(NSString *)rawValue integerValue]);
    }

    return defaultValue;
}

#pragma mark - Private: ResultSet mapping

- (NSDictionary *)clipItemDictionaryFromResultSet:(FMResultSet *)resultSet {
    return @{
        @"id": @([resultSet longLongIntForColumn:@"id"]),
        @"data_path": [resultSet stringForColumn:@"data_path"] ?: @"",
        @"title": [resultSet stringForColumn:@"title"] ?: @"",
        @"data_hash": [resultSet stringForColumn:@"data_hash"] ?: @"",
        @"primary_type": [resultSet stringForColumn:@"primary_type"] ?: @"",
        @"update_time": @([resultSet longLongIntForColumn:@"update_time"]),
        @"thumbnail_path": [resultSet stringForColumn:@"thumbnail_path"] ?: @"",
        @"is_color_code": @([resultSet intForColumn:@"is_color_code"]),
    };
}

- (NSDictionary *)snippetFolderDictionaryFromResultSet:(FMResultSet *)resultSet {
    return @{
        @"id": @([resultSet longLongIntForColumn:@"id"]),
        @"identifier": [resultSet stringForColumn:@"identifier"] ?: @"",
        @"folder_index": @([resultSet longLongIntForColumn:@"folder_index"]),
        @"enabled": @([resultSet intForColumn:@"enabled"]),
        @"title": [resultSet stringForColumn:@"title"] ?: @"",
    };
}

- (NSDictionary *)snippetDictionaryFromResultSet:(FMResultSet *)resultSet {
    return @{
        @"id": @([resultSet longLongIntForColumn:@"id"]),
        @"identifier": [resultSet stringForColumn:@"identifier"] ?: @"",
        @"folder_id": [resultSet stringForColumn:@"folder_id"] ?: @"",
        @"snippet_index": @([resultSet longLongIntForColumn:@"snippet_index"]),
        @"enabled": @([resultSet intForColumn:@"enabled"]),
        @"title": [resultSet stringForColumn:@"title"] ?: @"",
        @"content": [resultSet stringForColumn:@"content"] ?: @"",
    };
}

@end
