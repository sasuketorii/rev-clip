# ExecPlan: Phase 3 全バグ修正

**ステータス:** READY TO EXECUTE
**作成日:** 2026-02-14
**総バグ:** 91件 (実修正 87 / Informational 4)
**推定変更:** ~1,800-2,200行

---

## 実行フロー

```
Wave 1 ─► Review ─► Commit
  │
  ▼
Wave 2 (5並列) ─► Review ─► Commit (×5)
  │
  ▼
Wave 3 ─► Review ─► Commit
```

---

## Wave 1: Group A — DB + Data Model (17件)

**実行:** 単独 / コーダー×1
**対象ファイル:** `RCDatabaseManager.h/.m`, `RCClipData.h/.m`, `RCClipItem.h/.m`
**コミット:** `fix(db): resolve 17 database integrity and data model issues`
**ゲート:** Wave 2 はこの完了後に開始

### High
- [ ] **G2-001** `RCDatabaseManager.m:860` — PRAGMA foreign_keys を executeStatements: に変更、FMDatabaseQueue 作成直後に1回だけ設定
- [ ] **G2-002** `RCDatabaseManager.m:785-791` — ensureDatabaseReadyForOperation を @synchronized(self) でガード

### Medium
- [ ] **G2-004** `RCDatabaseManager.m:232-250` — updateClipItemUpdateTime に db.changes==0 チェック追加
- [ ] **G2-010** `RCDatabaseManager.m:198-230` — INSERT OR IGNORE に変更、db.changes==0 で重複検出
- [ ] **G2-011** `RCDatabaseManager.m:487-505` — deleteSnippetFolder 前に明示的 DELETE FROM snippets を実行
- [ ] **G1-005** `RCClipData.m:124-141` — 空 buffer で空文字列を返す早期リターン
- [ ] **G1-008** `RCClipData.m:262-265` — saveToPath: のディレクトリ作成エラーを捕捉・ログ
- [ ] **G1-009** `RCClipData.m:184-213` — writeToPasteboard: の writeObjects/setData 併用を検証・修正（NSData は NSPasteboardWriting 非準拠のため統一不可）
- [ ] **G1-010** `RCClipData.m` — dataHash ベースの -isEqual:/-hash を実装
- [ ] **G1-017** `RCClipData.m:93-105` — fileURLs を count>0 の場合のみ代入

### Low
- [ ] **G1-006** `RCClipData.m:310` — CC_SHA256 に NSAssert(data.length <= UINT32_MAX) 追加
- [ ] **G1-007** `RCClipData.m:324` — appendData:toBuffer: に同様の NSAssert 追加
- [ ] **G1-011** `RCClipItem.m` — itemId ベースの -isEqual:/-hash を実装
- [ ] **G2-014** `RCDatabaseManager.m:120-133` — スキーマ作成とバージョンシードを分離
- [ ] **G2-015** `RCDatabaseManager.m:107,365` — intForColumn: → longLongIntForColumn:
- [ ] **G1-015** `RCClipData.m:171` — "(Image)" を NSLocalizedString に変更
- [ ] **G1-016** `RCClipData.m:138` — primaryType 含有をコメントで文書化

**注:** G2-003 (FMDatabaseQueue nesting) は latent bug。コード修正ではなくコメントで文書化。

---

## Wave 2: 5並列実行 (Group B/C/D/E/F)

**前提:** Wave 1 完了済み
**ファイル衝突:** なし（全グループ完全独立）

### Group B — Core Clipboard/Paste/Privacy (16件)

**対象:** `RCClipboardService.h/.m`, `RCPasteService.h/.m`, `RCPrivacyService.h/.m`, `RCDataCleanService.h/.m`
**コミット:** `fix(clipboard): resolve 16 clipboard, paste, and privacy service issues`

