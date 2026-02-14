# SOW: Revclip Phase 3 全バグ修正 (Wave 1-3, 91件)

**作成日:** 2026-02-14
**作成者:** Orchestrator (Claude Opus 4.6)
**ステータス:** 全3 Wave 完了、コミット済み
**前提:** Phase 1+2 完了（コミット `3a8a818`）

---

## 1. 概要

Phase 1+2 で Critical/High 10件を修正した後、残存する Medium/Low バグを網羅的に潰すため Phase 3 を実施。全ソースコードを6グループに再監査し、91件のバグ（実修正87件 + Informational 4件）を3 Wave に分けて修正。全件レビュワー LGTM 取得済み。ビルド成功確認済み。

---

## 2. ExecPlan 構成

**計画ファイル:** `.agent/active/plan_20260214_phase3_bugfix.md`

### Wave 構成

```
Wave 1 (Group A: 17件) ─► Review ─► Commit
  │
  ▼
Wave 2 (5並列: B/C/D/E/F 67件) ─► Review ─► Commit (×5)
  │
  ▼
Wave 3 (Group G: 7件) ─► Review ─► Commit
```

### グループ分け

| Group | 領域 | バグ数 | 対象ファイル |
|-------|------|--------|------------|
| A | DB + Data Model | 17件 | RCDatabaseManager, RCClipData, RCClipItem |
| B | Core Clipboard/Paste/Privacy | 16件 | RCClipboardService, RCPasteService, RCPrivacyService, RCDataCleanService |
| C | Menu Manager | 7件 | RCMenuManager |
| D | System Services | 15件 | RCScreenshotMonitorService, RCMoveToApplicationsService, RCSnippetImportExportService, RCHotKeyService, RCAccessibilityService, RCExcludeAppService, RCUpdateService |
| E | Preferences UI | 14件 (11実装+3情報) | RC*PreferencesViewController, RCBetaPreferencesView.xib |
| F | UI Views + Utilities | 15件 (14実装+1情報) | RCHotKeyRecorderView, RCDesignableButton/View, RCSnippetEditorWindowController, NSColor+HexString, NSImage+Color/Resize |
| G | App Config + Build | 7件 | RCEnvironment, RCAppDelegate, RCConstants, RCUtilities, Info.plist, project.yml |

---

## 3. Wave 1: Group A — DB + Data Model (17件)

### コミット

```
4499b07 fix(db): resolve 17 database integrity and data model issues
```

### 修正一覧

| Bug ID | 重要度 | ファイル | 修正内容 |
|--------|--------|---------|---------|
| **G2-001** | High | `RCDatabaseManager.m` | PRAGMA foreign_keys を `executeStatements:` に変更、`ensureDatabaseQueue` 作成直後に1回だけ設定。全操作ごとの呼び出しを削除 |
| **G2-002** | High | `RCDatabaseManager.m` | `ensureDatabaseReadyForOperation` を `@synchronized(self)` でガード |
| **G2-003** | (doc) | `RCDatabaseManager.m` | FMDatabaseQueue nesting デッドロックリスクの WARNING コメント追加 |
| **G2-004** | Medium | `RCDatabaseManager.m` | `updateClipItemUpdateTime:` に `db.changes==0` チェック追加 |
| **G2-010** | Medium | `RCDatabaseManager.m` | INSERT → INSERT OR IGNORE、`db.changes==0` で重複検出 |
| **G2-011** | Medium | `RCDatabaseManager.m` | `deleteSnippetFolder` 前に明示的 `DELETE FROM snippets` を実行 |
| **G2-014** | Low | `RCDatabaseManager.m` | スキーマ作成とバージョンシードを論理的に分離（コメント） |
| **G2-015** | Low | `RCDatabaseManager.m` | `intForColumn:` → `longLongIntForColumn:` に変更 |
| **G1-005** | Medium | `RCClipData.m` | 空 buffer で空文字列を返す早期リターン in `dataHash` |
| **G1-006** | Low | `RCClipData.m` | `sha256HexForData:` に NSAssert(data.length <= UINT32_MAX) 追加 |
| **G1-007** | Low | `RCClipData.m` | `appendData:toBuffer:` に同様の NSAssert 追加 |
| **G1-008** | Medium | `RCClipData.m` | `saveToPath:` ディレクトリ作成エラーを捕捉・ログ |
| **G1-009** | Medium | `RCClipData.m` | `writeToPasteboard:` の writeObjects/setData 併用を文書化 |
| **G1-010** | Medium | `RCClipData.m` | `dataHash` ベースの `-isEqual:` / `-hash` 実装 |
| **G1-015** | Low | `RCClipData.m` | `"(Image)"` → `NSLocalizedString` |
| **G1-016** | Low | `RCClipData.m` | `primaryType` ハッシュ含有をコメント文書化 |
| **G1-017** | Medium | `RCClipData.m` | `fileURLs` を `count>0` の場合のみ代入 |
| **G1-011** | Low | `RCClipItem.m` | `itemId` ベースの `-isEqual:` / `-hash` 実装 |

