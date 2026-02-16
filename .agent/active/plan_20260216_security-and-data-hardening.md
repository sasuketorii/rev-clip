# ExecPlan: Security & Data Hardening

**Date**: 2026-02-16
**Status**: Draft (Rev.3 — レビュー指摘全件反映)
**Scope**: セキュリティ強化 + データ成長制御 + Auto-Expiry + Panic Button

---

## 背景

Codex xhigh 並列調査（5レーン）の結果に基づく実装プラン。
現在アプリは正常動作しており、バグ報告なし。既存動作を壊さないことが最優先。

### スコープ外（技術的限界のため除外）

- APFS/SSD上での物理的セキュア削除の保証
- at-rest暗号化（SQLCipher/AES-GCM）— 将来タスクとして記録のみ
- cryptographic erase（暗号化前提のため除外）
- swap/VM/クラッシュレポート/Unified Logging の痕跡完全消去
- Time Machine既存バックアップの削除
- ARC環境でのメモリゼロ化保証

---

## Phase 1: Data Growth Control（データ成長制御）

### 1-1. Per-item サイズ上限の導入

**対象ファイル:**
- `src/Revclip/Revclip/App/RCConstants.h` — 新定数追加
- `src/Revclip/Revclip/App/RCConstants.m` — 新定数定義
- `src/Revclip/Revclip/Utilities/RCUtilities.m` — デフォルト値登録
- `src/Revclip/Revclip/Services/RCClipboardService.m` — 保存前サイズチェック
- `src/Revclip/Revclip/Services/RCScreenshotMonitorService.m` — スクショ保存前サイズチェック

**仕様:**
- `kRCPrefMaxClipSizeBytesKey` を追加（デフォルト: 50MB = 52428800）
- `RCClipboardService` の保存処理で `NSKeyedArchiver` 後のデータサイズを検証
- 超過時はスキップ（保存しない）し、`os_log` でdebugログ出力
- スクリーンショットも同一制限を適用

### 1-2. サムネイル圧縮保存（サムネイルのみ対象）

**対象ファイル:**
- `src/Revclip/Revclip/Services/RCScreenshotMonitorService.m` — サムネイル生成時にJPEG変換
- `src/Revclip/Revclip/Services/RCClipboardService.m` — サムネイル生成時にJPEG変換

**仕様:**
- **画像本体（`TIFFData`）はTIFFのまま維持** — 貼り付け経路（`RCClipData` → `NSPasteboardTypeTIFF`）の互換性を保証
- **サムネイルのみ**をJPEG（quality 0.7）で保存しサイズ削減
- サムネイル生成時に `NSBitmapImageRep` → `representationUsingType:NSBitmapImageFileTypeJPEG` を使用
- 既存の `.thumbnail.tiff` 命名規則は維持（互換性。中身はJPEGだが拡張子は変更しない）
- **注意**: `RCClipData.TIFFData` の型・保存・復元・貼り付けには一切手を加えない

### 1-3. 保存直後の軽量トリム

**対象ファイル:**
- `src/Revclip/Revclip/Services/RCClipboardService.m` — 挿入後にcleanupトリガー
- `src/Revclip/Revclip/Services/RCDataCleanService.h` — debounce cleanup API追加
- `src/Revclip/Revclip/Services/RCDataCleanService.m` — debounce実装

**仕様:**
- クリップ保存成功後に `RCDataCleanService` の debounce cleanup をトリガー
- **`RCScreenshotMonitorService` の保存成功後にも同じ debounce cleanup をトリガー**
- debounce間隔: 5秒（高頻度コピーでも5秒に1回までに抑制）
- 30分タイマーは保険として維持
- `dispatch_source` タイマーで debounce を実装

**対象ファイル（追加）:**
- `src/Revclip/Revclip/Services/RCScreenshotMonitorService.m` — 保存成功後にdebounceトリガー追加

### 1-4. maxHistory サービス層 clamp

**対象ファイル:**
- `src/Revclip/Revclip/Services/RCDataCleanService.m` — clamp追加

**仕様:**
- `trimHistoryIfNeeded` で maxHistorySize を `1...9999` に強制 clamp
- `<=0` は `30`（デフォルト値）にフォールバック
- UI側の既存clampはそのまま維持

### 1-5. サムネイル寸法 clamp

**対象ファイル:**
- `src/Revclip/Revclip/Services/RCClipboardService.m` — clamp追加
- `src/Revclip/Revclip/Services/RCScreenshotMonitorService.m` — clamp追加
- `src/Revclip/Revclip/Managers/RCMenuManager.m` — clamp追加

