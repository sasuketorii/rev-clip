# SOW: Revclip バグ監査 & 修正 (Phase 1 + Phase 2)

**作成日:** 2026-02-14
**作成者:** Orchestrator (Claude Opus)
**ステータス:** Phase 1 + Phase 2 完了、未コミット

---

## 1. 概要

Revclip（macOS クリップボードマネージャー）の全ソースコードを8領域に分割して並列監査し、発見されたバグを優先度順に修正。Phase 1 で Critical/High 上位6件、Phase 2 で High 2件を修正し、全件レビュワーの LGTM を取得済み。

---

## 2. 監査対象・手法

### 2.1 監査対象領域（8並列）

| # | 領域 | 主要ファイル |
|---|------|------------|
| 1 | Clipboard History | RCClipboardService, RCClipData, RCClipItem |
| 2 | Snippet Editor | RCSnippetEditorWindowController |
| 3 | Import/Export | RCSnippetImportExportService |
| 4 | Menu System | RCMenuManager |
| 5 | HotKey System | RCHotKeyService, RCHotKeyRecorderView |
| 6 | Paste Service | RCPasteService |
| 7 | Preferences/Updates | RC*PreferencesViewController, RCUpdateService |
| 8 | App Lifecycle | RCAppDelegate, RCScreenshotMonitorService, RCLoginItemService |

### 2.2 監査手法

- 各領域ごとに独立したサブエージェント（Claude Opus）が全ファイルを通読
- Critical / High / Medium / Low の4段階で分類
- 合計約120件のバグを検出

---

## 3. Phase 1: Critical + High 上位修正（6件）

### 3.1 修正一覧

| Bug ID | 重要度 | ファイル | 問題 | 修正内容 |
|--------|--------|---------|------|---------|
| **PS-001** | Critical | `RCPasteService.m` | `frontmostApplication` が Revclip 自身を返す → 自分自身にペーストキーストロークを送信 | `bundleIdentifier` を比較して自己検出ガードを3箇所に追加 |
| **PS-002** | Critical | `RCPasteService.m` | macOS 14 で `activateWithOptions:0` が deprecated → コンパイル警告 + 将来の動作不安定 | `@available(macOS 14.0, *)` 分岐で `activate` / `activateWithOptions:` を使い分け |
| **PS-003** | High | `RCPasteService.m` | アプリ activation 完了前にペーストキーストローク送信 → ペーストが空振り | activation 後に 50ms の `dispatch_after` を追加、アプリが nil/terminated の場合の分岐も追加 |
| **PF-001** | High | `RCGeneralPreferencesViewController.m` | IBOutlet 名 `duplicateSameHistoryButton` が XIB の `copySameHistoryButton` と不一致 → `NSUnknownKeyException` クラッシュ | プロパティ名を `copySameHistoryButton` に修正（3箇所） |
| **HK-004** | High | `RCSnippetEditorWindowController.m` | `toggleSelectedItemEnabled:` 後に `reloadFolderHotKeys` 未呼び出し → フォルダホットキーの有効/無効が即座に反映されない | `reloadFolderHotKeys` 呼び出しを追加 |
| **AL-001** | High | `RCScreenshotMonitorService.m/.h` | UserDefaults キー `RCBetaScreenshotMonitoring` と定数 `kRCBetaObserveScreenshot` が不一致 → スクリーンショット監視が常に無効 | ローカル定数を削除し、`RCConstants.h` の `kRCBetaObserveScreenshot` を使用。ヘッダーコメントも更新 |

### 3.2 追加改善（Phase 1 で同時実施）

| ファイル | 改善内容 |
|---------|---------|
| `RCDatabaseManager.m` | `updateSnippetFolder` / `updateSnippet` で `db.changes == 0` チェック追加 → 更新対象なしを検出 |
| `RCSnippetEditorWindowController.m` | `contentTextView.allowsUndo = YES` でUndo対応、`flashSaveSuccess` で保存成功フィードバック、失敗時 `NSBeep()` |
| `RCUpdateService.m/.h` | `didAttemptSetup` フラグ削除（再試行可能に）、`canCheckForUpdates` プロパティ追加、ログ出力追加 |
| `RCUpdatesPreferencesViewController.m` | `RCUpdateService` 経由で設定読み書き（UserDefaults直接アクセス廃止）、チェックボタンの無効化 + スピナー表示 |
| `RCUpdatesPreferencesView.xib` | `checkNowButton` / `checkProgressIndicator` アウトレット追加 |
| `Info.plist` | 空の `SUPublicEDKey` エントリ削除 |
| `project.yml` | 空の `SUPublicEDKey` エントリ削除 |

### 3.3 レビュー結果

| グループ | 初回レビュー | 指摘 | 再レビュー |
|---------|------------|------|----------|
| A (PasteService) | LGTM | - | - |
| B (Preferences) | LGTM | - | - |
| C (HotKey reload) | LGTM | - | - |
| D (Screenshot key) | NEEDS_FIX | ヘッダーコメントに旧定数名残存 | LGTM |

