# SOW: Task 1-3 Database Layer

## 概要
- FMDB（latest stable tag: `2.7.12`）を `Revclip/Vendor/FMDB/` にソース直接組み込み。
- `RCDatabaseManager` を Objective-C で実装し、SQLiteスキーマ作成・マイグレーション枠・CRUDを追加。
- Xcodeプロジェクト定義を更新し、FMDBと`RCDatabaseManager`をビルド対象に追加。

## 実施内容
- `src/Revclip/Revclip/Vendor/FMDB/` に以下を追加:
  - `FMDB.h`
  - `FMDatabase.h/.m`
  - `FMDatabaseAdditions.h/.m`
  - `FMDatabasePool.h/.m`
  - `FMDatabaseQueue.h/.m`
  - `FMResultSet.h/.m`
- `src/Revclip/Revclip/Managers/RCDatabaseManager.h/.m` を新規作成:
  - シングルトン (`+shared`)
  - DBパス: `~/Library/Application Support/Revclip/revclip.db`
  - Application Support ディレクトリ自動作成
  - `FMDatabaseQueue` ベースのスレッドセーフアクセス
  - `PRAGMA foreign_keys = ON` の有効化
  - `setupDatabase` でスキーマ・インデックス作成
  - `currentSchemaVersion` / `migrateIfNeeded` 実装（現在 `schema_version=1`）
  - `clip_items` / `snippet_folders` / `snippets` のCRUD実装
  - fetch系は `NSDictionary` 配列・辞書を返却
- `src/Revclip/project.yml` を更新:
  - `OTHER_LDFLAGS` に `-lsqlite3` を追加
- `xcodegen generate` を実行して `src/Revclip/Revclip.xcodeproj/project.pbxproj` を再生成:
  - 新規ソース群を target sources に追加
  - `OTHER_LDFLAGS` 反映

## 検証結果
- `xcodebuild` は未実施（環境制約）:
  - `xcode-select: ... requires Xcode, but active developer directory '/Library/Developer/CommandLineTools'`
- 代替検証として、Command Line Tools の `clang` で以下を確認:
  - FMDB + `RCDatabaseManager.m` のコンパイル成功
  - `RCDatabaseManager` の実行スモークテスト成功（`setup=1`, `schema=1`）
  - CRUDスモークテスト成功（insert/update/fetch/delete/cascade delete）
- 生成DBの `.schema` を確認し、指定テーブル・インデックス定義が作成されることを確認

## 例外・省略
- Worktree作成は省略: ユーザーから「メインブランチで作業してOK」の明示許可あり。
- `/tmp` の一時ディレクトリ削除 (`rm -rf`) は実行ポリシーで拒否されるため未実施。
