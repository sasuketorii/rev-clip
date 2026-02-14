//
//  RCDatabaseManager.h
//  Revpy
//
//  Copyright (c) 2024-2026 Revpy. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FMDatabase;

@interface RCDatabaseManager : NSObject

+ (instancetype)shared;

// データベースパス: ~/Library/Application Support/Revclip/revclip.db
@property (nonatomic, readonly) NSString *databasePath;

// 初期化・マイグレーション
- (BOOL)setupDatabase;
- (NSInteger)currentSchemaVersion;
- (BOOL)migrateIfNeeded;
- (BOOL)performTransaction:(BOOL (^)(FMDatabase *db, BOOL *rollback))block;

// clip_items CRUD
- (BOOL)insertClipItem:(NSDictionary *)clipDict;
- (BOOL)updateClipItemUpdateTime:(NSString *)dataHash time:(NSInteger)updateTime;
- (BOOL)deleteClipItemWithDataHash:(NSString *)dataHash;
- (BOOL)deleteClipItemsOlderThan:(NSInteger)updateTime;
- (NSArray *)fetchClipItemsWithLimit:(NSInteger)limit;
- (nullable NSDictionary *)clipItemWithDataHash:(NSString *)dataHash;
- (NSInteger)clipItemCount;

// snippet_folders CRUD
- (BOOL)insertSnippetFolder:(NSDictionary *)folderDict;
- (BOOL)updateSnippetFolder:(NSDictionary *)folderDict;
- (BOOL)updateSnippetFolder:(NSString *)identifier withDict:(NSDictionary *)dict;
- (BOOL)deleteSnippetFolder:(NSString *)identifier;
- (BOOL)deleteAllSnippetFolders;
- (NSArray *)fetchAllSnippetFolders;
- (BOOL)snippetFolderExistsWithIdentifier:(NSString *)identifier;

// snippets CRUD
- (BOOL)insertSnippet:(NSDictionary *)snippetDict;
- (BOOL)insertSnippet:(NSDictionary *)snippetDict inFolder:(NSString *)folderIdentifier;
- (BOOL)updateSnippet:(NSDictionary *)snippetDict;
- (BOOL)updateSnippet:(NSString *)identifier withDict:(NSDictionary *)dict;
- (BOOL)deleteSnippet:(NSString *)identifier;
- (NSArray *)fetchSnippetsForFolder:(NSString *)folderIdentifier;
- (BOOL)snippetExistsWithIdentifier:(NSString *)identifier;
- (BOOL)deleteAllClipItems;

@end

NS_ASSUME_NONNULL_END
