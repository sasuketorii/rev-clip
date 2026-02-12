//
//  RCDatabaseManager.h
//  Revclip
//
//  Copyright (c) 2024-2026 Revclip. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RCDatabaseManager : NSObject

+ (instancetype)shared;

// データベースパス: ~/Library/Application Support/Revclip/revclip.db
@property (nonatomic, readonly) NSString *databasePath;

// 初期化・マイグレーション
- (BOOL)setupDatabase;
- (NSInteger)currentSchemaVersion;
- (BOOL)migrateIfNeeded;

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
- (BOOL)updateSnippetFolder:(NSString *)identifier withDict:(NSDictionary *)dict;
- (BOOL)deleteSnippetFolder:(NSString *)identifier;
- (NSArray *)fetchAllSnippetFolders;

// snippets CRUD
- (BOOL)insertSnippet:(NSDictionary *)snippetDict;
- (BOOL)updateSnippet:(NSString *)identifier withDict:(NSDictionary *)dict;
- (BOOL)deleteSnippet:(NSString *)identifier;
- (NSArray *)fetchSnippetsForFolder:(NSString *)folderIdentifier;
- (BOOL)deleteAllClipItems;

@end

NS_ASSUME_NONNULL_END