#### High
- [ ] **G3-001** `RCClipboardService.m:135-136` — NSPasteboard 読み取りをメインキューに移動
- [ ] **G3-004** `RCPasteService.m:63,190-191` — isPastingInternally (atomic) フラグを RCClipboardService に追加、poller でスキップ

#### Medium
- [ ] **G3-002** `RCClipboardService.m:341,377,406` — dispatch_sync → dispatch_async + completion
- [ ] **G3-003** `RCClipboardService.m:122-130` — 冗長な early excluded app チェックを削除
- [ ] **G3-006** `RCClipboardService.m:427` + `RCDataCleanService.m:119` — ClipboardService のトリミングを削除、DataCleanService に一本化
- [ ] **G3-007** `RCClipboardService.m:33,99,114` — isMonitoring を atomic に変更
- [ ] **G3-009** `RCPrivacyService.m:52-55` — canAccessClipboard: Granted のみ true
- [ ] **G3-011** `RCClipboardService.m:354-356` — CGImageSource でサムネイル生成
- [ ] **G3-013** `RCPasteService.m:40-74` — メインスレッド assertion + dispatch_async fallback

#### Low
- [ ] **G3-005** `RCPasteService.m:111-123` — CGEvent 両方チェック後に post
- [ ] **G3-008** `RCPrivacyService.m:157-167` — switch に default: 追加
- [ ] **G3-010** `RCPrivacyService.m:46-49` — getter から通知ロジックを分離
- [ ] **G3-012** `RCDataCleanService.m:54-86` — 初期 cleanup を @synchronized 内に移動
- [ ] **G3-014** `RCClipboardService.m:226-245` — shouldOverwrite セマンティクスをコメント明確化
- [ ] **G3-015** `RCPrivacyService.m:120` — @available(macOS 16, *) で新形式 URL
- [ ] **G3-016** `RCClipboardService.m:63-65` — dealloc でタイマー invalidate のみ直接実行

---

### Group C — Menu Manager (7件)

**対象:** `RCMenuManager.h/.m`
**コミット:** `fix(menu): resolve 7 menu manager performance and correctness issues`

#### Medium
- [ ] **G2-005** `RCMenuManager.m:310-314` — kRCPrefMaxHistorySizeKey を limit に使用
- [ ] **G2-006** `RCMenuManager.m:108-111` — NSUserDefaultsDidChange にデバウンス(0.3s) 導入
- [ ] **G2-007** `RCMenuManager.m:800-849` — ファイル削除を background queue に移動

#### Low
- [ ] **G2-008** `RCMenuManager.m:836-842` — 個別削除ループを除去、ディレクトリ sweep のみ
- [ ] **G2-009** `RCMenuManager.m:720-722` — [image copy] してからサイズ変更
- [ ] **G2-012** `RCMenuManager.m:195-206` — statusItem nil 時にカーソル位置でメニュー表示
- [ ] **G2-013** `RCMenuManager.m:914-928` — composed range 後に長さ再チェック

---

### Group D — System Services (15件)

**対象:** `RCScreenshotMonitorService.h/.m`, `RCMoveToApplicationsService.m`, `RCSnippetImportExportService.h/.m`, `RCAccessibilityService.m`, `RCHotKeyService.h/.m`, `RCUpdateService.h/.m`, `RCExcludeAppService.m`
**コミット:** `fix(services): resolve 15 system services thread safety and error handling issues`

#### Medium
- [ ] **G4-002** `RCScreenshotMonitorService.m:49,93` — background thread → dispatch_async main
- [ ] **G4-003** `RCScreenshotMonitorService.m:115,138` — metadata query handler をメインに dispatch
- [ ] **G4-004** `RCMoveToApplicationsService.m:132` — waitUntilExit → terminationHandler
- [ ] **G4-007** `RCSnippetImportExportService.m:800` — non-merge で snippets を明示的 DELETE
- [ ] **G4-008** `RCSnippetImportExportService.m:509-521` — 全要素がフォルダ形式かチェック