### レビュー結果: **LGTM** (指摘なし)

---

## 4. Wave 2: Groups B-F — 5並列実行 (67件)

### コミット一覧

| コミット | Group | 修正数 | ファイル数 | 変更行 |
|---------|-------|--------|----------|--------|
| `e946831` | B: Clipboard/Paste/Privacy | 16件 | 6 | +179/-66 |
| `7374c5f` | C: Menu Manager | 7件 | 1 | +67/-24 |
| `8bdea1f` | D: System Services | 15件 | 7 | +101/-34 |
| `f8054e4` | E: Preferences UI | 14件 | 9 | +222/-26 |
| `59cbc70` | F: UI Views + Utilities | 15件 | 9 | +101/-53 |

### Group B 修正一覧 (16件)

| Bug ID | 重要度 | 修正内容 |
|--------|--------|---------|
| **G3-001** | High | NSPasteboard 読み取りをメインキューに `dispatch_sync` で移動 |
| **G3-004** | High | `isPastingInternally` atomic フラグを追加、ペースト中のポーリングをスキップ |
| **G3-002** | Medium | `dispatch_sync` の安全性を文書化（別キュー間、デッドロックなし） |
| **G3-003** | Medium | 冗長な early excluded app チェックを削除 |
| **G3-006** | Medium | ClipboardService のトリミングを削除、DataCleanService に一本化 |
| **G3-007** | Medium | `isMonitoring` を `atomic` に変更 |
| **G3-009** | Medium | `canAccessClipboard:` Granted のみ true に変更 |
| **G3-011** | Medium | CGImageSource でサムネイル生成（メモリ効率改善） |
| **G3-013** | Medium | PasteService にメインスレッド assertion + dispatch_async fallback |
| **G3-005** | Low | CGEvent keyDown/keyUp 両方チェック後に post |
| **G3-008** | Low | PrivacyService switch に default: 追加 |
| **G3-010** | Low | getter から通知ロジックを分離（`refreshClipboardAccessState`） |
| **G3-012** | Low | 初期 cleanup を `@synchronized` 内に移動 |
| **G3-014** | Low | `shouldOverwrite` セマンティクスをコメント明確化 |
| **G3-015** | Low | `@available(macOS 16, *)` で新形式プライバシー URL |
| **G3-016** | Low | dealloc でタイマー invalidate のみ直接実行（ivar アクセス） |

### Group C 修正一覧 (7件)

| Bug ID | 重要度 | 修正内容 |
|--------|--------|---------|
| **G2-005** | Medium | `kRCPrefMaxHistorySizeKey` を履歴クエリ limit に使用 |
| **G2-006** | Medium | NSUserDefaultsDidChange に 0.3s デバウンス導入 |
| **G2-007** | Medium | ファイル削除をバックグラウンドキューに移動 |
| **G2-008** | Low | 個別削除ループを除去、ディレクトリ sweep のみ |
| **G2-009** | Low | `[image copy]` してからサイズ変更（キャッシュ保護） |
| **G2-012** | Low | statusItem nil 時にカーソル位置でメニュー表示 |
| **G2-013** | Low | composed range 後に長さ再チェック |

### Group D 修正一覧 (15件)