**仕様:**
- NSUserDefaultsから読み取ったサムネイル幅/高さを `16...512` に clamp
- 読み取り箇所すべてで統一的に適用

---

## Phase 2: Auto-Expiry（自動期限切れ削除）

### 2-1. Preference キー追加

**対象ファイル:**
- `src/Revclip/Revclip/App/RCConstants.h` — キー宣言 + enum定義
- `src/Revclip/Revclip/App/RCConstants.m` — キー定義
- `src/Revclip/Revclip/Utilities/RCUtilities.m` — デフォルト値登録

**仕様:**
- `kRCPrefAutoExpiryEnabledKey` (BOOL, default: NO)
- `kRCPrefAutoExpiryValueKey` (NSInteger, default: 30)
- `kRCPrefAutoExpiryUnitKey` (NSInteger, default: 0)
- enum `RCAutoExpiryUnit`: `RCAutoExpiryUnitDay=0`, `RCAutoExpiryUnitHour=1`, `RCAutoExpiryUnitMinute=2`

### 2-2. DB メソッド強化

**対象ファイル:**
- `src/Revclip/Revclip/Managers/RCDatabaseManager.h` — 新メソッド宣言
- `src/Revclip/Revclip/Managers/RCDatabaseManager.m` — 新メソッド実装

**仕様:**
- `- (NSArray<RCClipItem *> *)clipItemsOlderThan:(NSInteger)updateTimeMs;` を追加
- 既存の `deleteClipItemsOlderThan:` はそのまま維持
- 新メソッドは「対象行取得」のみ。削除は `RCDataCleanService` がDB削除+ファイル削除を一括実行

### 2-3. Expiry ロジック実装

**対象ファイル:**
- `src/Revclip/Revclip/Services/RCDataCleanService.h` — 新メソッド宣言
- `src/Revclip/Revclip/Services/RCDataCleanService.m` — expiry実装

**仕様:**
- `expireHistoryIfNeededWithDatabaseManager:` を追加
- Preference から enabled/value/unit を読み取り、期限ミリ秒を算出
- 期限切れアイテムを取得 → DB削除 → ファイル削除（既存 `removeFilesForClipItem:` 再利用）
- `performCleanupOnCleanupQueue` の実行順序を変更:
  1. `expireHistoryIfNeeded` (時間ベース)
  2. `trimHistoryIfNeeded` (件数ベース)
  3. `removeOrphanClipFiles` (孤立ファイル)
- **サービス層の最終防衛**: `enabled`/`value`/`unit` を必ず検証
  - `enabled` が BOOL でない場合 → `NO`（無効化）
  - `value` が `1...9999` 範囲外 → デフォルト `30` にフォールバック
  - `unit` が `0,1,2` 以外 → デフォルト `0`（Day）にフォールバック
  - NSUserDefaults 汚染時でも安全側に倒す設計

### 2-4. UI 実装

**対象ファイル:**
- `src/Revclip/Revclip/UI/Preferences/RCGeneralPreferencesViewController.h` — outlet/action宣言
- `src/Revclip/Revclip/UI/Preferences/RCGeneralPreferencesViewController.m` — UI制御実装
- `src/Revclip/Revclip/UI/Preferences/RCGeneralPreferencesView.xib` — UI要素追加

**仕様:**
- maxHistory行の直下に配置
- 行1: 「古い履歴を自動削除」チェックボックス
- 行2: 数値入力フィールド + ステッパー + 単位ポップアップ（Day/Hour/Minute）
- 無効時は行2の3コントロールを disabled
- 有効化/値変更/単位変更時に即時 cleanup 実行
- 値は `1...9999` に clamp

---

## Phase 3: Panic Button（緊急全削除）

### 3-1. RCPanicEraseService 新設

**対象ファイル（新規作成）:**
- `src/Revclip/Revclip/Services/RCPanicEraseService.h`
- `src/Revclip/Revclip/Services/RCPanicEraseService.m`