#### Low
- [ ] **G4-001** `RCHotKeyService.m:50` — strtoull の endptr チェック
- [ ] **G4-005** `RCMoveToApplicationsService.m:80-118` — 移動後に sourcePath を削除
- [ ] **G4-006** `RCMoveToApplicationsService.m:69-78` — パスコンポーネント単位マッチング
- [ ] **G4-009** `RCSnippetImportExportService.m:219-221` — パースエラーを NSError で伝播
- [ ] **G4-010** `RCSnippetImportExportService.m:192` — 50MB ファイルサイズガード追加
- [ ] **G4-011** `RCAccessibilityService.m:54` — @available(macOS 13, *) で新形式 URL
- [ ] **G4-012** `RCAccessibilityService.m:37-39` — TCC 即時再チェック削除
- [ ] **G4-013** `RCExcludeAppService.m:47` — lowercaseString で正規化
- [ ] **G4-014** `RCUpdateService.m:81-88` — @synchronized(self) でラップ
- [ ] **G4-015** `RCHotKeyService.m:484-493` — 冗長な removeAllObjects 削除

---

### Group E — Preferences UI (14件)

**対象:** `RCShortcutsPreferencesViewController.m`, `RCExcludePreferencesViewController.h/.m`, `RCMenuPreferencesViewController.m`, `RCBetaPreferencesView.xib`, `RCBetaPreferencesViewController.h/.m`, `RCPreferencesWindowController.h/.m`, `RCUpdatesPreferencesViewController.m`, `RCGeneralPreferencesViewController.m`
**コミット:** `fix(prefs): resolve 14 preferences UI memory safety and UX issues`

#### Medium
- [ ] **G5-001** `RCShortcutsPreferencesViewController.m:60` — __weak self でリテインサイクル解消
- [ ] **G5-003** `RCExcludePreferencesViewController.m:39-41` — bottom auto layout constraint 追加
- [ ] **G5-004** `RCMenuPreferencesViewController.m:241-331` — dealloc で全 unbind: 呼び出し
- [ ] **G5-006** `RCExcludePreferencesViewController.m:192-216` — 最前面アプリ追跡 or ピッカー方式
- [ ] **G5-010** `RCBetaPreferencesView.xib` — translatesAutoresizingMaskIntoConstraints=NO + auto layout

#### Low
- [ ] **G1-013-E** `RCGeneralPreferencesViewController.m` — loginItem/suppressAlertForLoginItem を kRC プレフィックスに更新 (Group G G1-013 と連動)
- [ ] **G5-002** `RCPreferencesWindowController.m:71` — @available(macOS 14, *) で activate 分岐
- [ ] **G5-005** `RCUpdatesPreferencesViewController.m:101` — runModal → beginSheetModalForWindow:
- [ ] **G5-007** `RCGeneralPreferencesViewController.m:63-69` — NSNotification でステータスアイテム変更通知
- [ ] **G5-008** `RCGeneralPreferencesViewController.m:52-61` — ログインアイテム失敗時にアラート表示
- [ ] **G5-009** `RCUpdatesPreferencesViewController.m:114-141` — タイマーをプロパティ化、重複排除
- [ ] ~~G5-011~~ **Informational** — キャッシュ持続: 対応不要
- [ ] ~~G5-012~~ **Informational** — contentView 置換: 対応不要
- [ ] ~~G1-012~~ **Informational** — NSSecureCoding: 対応不要

---

### Group F — UI Views + Utilities (15件)

**対象:** `RCHotKeyRecorderView.h/.m`, `RCDesignableButton.h/.m`, `RCDesignableView.h/.m`, `RCSnippetEditorWindowController.h/.m`, `NSColor+HexString.h/.m`, `NSImage+Color.h/.m`, `NSImage+Resize.h/.m`
**コミット:** `fix(ui): resolve 15 UI views and utilities correctness issues`

