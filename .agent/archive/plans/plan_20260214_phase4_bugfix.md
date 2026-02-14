# ExecPlan: Phase 4 Bug Audit Fix

**作成日:** 2026-02-14
**Phase**: 4
**監査結果:** 83件 (8グループ中7グループ完了)

---

## トリアージ結果

### 除外項目（コード修正不要/インフラ/新機能）

| Bug ID | 理由 |
|--------|------|
| P4-500 | SUPublicEDKey はユーザーが鍵生成する必要あり (APP-001) |
| P4-501 | appcast署名はCI/CDリリース工程の問題 |
| P4-502 | appcast.xmlの内容はGitHub Releases管理 |
| P4-507 | コード署名設定は開発者環境依存 |
| P4-202 | HTML保存対応は新機能 |
| P4-309 | ポーリング間隔変更は設計変更 |
| P4-308 | DataCleanパフォーマンス最適化 |
| P4-609 | コンテキストメニューは新機能 |
| P4-516 | 権限昇格は新機能 |
| P4-703 | Beta機能未実装 → UIを無効化するだけで対応 |
| P4-604 | COUNT最適化はLow優先度 |

### 修正対象: 72件

---

## Wave 構成

### Wave 1: Core Safety (Critical + High) — 5並列

#### Group A: Clipboard + Paste 安全性 (5件)
- **P4-300** Critical: Concealed/Transient clipboard保存防止
- **P4-301** High: isPastingInternally タイマー競合
- **P4-302** High: changeCount + データ取得の原子性
- **P4-303** High: 除外アプリ判定タイミング
- **P4-306** Medium: stopMonitoring後のイベント抑止

対象ファイル: `RCClipboardService.m`, `RCPasteService.m`

#### Group B: Privacy + Exclude 修正 (6件)
- **P4-400** High: Privacy API OS判定修正 (macOS 15.4)
- **P4-401** High: Privacy状態更新の配線
- **P4-402** Medium: Privacyメインスレッド保証
- **P4-405** High: 除外判定をコピー時点に固定
- **P4-406** High: Bundle ID欠落時のフォールバック
- **P4-403** Medium: Accessibility alertメインスレッド保証

対象ファイル: `RCPrivacyService.m`, `RCExcludeAppService.m`, `RCAccessibilityService.m`

#### Group C: HotKey + Update Service (8件)
- **P4-503** High: SPUUpdaterDelegate実装
- **P4-504** High: 更新失敗のUI伝播
- **P4-505** Medium: canCheckForUpdates楽観フォールバック修正
- **P4-508** High: ホットキー競合検出・通知
- **P4-509** High: フォルダホットキー保存順序修正
- **P4-510** High: 重複ホットキー検証
- **P4-506** Medium: Sparkle欠落時の明示警告
- **P4-514** Medium: スクリーンショット設定即時反映

対象ファイル: `RCUpdateService.m`, `RCHotKeyService.m`, `RCScreenshotMonitorService.m`

#### Group D: Menu Manager + DB (6件)
- **P4-600** High: Clear History非同期競合修正
- **P4-602** High: メニュー構築のI/O分離
- **P4-200** High: スニペットフォルダ削除のトランザクション化
- **P4-601** Medium: Clear History削除対象フィルタ
- **P4-603** Medium: サムネイルキャッシュ導入
- **P4-605** Medium: 合成文字切り詰め修正

対象ファイル: `RCMenuManager.m`, `RCDatabaseManager.m`

#### Group E: Preferences + UI 修正 (8件)
- **P4-700** High: 履歴上限即時反映
- **P4-702** High: スクリーンショット設定即時反映
- **P4-800** High: 無効フォルダのホットキー登録防止
- **P4-801** High: performKeyEquivalent記録中横取り防止
- **P4-802** High: リサイズ画像のソース参照解放
- **P4-704** Medium: ショートカット登録失敗のUI返却
- **P4-701** Medium: ログイン起動トグルの実状態反映
- **P4-805** Medium: 保存失敗時のUIモデル整合性