**仕様:**
- シングルトンサービス
- `- (void)executePanicEraseWithCompletion:(void(^)(BOOL success))completion;`
- 実行シーケンス:
  1. 再入防止フラグ設定
  2. **必要設定をローカル変数に退避**（「実行後終了」フラグ等 — NSUserDefaults リセット前に読み取る）
  3. **書き込み禁止フラグ設定** — 全サービスの書き込みAPIの入口でガードチェック
  4. 全監視停止（clipboard monitoring, screenshot monitoring, cleanup timer）
  5. **キュー排水（drain）** — **Panicシーケンス全体を専用バックグラウンド直列キュー（`panicQueue`）で実行**し、メインスレッドでのqueue drainを回避。各サービスキューへの排水は `dispatch_barrier_async` でフェンスを張り、書き込み禁止フラグとの組み合わせでin-flightジョブの自然終了を待つ。**`dispatch_sync` によるメインスレッドからのdrain は禁止**（`RCClipboardService` の `monitoringQueue → main queue` 同期呼び出しとのデッドロック防止）
  6. 全クリップファイル best-effort 上書き（1-pass zero fill） + 削除
  7. 全スニペットDB行削除
  8. DBファイル群（`.db`, `-journal`, `-wal`, `-shm`）を閉じて削除、再初期化
  9. NSPasteboard クリア
  10. メモリキャッシュクリア（thumbnailCache等）
  11. **NSUserDefaults ドメインリセット（最後に実行）**（`removePersistentDomainForName:`）
  12. **アプリ終了（固定動作）** — Panic実行後は常に `[NSApp terminate:nil]` でアプリを終了する。「終了しない」オプションは提供しない（理由: 全サービス停止・DB再初期化後の復帰シーケンスが複雑かつ半停止状態のリスクが高いため。再利用時はアプリ再起動で全サービスがクリーンに再初期化される）
- Panic中は NSLog 出力を最小化（パス/ハッシュを記録しない）
- **書き込み禁止フラグの実装**: `RCPanicEraseService` に `@property (atomic, assign) BOOL isPanicInProgress;` を公開し、各サービスのファイル書き込み・DB書き込みの入口で `if ([RCPanicEraseService sharedInstance].isPanicInProgress) return;` でガード

### 3-2. DB close/reopen API追加

**対象ファイル:**
- `src/Revclip/Revclip/Managers/RCDatabaseManager.h` — close/reinitialize宣言
- `src/Revclip/Revclip/Managers/RCDatabaseManager.m` — close/reinitialize実装

**仕様:**
- `- (void)closeDatabase;` — FMDatabaseQueue を close
- `- (void)deleteDatabaseFiles;` — .db, -journal, -wal, -shm を削除
- `- (void)reinitializeDatabase;` — DB再作成 + スキーマ再構築
- Panic フローから呼び出し

### 3-3. Panic ホットキー追加

**対象ファイル:**
- `src/Revclip/Revclip/App/RCConstants.h` — Panic設定キー追加
- `src/Revclip/Revclip/App/RCConstants.m` — Panic設定キー定義
- `src/Revclip/Revclip/Services/RCHotKeyService.h` — Panic hotkey登録
- `src/Revclip/Revclip/Services/RCHotKeyService.m` — Panic hotkey実装
- `src/Revclip/Revclip/Managers/RCMenuManager.m` — Panicメニュー項目追加

**仕様:**
- デフォルトホットキー: Cmd+Shift+Option+Delete（誤爆しにくい組み合わせ）
- メニューバーに「緊急削除」項目を追加（確認ダイアログ付き）
- ホットキーからの実行は確認ダイアログなし（即時実行）
- 設定画面でホットキーのカスタマイズ可能

### 3-4. Panic 設定 UI

**対象ファイル:**
- `src/Revclip/Revclip/UI/Preferences/RCShortcutsPreferencesViewController.h` — ホットキー設定
- `src/Revclip/Revclip/UI/Preferences/RCShortcutsPreferencesViewController.m` — ホットキー設定
- `src/Revclip/Revclip/UI/Preferences/RCShortcutsPreferencesView.xib` — ホットキー設定

**仕様:**
- **General設定にPanic関連UIは追加しない**（Panic後は常にアプリ終了で固定のため設定項目不要）
- **Shortcuts設定のみ**: Panicホットキーのカスタマイズを既存の Shortcuts 画面に追加（既存の保存/再登録/リセット導線と統合）
- ホットキー設定を General に置かない（既存の Shortcuts 画面との二重管理を回避）

---

## Phase 4: Security Hardening（セキュリティ強化）

### 4-1. ファイルパーミッション明示設定

**対象ファイル:**
- `src/Revclip/Revclip/Utilities/RCUtilities.m` — ディレクトリ作成時に0700
- `src/Revclip/Revclip/Models/RCClipData.m` — ファイル書き込み時に0600
- `src/Revclip/Revclip/Managers/RCDatabaseManager.m` — DB作成時にパーミッション設定