#### High
- [ ] **G6-015** `RCHotKeyRecorderView.m:137` — モディファイアなしショートカットを NSBeep() で拒否

#### Medium
- [ ] **G6-001** `RCHotKeyRecorderView.m:288` — 表示順を Control→Option→Shift→Command に変更
- [ ] **G6-004** `NSImage+Color.m:22` — lockFocus → imageWithSize:flipped:drawingHandler:
- [ ] **G6-010** `NSImage+Resize.m:12` — 同上 + Retina 対応
- [ ] **G6-011** `RCSnippetEditorWindowController.m:838` — runModal → beginSheetModalForWindow:
- [ ] **G6-013** `RCSnippetEditorWindowController.m:936` — outlineView:child:ofItem: に bounds check

#### Low
- [ ] **G6-003** `RCSnippetEditorWindowController.m:1293` — __weak self で flashSaveSuccess 修正
- [ ] **G6-007** `RCDesignableButton.m:59` — NSTrackingAssumeInside 削除
- [ ] **G6-008** `RCDesignableView.h:15` — backgroundColor → viewBackgroundColor (macOS 14+ ランタイム互換)
- [ ] **G6-009** `NSColor+HexString.m:97` — 変換失敗時 nil 返却
- [ ] **G6-014** `RCSnippetEditorWindowController.m:847` — ディレクトリ存在チェック追加
- [ ] ~~G6-017~~ **Informational** — Singleton XIB 依存: 対応不要
- [ ] **G6-018** `RCSnippetEditorWindowController.m:869` — saveButtonClicked 戻り値を BOOL 化
- [ ] **G6-019** `NSColor+HexString.m:33` — 入力長 2未満ガード追加
- [ ] **G6-020** `RCDesignableButton.m:109` — rc_commonInit → viewDidMoveToWindow: に移動

---

## Wave 3: Group G — App Config + Build (7件)

**前提:** Wave 2 完了済み（特に Group E の G1-013-E）
**対象:** `RCEnvironment.h/.m`, `RCAppDelegate.h/.m`, `RCConstants.h/.m`, `RCUtilities.h/.m`, `Info.plist`, `project.yml`
**コミット:** `fix(config): resolve 7 app configuration, environment, and build settings issues`

### High
- [ ] **G1-002** `RCEnvironment.h` + `RCAppDelegate.m` — プロパティを具体型に変更、applicationWillTerminate で nil 化
- [ ] **G1-004** `Info.plist` + `project.yml` — project.yml を 0.0.6/6 に同期

### Medium
- [ ] **G1-001** `RCEnvironment.h:27-37` — 全プロパティを id → 具体クラス型に変更
- [ ] **G1-003** `RCAppDelegate.m:64-71` — excludeAppService/loginItemService を Environment に設定
- [ ] **G1-018** `Info.plist` + `project.yml` — NSAccessibilityUsageDescription 追加

### Low
- [ ] **G1-013** `RCConstants.h/.m` + `RCAppDelegate.m` + `RCUtilities.m` — loginItem → kRCLoginItem リネーム（Group G 管轄ファイルのみ）
- [ ] **G1-014** `RCUtilities.m` — registerDefaultSettings に kRCSuppressAlertForDeleteSnippet: @NO 追加

---

## リスク・注意事項

1. **G1-013 分担**: Group E が `RCGeneralPreferencesViewController.m` を、Group G が `RCConstants.h/.m` 等をリネーム。順序逆転でビルド破壊
2. **G2-001 (FK PRAGMA)**: Wave 1 で確実に修正しないと G2-011, G4-007 の CASCADE が無効
3. **G3-004 (Paste loop)**: isPastingInternally を atomic で宣言。ClipboardService/PasteService 両方変更
4. **G6-008 (backgroundColor)**: macOS 14+ の NSView.backgroundColor とのランタイム衝突回避
5. **各コーダーは自グループ外のファイルを絶対に変更しないこと**
