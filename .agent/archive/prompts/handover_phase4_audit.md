# ハンドオーバー: Phase 4 網羅的バグ監査へ

**作成日:** 2026-02-14
**作成者:** Orchestrator (Claude Opus 4.6)
**対象:** 次期オーケストレーター（コンテキスト共有なし）

---

## 0. あなたの役割

あなたは **オーケストレーター** です。自分ではコードの編集・実装・レビューを行いません。
全ての実作業はサブエージェント（Task ツール）に委譲してください。
詳細は `/Users/sasuketorii/dev/Revclip/CLAUDE.md` の「Orchestrator Hard Rules」セクションを必読。

---

## 1. プロジェクト概要

### 1.1 Revclip とは

**Revclip** は macOS 用のクリップボードマネージャーアプリケーション（Objective-C / Cocoa）です。

- **リポジトリルート:** `/Users/sasuketorii/dev/Revclip`
- **ソースコード:** `/Users/sasuketorii/dev/Revclip/src/Revclip/Revclip/` 配下
- **ブランチ:** `master`（メインブランチ、直接作業OK — ユーザー許可済み）
- **現バージョン:** v0.0.6
- **ビルドシステム:** XcodeGen (`project.yml` → `.xcodeproj`) + Xcode
- **言語:** Objective-C (Cocoa / AppKit)
- **Deployment Target:** macOS 14.0

### 1.2 主要機能

- クリップボード履歴の自動保存・メニュー表示
- スニペット（定型文）管理・フォルダ分類
- グローバルホットキー（メニュー表示、フォルダ直接呼び出し）
- スクリーンショット自動取り込み（ベータ機能）
- Sparkle 経由の自動アップデート
- アプリ除外設定、データクリーンアップ

### 1.3 ディレクトリ構成

```
/Users/sasuketorii/dev/Revclip/
├── CLAUDE.md                          # エージェント設定（必読）
├── .agent_rules/RULES.md              # 共通ルール（必読）
├── .agent/
│   ├── PROJECT_CONTEXT.md             # プロジェクトコンテキスト
│   ├── active/
│   │   ├── plan_20260214_phase3_bugfix.md  # Phase 3 ExecPlan（参考）
│   │   ├── sow/
│   │   │   ├── 20260214_bugfix_audit_phase1_phase2.md  # Phase 1+2 SOW
│   │   │   └── 20260214_bugfix_phase3_all_waves.md     # Phase 3 SOW ★
│   │   └── prompts/
│   │       ├── handover_to_next_orchestrator.md         # 旧ハンドオーバー（Phase 1+2→3）
│   │       └── handover_phase4_audit.md                 # このファイル ★
│   └── archive/
├── src/Revclip/
│   └── Revclip/                       # アプリケーションソースコード
│       ├── App/                       # AppDelegate, Constants, Environment, main.m
│       ├── Managers/                  # DatabaseManager, MenuManager
│       ├── Models/                    # ClipData, ClipItem
│       ├── Services/                  # ClipboardService, PasteService, HotKeyService, etc.
│       ├── UI/
│       │   ├── HotKeyRecorder/        # RCHotKeyRecorderView
│       │   ├── Preferences/           # 設定画面 VC + XIB
│       │   ├── SnippetEditor/         # スニペットエディタ
│       │   └── Views/                 # RCDesignableButton, RCDesignableView
│       ├── Utilities/                 # NSColor+HexString, NSImage+Color/Resize, RCUtilities
│       └── Vendor/                    # FMDB, Sparkle.framework（変更禁止）
└── src/Revclip/project.yml            # XcodeGen プロジェクト定義
```

---

## 2. これまでの作業履歴

### 2.1 コミット履歴（最新→古い順）

```
91e6a52 fix(config): resolve 7 app configuration, environment, and build settings issues    ← Phase 3 Wave 3
59cbc70 fix(ui): resolve 15 UI views and utilities correctness issues                       ← Phase 3 Wave 2 Group F
f8054e4 fix(prefs): resolve 14 preferences UI memory safety and UX issues                   ← Phase 3 Wave 2 Group E
8bdea1f fix(services): resolve 15 system services thread safety and error handling issues    ← Phase 3 Wave 2 Group D
7374c5f fix(menu): resolve 7 menu manager performance and correctness issues                ← Phase 3 Wave 2 Group C
e946831 fix(clipboard): resolve 16 clipboard, paste, and privacy service issues             ← Phase 3 Wave 2 Group B
4499b07 fix(db): resolve 17 database integrity and data model issues                        ← Phase 3 Wave 1 Group A
3a8a818 fix: Critical/High bug audit Phase 1+2 (10 bugs resolved)                           ← Phase 1+2
dde2ecc v0.0.6: hotkey menu at cursor position, login item auto-registration
27b12d2 v0.0.5: delete confirmation, full tooltip, shortcut reset button fix
```

### 2.2 修正統計