**仕様:**
- `~/Library/Application Support/Revclip/` ディレクトリ: 0700
- `ClipsData/` ディレクトリ: 0700
- `.rcclip` ファイル: 0600
- `.thumbnail.tiff` ファイル: 0600
- `revclip.db`: 0600
- ディレクトリ作成時に `NSFilePosixPermissions` を明示指定
- **起動時の既存ファイル修復**: `RCAppDelegate` の起動シーケンス内で以下に対して `NSFileManager setAttributes:` でパーミッションを再適用するワンショット処理を実行（既存ユーザー環境も強化）:
  - `Revclip/` ディレクトリ → 0700
  - `ClipsData/` ディレクトリ → 0700
  - `revclip.db` → 0600
  - `ClipsData/` 配下の既存 `.rcclip` / `.thumbnail.tiff` ファイル全て → 0600（`NSDirectoryEnumerator` で走査）

**対象ファイル（追加）:**
- `src/Revclip/Revclip/App/RCAppDelegate.m` — 起動時パーミッション修復呼び出し

### 4-2. PRAGMA secure_delete + 定期 VACUUM

**対象ファイル:**
- `src/Revclip/Revclip/Managers/RCDatabaseManager.m` — DB初期化時にPRAGMA設定

**仕様:**
- DB open後に `PRAGMA secure_delete = ON;` を実行
- `PRAGMA auto_vacuum = INCREMENTAL;` を設定（新規DB作成時のみ有効）
- **既存DB移行**: 起動時に `PRAGMA auto_vacuum;` を確認し、`0`（NONE）の場合は `PRAGMA auto_vacuum = INCREMENTAL;` 設定後に `VACUUM;` を1回実行して移行（auto_vacuumはVACUUM実行時のみ有効化される）。移行済みフラグを `NSUserDefaults` に記録し、2回目以降はスキップ。移行失敗時は `os_log` で警告を出すが動作は継続
- `RCDataCleanService` の30分cleanup時に `PRAGMA incremental_vacuum;` を実行
- WAL使用時は cleanup時に `PRAGMA wal_checkpoint(TRUNCATE);` も実行

**対象ファイル（追加）:**
- `src/Revclip/Revclip/Services/RCDataCleanService.m` — incremental_vacuum/wal_checkpoint実行

### 4-3. Time Machine / Spotlight 除外

**対象ファイル:**
- `src/Revclip/Revclip/Utilities/RCUtilities.m` — 除外属性設定

**仕様:**
- `~/Library/Application Support/Revclip/` に `NSURLIsExcludedFromBackupKey = YES` を設定
- `ClipsData/` に `.metadata_never_index` ファイルを作成（Spotlight除外）
- **呼び出し位置**: `RCAppDelegate` の `applicationDidFinishLaunching:` 内、DB初期化後・サービス起動前に `[RCUtilities applyDataProtectionAttributes]` を呼び出し
- `RCUtilities` に `+ (void)applyDataProtectionAttributes;` クラスメソッドを追加し、除外属性設定 + パーミッション修復（4-1）を統合

**対象ファイル（追加）:**
- `src/Revclip/Revclip/Utilities/RCUtilities.h` — メソッド宣言追加
- `src/Revclip/Revclip/App/RCAppDelegate.m` — 呼び出し追加

### 4-4. XXE 対策（XMLインポート）

**対象ファイル:**
- `src/Revclip/Revclip/Services/RCSnippetImportExportService.m` — XMLパーサ設定変更

**仕様:**
- `NSXMLDocument` 初期化時に `NSXMLNodeLoadExternalEntitiesNever` オプションを追加
- `<!DOCTYPE` を含むXMLを拒否（入力先頭チェック）
- インポート件数上限を追加: フォルダ上限100件、スニペット上限10000件
- タイトル長上限: 500文字、本文長上限: 1MB

### 4-5. パストラバーサル対策

**対象ファイル:**
- `src/Revclip/Revclip/Models/RCClipData.m` — 読み込み時にパス検証
- `src/Revclip/Revclip/Services/RCDataCleanService.m` — 既存検証を強化

**仕様:**
- `clipDataFromPath:` でパスが `ClipsData/` 配下であることを `canonicalPath` で検証
- DB保存時は相対ファイル名（UUID.rcclip）のみ格納を推奨（互換性のため段階移行）
- 境界外パスは拒否し、nilを返す

### 4-6. NSLog → os_log 移行（パス/メタデータ部分のみ）

