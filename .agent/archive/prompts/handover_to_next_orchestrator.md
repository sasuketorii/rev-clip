# ハンドオーバー: 次期オーケストレーターへの引継ぎ

**作成日:** 2026-02-14
**作成者:** Orchestrator (Claude Opus)
**対象:** 次期オーケストレーター（コンテキスト共有なし）

---

## 0. あなたの役割

あなたは **オーケストレーター** です。自分ではコードの編集・実装・レビューを行いません。
全ての実作業はサブエージェント（Task ツール）に委譲してください。
詳細は `CLAUDE.md` の「Orchestrator Hard Rules」セクションを参照。

---

## 1. プロジェクト概要

### 1.1 Revclip とは

**Revclip** は macOS 用のクリップボードマネージャーアプリケーション（Objective-C / Cocoa）です。

- **リポジトリ:** `/Users/sasuketorii/dev/Revclip`
- **ソースコード:** `src/Revclip/Revclip/` 配下
- **ブランチ:** `master`（メインブランチ）
- **現バージョン:** v0.0.6

### 1.2 主要機能

- クリップボード履歴の自動保存・メニュー表示
- スニペット（定型文）管理・フォルダ分類
- グローバルホットキー（メニュー表示、フォルダ直接呼び出し）
- スクリーンショット自動取り込み（ベータ機能）
- Sparkle 経由の自動アップデート
- アプリ除外設定、データクリーンアップ

### 1.3 ディレクトリ構成（重要）

```
/Users/sasuketorii/dev/Revclip/
├── CLAUDE.md                    # エージェント設定（必読）
├── .agent_rules/RULES.md        # 共通ルール（必読）
├── .agent/
│   ├── PROJECT_CONTEXT.md       # プロジェクトコンテキスト
│   ├── requirements.md          # 要件定義（テンプレ状態）
│   ├── active/
│   │   ├── sow/                 # SOW（作業明細）
│   │   │   └── 20260214_bugfix_audit_phase1_phase2.md  # ← 今回のSOW
│   │   └── prompts/             # ハンドオーバー・依頼プロンプト
│   │       └── handover_to_next_orchestrator.md  # ← このファイル
│   └── archive/                 # 完了した作業
├── src/Revclip/Revclip/         # アプリケーションソースコード
│   ├── App/                     # AppDelegate, Constants, Environment
│   ├── Managers/                # DatabaseManager, MenuManager
│   ├── Models/                  # ClipData, ClipItem
│   ├── Services/                # ClipboardService, PasteService, HotKeyService, etc.
│   ├── UI/                      # Preferences, SnippetEditor, Views
│   ├── Utilities/               # NSColor+HexString, NSImage+Resize, RCUtilities
│   └── Vendor/                  # FMDB, Sparkle.framework
└── src/Revclip/project.yml      # XcodeGen プロジェクト定義
```

---

## 2. 現在の状態

### 2.1 完了した作業

**バグ監査 & 修正 Phase 1 + Phase 2** が完了しています。

全ソースコードを8領域に分割して並列監査し、Critical/High バグを修正。全件レビュワー LGTM 取得済み。

#### Phase 1 修正済み（6件）

| Bug ID | ファイル | 修正内容 |
|--------|---------|---------|
| PS-001 | `Services/RCPasteService.m` | frontmostApplication が自分自身を返す場合の自己検出ガード（3箇所） |
| PS-002 | `Services/RCPasteService.m` | macOS 14 deprecated API `activateWithOptions:0` → `@available` 分岐 |
| PS-003 | `Services/RCPasteService.m` | activation 完了前のペースト空振り → 50ms 遅延追加 |
| PF-001 | `UI/Preferences/RCGeneralPreferencesViewController.m` | IBOutlet 名 `duplicateSameHistoryButton` → `copySameHistoryButton` |
| HK-004 | `UI/SnippetEditor/RCSnippetEditorWindowController.m` | `toggleSelectedItemEnabled:` に `reloadFolderHotKeys` 追加 |
| AL-001 | `Services/RCScreenshotMonitorService.m/.h` | UserDefaults キー不一致修正 |

#### Phase 1 追加改善

| ファイル | 改善 |
|---------|------|
| `Managers/RCDatabaseManager.m` | `db.changes == 0` チェック追加 |
| `UI/SnippetEditor/RCSnippetEditorWindowController.m` | Undo対応、保存フィードバック |
| `Services/RCUpdateService.h/.m` | `canCheckForUpdates` 追加、再試行可能化 |
| `UI/Preferences/RCUpdatesPreferencesViewController.m` | UpdateService 経由設定、スピナー |
| `UI/Preferences/RCUpdatesPreferencesView.xib` | スピナーUI追加 |
| `Info.plist` / `project.yml` | 空 `SUPublicEDKey` 削除 |