---

## 4. Phase 2: 残り High 修正（2件 + 1件ユーザーアクション）

### 4.1 再監査

Phase 1 完了後、3並列で再監査を実施:
- Core Services（9ファイル）→ HIGH 0件
- UI/Managers（6ファイル）→ HIGH 1件（UI-001）
- Preferences/App（13ファイル）→ HIGH 2件（APP-001, APP-002）

### 4.2 修正一覧

| Bug ID | 重要度 | ファイル | 問題 | 修正内容 |
|--------|--------|---------|------|---------|
| **UI-001** | High | `RCClipData.m` | `dataHash` が `stringValue` 非 nil 時に早期リターン → RTF/TIFF 等のリッチデータを無視してハッシュ衝突 → サイレントデータ消失 | 早期リターンを削除し、全データフィールド（stringValue, RTFData, RTFDData, PDFData, TIFFData, fileNames, fileURLs, URLString, primaryType）の複合バッファからハッシュを計算 |
| **APP-002** | High | `RCScreenshotMonitorService.m` | スクリーンショット検出時に `[pasteboard clearContents]` でユーザーのクリップボード内容を無断上書き → データ消失 | クリップボード上書きを完全廃止。代わりにクリップ履歴DB（`RCDatabaseManager`）に直接保存し、`RCClipboardDidChangeNotification` で UI 更新。サムネイル生成も同梱 |
| **APP-001** | High | `Info.plist` / `project.yml` | `SUPublicEDKey`（Sparkle EdDSA 公開鍵）が空/削除 → 自動アップデート署名検証無効 | **ユーザーアクション必要**: Sparkle `generate_keys` で鍵ペア生成し、公開鍵を設定に追加 |

### 4.3 レビュー結果

| Bug ID | 初回レビュー | 指摘 | 再レビュー |
|--------|------------|------|----------|
| UI-001 | LGTM | - | - |
| APP-002 | NEEDS_FIX | (1) `object:nil` → `object:self`（MEDIUM）、(2) サムネイルサイズハードコード → UserDefaults 参照（LOW） | LGTM |

---

## 5. 変更ファイル一覧（全13ファイル、286行追加 / 43行削除）

| ファイル | 追加 | 削除 | Phase | 変更概要 |
|---------|------|------|-------|---------|
| `RCPasteService.m` | 21 | 2 | 1 | 自己検出ガード、deprecated API 対応、activation 遅延 |
| `RCGeneralPreferencesViewController.m` | 3 | 3 | 1 | IBOutlet 名修正 |
| `RCSnippetEditorWindowController.m` | 20 | 0 | 1 | Undo対応、保存フィードバック、hotkey reload |
| `RCScreenshotMonitorService.h` | 1 | 1 | 1+2 | コメント更新 |
| `RCScreenshotMonitorService.m` | 137 | 11 | 1+2 | キー不一致修正 + クリップ履歴直接保存 |
| `RCDatabaseManager.m` | 6 | 0 | 1 | 更新対象なし検出 |
| `RCUpdateService.h` | 3 | 0 | 1 | `canCheckForUpdates` プロパティ |
| `RCUpdateService.m` | 27 | 3 | 1 | `didAttemptSetup` 削除、再試行可能化、ログ |
| `RCUpdatesPreferencesViewController.m` | 56 | 14 | 1 | UpdateService 経由設定、スピナー |
| `RCUpdatesPreferencesView.xib` | 10 | 0 | 1 | スピナー + アウトレット |
| `RCClipData.m` | 2 | 6 | 2 | 複合ハッシュ |
| `Info.plist` | 0 | 2 | 1 | 空 `SUPublicEDKey` 削除 |
| `project.yml` | 0 | 1 | 1 | 空 `SUPublicEDKey` 削除 |

---

## 6. 未対応事項

### 6.1 APP-001: SUPublicEDKey（ユーザーアクション必要）

```bash
# 鍵生成
./src/Revclip/Revclip/Vendor/Sparkle/Sparkle.framework/Resources/generate_keys

# 出力された公開鍵を以下に設定:
# - project.yml の SUPublicEDKey
# - Info.plist の SUPublicEDKey
# リリース時に秘密鍵でアーカイブ署名
```

### 6.2 残バグ（Medium/Low）

Phase 1+2 で Critical 2件 + High 8件を処理。残りは Medium ~41件、Low ~58件（初回監査時の概算）。次フェーズで対応予定。

---

## 7. 品質保証

- 全修正に対してレビュワーエージェント（Claude Opus）が独立レビューを実施
- NEEDS_FIX の指摘は全件修正後に再レビューで LGTM を取得
- 変更は全て未コミット状態（ユーザー確認待ち）