対象ファイル: `RCGeneralPreferencesViewController.m`, `RCBetaPreferencesViewController.m`, `RCSnippetEditorWindowController.m`, `RCHotKeyRecorderView.m`, `NSImage+Resize.m`

### Wave 2: Medium Priority — 3並列

#### Group F: Services 改善 (8件)
- **P4-511** High: スクリーンショット取り込みバックグラウンド化
- **P4-515** High: MoveToApps ダウングレード防止
- **P4-520** High: スニペットマージ identifier優先化
- **P4-512** Medium: NSMetadataQueryスコープ限定
- **P4-513** Medium: スクリーンショット対応拡張子追加
- **P4-517** Medium: MoveToApps動的パス生成
- **P4-518** Medium: LoginItem status enum化
- **P4-519** Medium: LoginItemエラー伝播

対象ファイル: `RCScreenshotMonitorService.m`, `RCMoveToApplicationsService.m`, `RCSnippetImportExportService.m`, `RCLoginItemService.m`

#### Group G: Data + Pasteboard 改善 (7件)
- **P4-201** Medium: ハッシュ生成ストリーミング化
- **P4-203** Medium: ClipItem等価性の未永続対応
- **P4-204** Medium: 未来スキーマバージョン検知
- **P4-208** Medium: Pasteboard書き込み失敗検知
- **P4-304** Medium: アプリ再アクティブ化待ち改善
- **P4-305** Medium: NSPasteboard非メインアクセス残存修正
- **P4-307** Medium: DataCleanパス検証追加

対象ファイル: `RCClipData.m`, `RCClipItem.m`, `RCDatabaseManager.m`, `RCPasteService.m`, `RCDataCleanService.m`

#### Group H: UI + Utilities 改善 (10件)
- **P4-803** Medium: Delete記録の修飾キー判定
- **P4-804** Medium: Option-only制限のOS判定
- **P4-806** Medium: ダークモードボタン色追従
- **P4-807** Medium: ダークモードビュー色追従
- **P4-808** Medium: Snippet N+1クエリ解消
- **P4-809** Medium: フォルダホットキー値検証強化
- **P4-608** Medium: クリップファイル欠損時のDB整合回復
- **P4-607** Medium: スニペット本文の遅延読込
- **P4-705** Medium: ホットキークリア機能修正
- **P4-703** High: Beta設定UIの無効化表示

対象ファイル: `RCHotKeyRecorderView.m`, `RCDesignableButton.m`, `RCDesignableView.m`, `RCSnippetEditorWindowController.m`, `RCMenuManager.m`, `RCShortcutsPreferencesViewController.m`, `RCBetaPreferencesViewController.m`

### Wave 3: Low Priority (9件) — 1グループ

#### Group I: Low fixes
- **P4-205** Low: 重複インデックス削除
- **P4-206** Low: clipDataFromPath nullability修正
- **P4-207** Low: clipItemWithDataHash nullability修正
- **P4-209** Low: INSERT OR IGNORE改善
- **P4-310** Medium: ペーストコマンド無効時の監視抑止修正
- **P4-404** Medium: Accessibility URL段階フォールバック
- **P4-407** Low: NSUserDefaults自己修復
- **P4-521** Medium: importSnippetsFromDataサイズ制限
- **P4-523** Medium: フォーマット/バージョン検証
- **P4-810** Low: 削除後order永続化失敗のエラーハンドリング

対象ファイル: 各種

---

## 実行フロー

```
Wave 1 (5並列: A/B/C/D/E) → Review → Fix → LGTM
    ↓
Wave 2 (3並列: F/G/H) → Review → Fix → LGTM
    ↓
Wave 3 (1グループ: I) → Review → Fix → LGTM
    ↓
ビルド確認 → コミット
```