| Phase | 修正件数 | コミット数 | 変更行 |
|-------|---------|----------|--------|
| Phase 1+2 | 10件 (Critical 2, High 8) | 1 | ~290行 |
| Phase 3 Wave 1 | 17件 | 1 | +91/-103 |
| Phase 3 Wave 2 | 67件 (5並列) | 5 | +670/-203 |
| Phase 3 Wave 3 | 7件 | 1 | +44/-25 |
| **合計** | **101件** | **8コミット** | **~1,100行** |

### 2.3 修正カテゴリ別内訳

| カテゴリ | 修正内容 |
|---------|---------|
| **スレッド安全性** | メインスレッド dispatch、atomic プロパティ、@synchronized、dispatch_async |
| **メモリ管理** | __weak self、Cocoa Bindings unbind、dealloc クリーンアップ |
| **データ整合性** | DB INSERT OR IGNORE、外部キー PRAGMA、bounds check、ハッシュ改善 |
| **API 互換性** | lockFocus → block API、@available ガード、deprecated API 置換 |
| **UI/UX** | Auto Layout、runModal → sheet、ホットキーバリデーション、デバウンス |
| **堅牢性** | エラーハンドリング、入力バリデーション、ファイルサイズガード |
| **設定・ビルド** | 型安全化、定数リネーム、バージョン同期、Info.plist 改善 |

---

## 3. 現在の状態

### 3.1 ビルド状態

- **BUILD SUCCEEDED** — 全修正適用後、ビルド成功確認済み
- ビルドコマンド:
  ```bash
  xcodebuild -project /Users/sasuketorii/dev/Revclip/src/Revclip/Revclip.xcodeproj \
    -scheme Revclip -configuration Debug build 2>&1 | grep -E "error:|BUILD"
  ```

### 3.2 未コミット変更

```bash
git status --short
# 出力: .agent/ 配下のオーケストレーション成果物のみ（untracked）
# ソースコードの未コミット変更: なし（全てコミット済み）
```

### 3.3 既知の未対応事項

#### APP-001: SUPublicEDKey（ユーザーアクション必要 / コード修正不可）

Sparkle の EdDSA 公開鍵が未設定。自動アップデートの署名検証が無効。
→ ユーザーが `generate_keys` で鍵ペアを生成し、`project.yml` と `Info.plist` に公開鍵を設定する必要がある。

---

## 4. 次のタスク: Phase 4 網羅的バグ監査

### 4.1 目的

Phase 1-3 で101件のバグを修正したが、以下の理由で再度網羅的監査が必要:

1. **Phase 1+2 の修正自体にバグがあった実績**（例: `[app activate]` は存在しないセレクタだった）
2. **Phase 3 の5並列修正による相互作用の可能性**
3. **前回監査で見落としたバグの存在可能性**
4. **修正によって新たに発生した可能性のある問題**

### 4.2 推奨アプローチ

ユーザーの指示: **codex xhigh で並列調査** を実施。

#### Step 1: ソースファイル一覧の取得

```bash
# 全 .h/.m ファイルの一覧
find /Users/sasuketorii/dev/Revclip/src/Revclip/Revclip -name "*.h" -o -name "*.m" | \
  grep -v Vendor | sort
```

#### Step 2: グループ分け（推奨: 6-8並列）

| # | 監査グループ | 対象ファイル |
|---|------------|------------|
| 1 | App + Environment | `App/RCAppDelegate.h/.m`, `App/RCConstants.h/.m`, `App/RCEnvironment.h/.m`, `App/main.m` |
| 2 | Data Models + DB | `Models/RCClipData.h/.m`, `Models/RCClipItem.h/.m`, `Managers/RCDatabaseManager.h/.m` |
| 3 | Clipboard + Paste | `Services/RCClipboardService.h/.m`, `Services/RCPasteService.h/.m`, `Services/RCDataCleanService.h/.m` |
| 4 | Privacy + Exclude + Accessibility | `Services/RCPrivacyService.h/.m`, `Services/RCExcludeAppService.h/.m`, `Services/RCAccessibilityService.h/.m` |
| 5 | System Services | `Services/RCHotKeyService.h/.m`, `Services/RCScreenshotMonitorService.h/.m`, `Services/RCMoveToApplicationsService.h/.m`, `Services/RCUpdateService.h/.m`, `Services/RCLoginItemService.h/.m`, `Services/RCSnippetImportExportService.h/.m` |
| 6 | Menu Manager | `Managers/RCMenuManager.h/.m` |
| 7 | Preferences UI | `UI/Preferences/RC*PreferencesViewController.h/.m`, `UI/Preferences/RC*PreferencesView.xib`, `UI/Preferences/RCPreferencesWindowController.h/.m` |
| 8 | UI + Utilities | `UI/HotKeyRecorder/RCHotKeyRecorderView.h/.m`, `UI/SnippetEditor/RCSnippetEditorWindowController.h/.m`, `UI/Views/RCDesignableButton.h/.m`, `UI/Views/RCDesignableView.h/.m`, `Utilities/*.h/.m` |

#### Step 3: 各監査エージェントへの指示テンプレート