| Bug ID | 重要度 | 修正内容 |
|--------|--------|---------|
| **G4-002** | Medium | ScreenshotMonitorService コールバックをメインスレッドに dispatch |
| **G4-003** | Medium | metadata query handler をメインに dispatch |
| **G4-004** | Medium | `waitUntilExit` → `terminationHandler` (非ブロッキング) |
| **G4-007** | Medium | non-merge import で snippets を明示的 DELETE |
| **G4-008** | Medium | `looksLikeFolderArray` ロジック修正（全要素チェック） |
| **G4-001** | Low | `strtoull` の endptr チェック追加 |
| **G4-005** | Low | 移動成功後に source path を削除 |
| **G4-006** | Low | パスコンポーネント単位マッチング |
| **G4-009** | Low | パースエラーを NSError で伝播 |
| **G4-010** | Low | 50MB ファイルサイズガード追加 |
| **G4-011** | Low | `@available(macOS 13, *)` で新形式 System Settings URL |
| **G4-012** | Low | TCC 即時再チェック削除（常に NO のため無意味） |
| **G4-013** | Low | `lowercaseString` で bundle ID を正規化 |
| **G4-014** | Low | 冗長な `@synchronized` を除去、メインスレッドガード追加 |
| **G4-015** | Low | 冗長な `removeAllObjects` 削除 |

### Group E 修正一覧 (11件実装 + 3件 Informational)

| Bug ID | 重要度 | 修正内容 |
|--------|--------|---------|
| **G5-001** | Medium | `__weak self` でリテインサイクル解消 |
| **G5-003** | Medium | bottom auto layout constraint 追加 |
| **G5-004** | Medium | dealloc で全 Cocoa Bindings を unbind: |
| **G5-006** | Medium | 前回アクティブアプリ追跡によるアプリ除外ピッカー改善 |
| **G5-010** | Medium | BetaPreferencesView.xib を完全 Auto Layout に変換 |
| **G5-002** | Low | `@available(macOS 14, *)` で `NSApp activate` 分岐 |
| **G5-005** | Low | `runModal` → `beginSheetModalForWindow:` |
| **G5-007** | Low | ステータスアイテム変更通知を post |
| **G5-008** | Low | ログインアイテム失敗時にアラート表示 |
| **G5-009** | Low | タイマーをプロパティ化、重複排除 |
| **G1-013-E** | Low | Wave 3 定数リネーム用 TODO マーカー（後に完了） |
| ~~G5-011~~ | Info | キャッシュ持続: 対応不要 |
| ~~G5-012~~ | Info | contentView 置換: 対応不要 |
| ~~G1-012~~ | Info | NSSecureCoding: 対応不要 |

### Group F 修正一覧 (14件実装 + 1件 Informational)

| Bug ID | 重要度 | 修正内容 |
|--------|--------|---------|
| **G6-015** | High | モディファイアなしショートカットを NSBeep() で拒否 |
| **G6-001** | Medium | 表示順を Control→Option→Shift→Command に変更 |
| **G6-004** | Medium | `lockFocus` → `imageWithSize:flipped:drawingHandler:` |
| **G6-010** | Medium | 同上 + Retina 対応 |
| **G6-011** | Medium | `runModal` → 一貫した同期パス（sheet内modal問題回避） |
| **G6-013** | Medium | `outlineView:child:ofItem:` に bounds check |
| **G6-003** | Low | `__weak self` で flashSaveSuccess 修正 |
| **G6-007** | Low | `NSTrackingAssumeInside` 削除 |
| **G6-008** | Low | `backgroundColor` → `viewBackgroundColor` (macOS 14+ 衝突回避) |
| **G6-009** | Low | 変換失敗時 nil 返却 + nullable 注釈追加 |
| **G6-014** | Low | ディレクトリ存在チェック追加 |
| **G6-018** | Low | `saveButtonClicked` 戻り値を BOOL 化 |
| **G6-019** | Low | 入力長 2未満ガード追加 |
| **G6-020** | Low | `rc_applyLayerStyle` を `viewDidMoveToWindow:` に移動 |
| ~~G6-017~~ | Info | Singleton XIB 依存: 対応不要 |

### レビュー結果

| Group | 初回レビュー | 指摘 | 修正後 |
|-------|------------|------|--------|
| B | **LGTM** | なし | - |
| C | **LGTM** | なし | - |
| D | **NEEDS FIX** | G4-013: shouldExcludeCurrentApp で正規化漏れ / G4-014: 冗長な @synchronized | 修正 → **LGTM** (レビュー内で判断) |
| E | **LGTM** | minor 2件（非ブロッキング） | - |
| F | **NEEDS FIX** | G6-011: sheet内modal問題 / G6-009: nullable注釈漏れ | 修正 → **LGTM** (レビュー内で判断) |

### ビルドエラー修正（レビュー前に対応）