**対象ファイル:**
- `src/Revclip/Revclip/Models/RCClipData.m` — os_log導入
- `src/Revclip/Revclip/Managers/RCDatabaseManager.m` — os_log導入
- `src/Revclip/Revclip/Services/RCClipboardService.m` — os_log導入
- `src/Revclip/Revclip/Services/RCDataCleanService.m` — os_log導入

**仕様:**
- パスやDBエラーを含むログを `os_log` の `%{private}@` で保護
- debug用の詳細ログは `OS_LOG_TYPE_DEBUG` レベルに制限
- 全NSLogをos_logに置換するのではなく、機密情報を含む箇所のみ対象

---

## Phase 5: Existing Deletion Enhancement（既存削除機能強化）

### 5-1. 完全履歴削除の強化

**対象ファイル:**
- `src/Revclip/Revclip/Managers/RCMenuManager.m` — 既存Clear History強化

**仕様:**
- 既存の `clearHistoryMenuItemSelected:` は Trash を経由しない（`removeItemAtPath:` 使用）ことを確認済み
- `secure_delete` PRAGMA が有効なので、DB DELETE 時にゼロ埋め実行
- 削除後に `PRAGMA incremental_vacuum;` を実行してDB縮小
- ファイル削除前に best-effort 上書き（Panic と同じロジックを共有）

### 5-2. DB定期メンテナンス

**対象ファイル:**
- `src/Revclip/Revclip/Services/RCDataCleanService.m` — VACUUM追加

**仕様:**
- 30分cleanupの最後に `PRAGMA incremental_vacuum;` を実行
- DB高水位サイズの継続的な縮小を実現

---

## 実装順序

```
Phase 1 (Data Growth)  ──→  Phase 2 (Auto-Expiry)  ──→  Phase 3 (Panic Button)
                                                               │
Phase 4 (Security)  ────────────────────────────────────────────┘
                                                               │
Phase 5 (Deletion Enhancement)  ───────────────────────────────┘
```

- Phase 1 と Phase 4 は独立して並列実装可能
- Phase 2 は Phase 1-4（maxHistory clamp）に依存
- Phase 3 は Phase 4-2（secure_delete）に依存
- Phase 5 は Phase 3 と Phase 4 に依存

---

## テスト方針

各Phaseで以下を確認:
1. 既存機能が壊れていないこと（コピー→ペースト、履歴表示、スニペット）
2. 新機能が仕様通り動作すること
3. エッジケース（極大値、0値、不正入力）の処理
4. メモリリーク/クラッシュがないこと

---

## 影響範囲サマリ

| ファイル | Phase | 変更内容 |
|---------|-------|---------|
| `RCConstants.h/m` | 1,2,3 | 新定数・enum追加 |
| `RCUtilities.h/m` | 1,2,4 | デフォルト値登録、パーミッション修復、除外属性、`applyDataProtectionAttributes` |
| `RCAppDelegate.m` | 4 | 起動時にデータ保護属性適用呼び出し |
| `RCClipboardService.m` | 1 | サイズチェック、debounceトリガー、サムネイルclamp、サムネイルJPEG化 |
| `RCScreenshotMonitorService.m` | 1 | サムネイルJPEG化、サイズチェック、サムネイルclamp、debounceトリガー |
| `RCDataCleanService.h/m` | 1,2,4,5 | debounce、expiry（値検証含む）、clamp、VACUUM、incremental_vacuum |
| `RCDatabaseManager.h/m` | 2,3,4 | 新クエリ、close/reopen、PRAGMA、auto_vacuum移行 |
| `RCMenuManager.m` | 1,3,5 | サムネイルclamp、Panicメニュー、削除強化 |
| `RCPanicEraseService.h/m` | 3 | **新規作成**（書き込み禁止フラグ、キュー排水、設定退避） |
| `RCHotKeyService.h/m` | 3 | Panicホットキー |
| `RCGeneralPreferencesViewController.h/m` | 2 | Auto-Expiry UI のみ |
| `RCGeneralPreferencesView.xib` | 2 | Auto-Expiry UI要素追加 |
| `RCShortcutsPreferencesViewController.h/m` | 3 | Panicホットキー設定（既存Shortcuts画面に統合） |
| `RCShortcutsPreferencesView.xib` | 3 | Panicホットキー設定UI追加 |
| `RCSnippetImportExportService.m` | 4 | XXE対策、件数上限 |
| `RCClipData.m` | 4 | パス検証、os_log |
| `project.yml` | - | **変更不要**（ソースは包括取り込みのため新規.m/.h追加で自動認識） |