```
AGENT_ROLE=reviewer (codex xhigh)

## 監査対象
[ファイルパス一覧]

## 指示
1. 全ファイルを通読し、以下の観点でバグ・問題を検出:
   - クラッシュ、データ消失、セキュリティ脆弱性
   - スレッド安全性違反（メインスレッド外でのUI操作、データ競合）
   - メモリ管理問題（リテインサイクル、dangling pointer、リーク）
   - ロジックエラー、エッジケース未処理
   - API 誤用、deprecated API 使用
   - エラーハンドリング不足
   - パフォーマンス問題

2. 最近の修正（Phase 1-3）で入ったバグも見逃さない
   - 修正コメント（// G1-xxx, // G2-xxx 等）が付いた箇所を重点チェック

3. 出力フォーマット:
   - 各バグに一意ID (例: P4-001)
   - 重要度: Critical / High / Medium / Low
   - ファイル名:行番号
   - 問題の説明
   - 推奨修正案
```

#### Step 4: 監査結果の集約 → ExecPlan 作成 → 修正実行

監査結果を集約し、Phase 3 と同様に Wave 構成で ExecPlan を作成。
修正 → レビュー → LGTM のサイクルを回す。

### 4.3 注意事項

1. **Vendor ファイル（FMDB, Sparkle）は変更禁止** — サードパーティライブラリ
2. **XIB ファイルの変更は慎重に** — Auto Layout 制約の整合性を必ず検証
3. **deployment target は macOS 14.0** — `@available` ガードは macOS 14 未満チェック不要
4. **レビュワーは CLAUDE.md ルールでは Codex xhigh 固定** — ユーザーの指示に従い Codex を使用
5. **メインブランチで直接作業OK** — ユーザー許可済み、Worktree 不要

---

## 5. 重要ファイルの場所（クイックリファレンス）

| 目的 | 絶対パス |
|------|---------|
| エージェント設定 | `/Users/sasuketorii/dev/Revclip/CLAUDE.md` |
| 共通ルール | `/Users/sasuketorii/dev/Revclip/.agent_rules/RULES.md` |
| Phase 3 ExecPlan | `/Users/sasuketorii/dev/Revclip/.agent/active/plan_20260214_phase3_bugfix.md` |
| Phase 1+2 SOW | `/Users/sasuketorii/dev/Revclip/.agent/active/sow/20260214_bugfix_audit_phase1_phase2.md` |
| Phase 3 SOW | `/Users/sasuketorii/dev/Revclip/.agent/active/sow/20260214_bugfix_phase3_all_waves.md` |
| 旧ハンドオーバー | `/Users/sasuketorii/dev/Revclip/.agent/active/prompts/handover_to_next_orchestrator.md` |
| このハンドオーバー | `/Users/sasuketorii/dev/Revclip/.agent/active/prompts/handover_phase4_audit.md` |
| アプリソース | `/Users/sasuketorii/dev/Revclip/src/Revclip/Revclip/` |
| Xcode プロジェクト | `/Users/sasuketorii/dev/Revclip/src/Revclip/Revclip.xcodeproj` |
| project.yml | `/Users/sasuketorii/dev/Revclip/src/Revclip/project.yml` |
| Info.plist | `/Users/sasuketorii/dev/Revclip/src/Revclip/Revclip/Info.plist` |

---

## 6. サブエージェント構成（参考）

前セッションで使用した構成:

| 役割 | 実行手段 | 用途 |
|------|---------|------|
| 監査（6グループ並列） | Task (Claude Opus) | ソースコード全ファイル通読 + バグ分類 |
| Coder (Wave 1: 単独) | Task (Claude Opus) | Group A 17件修正 |
| Coder (Wave 2: 5並列) | Task (Claude Opus) | Group B-F 各グループ修正 |
| Coder (Wave 3: 単独) | Task (Claude Opus) | Group G 7件修正 |
| Reviewer (全グループ) | Task (Claude Opus) | 各グループの独立レビュー |

**構成ルール:**
- 修正とレビューは必ず別エージェント
- レビュワーの LGTM で完了
- NEEDS FIX → 修正 → 再レビュー → LGTM のサイクルを回す
- ビルド確認はオーケストレーターが `xcodebuild` で実行

---

## 7. 過去の教訓（次期オーケストレーターへ）

1. **Phase 1+2 の修正自体にバグがあった**: `[application activate]` は `NSRunningApplication` に存在しないセレクタだった → Phase 3 で発見・修正
2. **ARC naming convention**: `copySameHistoryButton` のように "copy" で始まるプロパティは ARC に拒否される → `sameHistoryCopyButton` にリネーム
3. **5並列修正時のクロスグループ影響**: ビルドエラーは Group F のビルドで他グループの問題が発覚した
4. **deployment target 14.0 のため `@available(macOS 14, *)` は常に true**: 不要な `@available` ガードが紛れ込みやすい
5. **レビューで NEEDS FIX が出たら即修正**: Group D の G4-013 (bundle ID 正規化漏れ) は実動作に影響する実バグだった