#### Phase 2 修正済み（2件）

| Bug ID | ファイル | 修正内容 |
|--------|---------|---------|
| UI-001 | `Models/RCClipData.m` | `dataHash` の早期リターンを削除 → 全データフィールドの複合ハッシュに変更（サイレントデータ消失を解消） |
| APP-002 | `Services/RCScreenshotMonitorService.m` | クリップボード上書きを廃止 → クリップ履歴DBに直接保存する方式に全面書き換え |

### 2.2 未コミット変更

**全ての変更は未コミットです。** 13ファイル、286行追加 / 43行削除。

```bash
# 変更確認コマンド
cd /Users/sasuketorii/dev/Revclip
git diff --stat
git diff  # 全差分
```

### 2.3 未対応事項

#### APP-001: SUPublicEDKey（ユーザーアクション必要 / コード修正不可）

Sparkle の EdDSA 公開鍵が空/削除されている。自動アップデートの署名検証が無効。
→ ユーザーが `Sparkle.framework/Resources/generate_keys` で鍵ペアを生成し、`project.yml` と `Info.plist` に公開鍵を設定する必要がある。コード修正では対応不可。

#### 残バグ（Medium / Low）

初回監査で約120件検出。Phase 1+2 で Critical 2件 + High 8件を処理。
残りは **Medium 約41件、Low 約58件**（概算値。初回監査のコンテキストは消失済み）。

**重要:** 残りの Medium/Low バグの詳細リストは、初回監査時のコンテキスト圧縮により消失しています。次フェーズで対応する場合は**再監査が必要**です。

---

## 3. 次のステップ（推奨）

### Option A: コミット → Phase 3（Medium バグ修正）

1. **ユーザーにコミット確認** → 現在の変更をコミット
2. **再監査**: ソースコード全体を Medium 以上で再監査（8並列）
3. **Medium バグ修正**: 優先度順にグループ化して並列修正
4. **レビュー → LGTM**: 全件レビュワー LGTM 取得

### Option B: コミット → APP-001 対応

1. **ユーザーにコミット確認** → 現在の変更をコミット
2. **ユーザーに APP-001 対応を依頼**（鍵生成）
3. 鍵設定後、`project.yml` / `Info.plist` の更新を確認

### Option C: コミット → リリース準備

1. **ユーザーにコミット確認** → 現在の変更をコミット
2. v0.0.7 リリース準備（CHANGELOG、バージョンバンプ等）

---

## 4. サブエージェント構成（参考）

前回セッションで使用した構成:

| 役割 | エージェント | 用途 |
|------|------------|------|
| 調査 | Task (Claude Opus) × 3並列 | ソースコード監査 |
| コーダー | Task (Claude Opus) × 2〜4並列 | バグ修正実装 |
| レビュワー | Task (Claude Opus) × 2〜4並列 | コードレビュー |

**構成ルール:**
- 修正とレビューは必ず別エージェント
- レビュワーの LGTM で完了（修正完了 ≠ 完了）
- NEEDS_FIX → 修正 → 再レビュー → LGTM のサイクルを回す
- メインブランチで直接作業OK（ユーザー許可済み）

---

## 5. 重要ファイルの場所

| 目的 | パス |
|------|------|
| エージェント設定 | `/Users/sasuketorii/dev/Revclip/CLAUDE.md` |
| 共通ルール | `/Users/sasuketorii/dev/Revclip/.agent_rules/RULES.md` |
| 今回のSOW | `/Users/sasuketorii/dev/Revclip/.agent/active/sow/20260214_bugfix_audit_phase1_phase2.md` |
| このハンドオーバー | `/Users/sasuketorii/dev/Revclip/.agent/active/prompts/handover_to_next_orchestrator.md` |
| アプリソース | `/Users/sasuketorii/dev/Revclip/src/Revclip/Revclip/` |
| 定数定義 | `/Users/sasuketorii/dev/Revclip/src/Revclip/Revclip/App/RCConstants.h` / `.m` |
| DB管理 | `/Users/sasuketorii/dev/Revclip/src/Revclip/Revclip/Managers/RCDatabaseManager.h` / `.m` |

---

## 6. 注意事項

1. **残バグの詳細リストは消失** — Medium/Low バグの対応には再監査が必要
2. **全変更は未コミット** — 次の作業前にコミットを推奨
3. **APP-001 はコード修正不可** — ユーザーによる鍵生成が必要
4. **Vendor ファイル（FMDB, Sparkle）は変更禁止** — サードパーティライブラリ
5. **ビルドには XcodeGen + Xcode が必要** — `project.yml` から `.xcodeproj` を生成