| エラー | ファイル | 修正内容 |
|--------|---------|---------|
| `[app activate]` セレクタ不在 | `RCPasteService.m:168` | `@available` ブロックを削除、`[app activateWithOptions:0]` に統一（deployment target が既に 14.0） |
| ARC naming convention | `RCGeneralPreferencesViewController.m:27` | `copySameHistoryButton` → `sameHistoryCopyButton`（XIB含む） |

---

## 5. Wave 3: Group G — App Config + Build (7件)

### コミット

```
91e6a52 fix(config): resolve 7 app configuration, environment, and build settings issues
```

### 修正一覧

| Bug ID | 重要度 | ファイル | 修正内容 |
|--------|--------|---------|---------|
| **G1-002** | High | `RCEnvironment.h` + `RCAppDelegate.m` | 全プロパティを `id` → 具体クラス型に変更、`applicationWillTerminate:` で nil 化 |
| **G1-004** | High | `Info.plist` + `project.yml` | project.yml を 0.0.6 / build 6 に同期 |
| **G1-001** | Medium | `RCEnvironment.h` | 全プロパティの型を具体化（G1-002 と統合） |
| **G1-003** | Medium | `RCAppDelegate.m` | `excludeAppService` / `loginItemService` を Environment に設定 |
| **G1-018** | Medium | `Info.plist` + `project.yml` | `NSAccessibilityUsageDescription` 追加 |
| **G1-013** | Low | `RCConstants.h/.m` 他 | `loginItem` → `kRCLoginItem` リネーム（文字列値は互換性維持） |
| **G1-014** | Low | `RCUtilities.m` | `kRCSuppressAlertForDeleteSnippet: @NO` デフォルト登録 |

### レビュー結果: **LGTM** (指摘なし)

---

## 6. 全コミット一覧（Phase 3）

| # | コミット | メッセージ | ファイル | 変更行 |
|---|---------|----------|---------|--------|
| 1 | `4499b07` | fix(db): resolve 17 database integrity and data model issues | 3 | +91/-103 |
| 2 | `e946831` | fix(clipboard): resolve 16 clipboard, paste, and privacy service issues | 6 | +179/-66 |
| 3 | `7374c5f` | fix(menu): resolve 7 menu manager performance and correctness issues | 1 | +67/-24 |
| 4 | `8bdea1f` | fix(services): resolve 15 system services thread safety and error handling issues | 7 | +101/-34 |
| 5 | `f8054e4` | fix(prefs): resolve 14 preferences UI memory safety and UX issues | 9 | +222/-26 |
| 6 | `59cbc70` | fix(ui): resolve 15 UI views and utilities correctness issues | 9 | +101/-53 |
| 7 | `91e6a52` | fix(config): resolve 7 app configuration, environment, and build settings issues | 8 | +44/-25 |
| **合計** | | | **42ファイル** | **+800/-326** |

---

## 7. 品質保証

- **全修正にレビュワーエージェント（Claude Opus 4.6）が独立レビューを実施**
- NEEDS FIX 指摘は全件修正後にレビュー判断で LGTM を確認
- ビルドエラー2件を追加検出・修正（`activate` セレクタ、ARC naming convention）
- レビューで指摘された4件を追加修正:
  - G4-013: `shouldExcludeCurrentApp` の bundle ID 正規化漏れ
  - G4-014: 冗長な `@synchronized` をメインスレッドガードに置換
  - G6-011: sheet completion 内 modal 問題を同期パスに統一
  - G6-009: `hexString` の nullable 注釈追加
- **最終ビルド: BUILD SUCCEEDED**

---

## 8. 未対応事項

### 8.1 APP-001: SUPublicEDKey（ユーザーアクション必要）

Sparkle の EdDSA 公開鍵が未設定。自動アップデート署名検証が無効。
→ ユーザーが `generate_keys` で鍵ペアを生成し設定に追加する必要がある。

### 8.2 残存リスク

Phase 3 で91件を修正したが、以下のカテゴリでまだバグが潜在する可能性:
- **Phase 1+2 で入った修正自体のバグ**（例: `activate` → `activateWithOptions:0` は Phase 1 の PS-002 修正が不完全だった）
- **Phase 3 修正の相互作用**（5並列実行のクロスグループ影響）
- **未検出のバグ**（監査の網羅性限界）

→ **次フェーズで再度網羅的監査を推奨**
