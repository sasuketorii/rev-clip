# Revclip ハンドオーバー文書

> 作成日: 2026-02-13
> 作成者: codex (Claude Opus 4.6)
> 宛先: 次期オーケストレーター (Opus)

---

## 1. プロジェクト概要

Revclipは、macOS向けの人気クリップボードマネージャー「Clipy」を、Objective-C + AppKit で完全にリブランド・再実装するプロジェクトである。Clipyは長年メンテナンスされておらず、Swift 5 + RealmSwift + RxSwift + CocoaPods（15以上の依存ライブラリ）という重厚な技術スタックで構築されているため、最新macOS（Sequoia/macOS 16）での動作に問題が生じている。Revclipは、ClipyのUX/UIをピクセル単位で完全再現しつつ、Objective-C + ネイティブAPI中心の軽量な実装に置き換え、Apple Silicon対応・Apple公証対応を果たした上で「Revclip」として独自ブランドで配布することを目的とする。

---

## 2. 現在の状態（Status）

### 完了済み
- Clipyのソースコード全体の分析（全機能・全設定項目・全UIコンポーネントの洗い出し）
- 実装プラン（Rev.4確定版）の策定（1700行超の包括的設計文書）
- レビュー4回（Rev.1 -> Rev.2 -> Rev.3 -> Rev.4）を経てLGTM取得
  - Rev.1レビュー: Critical 2件 (C-1, C-2) + Major 6件 (M-1〜M-6) + Minor 7件 (m-1〜m-7) = 計15件の指摘
  - Rev.2: C-1, C-2, M-1〜M-6, m-1〜m-7 の全15件を修正
  - Rev.3: Xcode.app不使用制約への対応（ビルドシステム全面書き換え）
  - Rev.3レビュー: N-1 (Critical: Xcode.app依存関係の記載不正確), N-2 (Minor: notarytoolシンタックス), N-3 (Minor: submission ID抽出ロジック)
  - Rev.4: N-1〜N-3 の3件を修正 -> **LGTM**
- エージェント基盤（agent_base）のセットアップ

### 未完了
- **Phase 1〜3の全実装がまだ手付かず**（コードは1行も書かれていない）
- `src/` ディレクトリは空（`.gitkeep` のみ）
- Revclipの .xcodeproj / project.yml はまだ作成されていない
- 実装開始可能な状態であり、Phase 1から着手すべき

---

## 3. ディレクトリ構成（完全なパス付き）

### プロジェクトルート: `/Users/sasuketorii/dev/Revclip/`

```
/Users/sasuketorii/dev/Revclip/
├── .agent/                              # エージェント駆動開発の中核ディレクトリ
│   ├── PROJECT_CONTEXT.md               # プロジェクト固有コンテキスト（技術スタック・ワークフロー定義）
│   ├── requirements.md                  # 要件定義書のテンプレート（未記入）
│   ├── active/                          # 現在進行中のタスク格納場所
│   │   ├── prompts/                     # サブエージェントへの依頼プロンプト格納場所
│   │   │   └── .gitkeep
│   │   └── sow/                         # セッション別SOW格納場所
│   │       └── .gitkeep
│   └── archive/                         # 完了した作業のアーカイブ
│       ├── docs/                        # アーカイブされたドキュメント
│       ├── feedback/                    # 過去のレビューフィードバック
│       ├── plans/                       # 完了したプラン
│       ├── prompts/                     # 完了したハンドオーバー
│       ├── sow/                         # 完了したSOW
│       └── test/                        # アーカイブされたテスト
│
├── .agent_rules/                        # 全エージェント共通ルール
│   └── RULES.md                         # 共通ルール定義（36KB、CRITICAL / MUST FOLLOW）
│
├── .claude/                             # Claude CLI 設定ディレクトリ
│   ├── settings.json                    # Hook設定（PostToolUse: Edit/Write時にレビューキュー蓄積）
│   ├── commands/
│   │   ├── auto_orchestrate.sh          # メインオーケストレーションスクリプト（test->impl->review->fixの自動反復）
│   │   ├── README.md                    # コマンド使用ガイド
│   │   └── lib/                         # 共有ライブラリ群
│   │       ├── coder.sh                 # Claude CLI制御（セッション管理・修正実行）
│   │       ├── reviewer.sh              # Codex CLI制御（並列レビュー・動的選択）
│   │       ├── session.sh               # セッションライフサイクル管理
│   │       ├── state.sh                 # 実行状態管理（state.json操作）
│   │       ├── timeout.sh               # タイムアウト管理
│   │       └── utils.sh                 # ユーティリティ関数（ログ・ファイル操作・ロック等）
│   ├── hooks/
│   │   └── codex-review-hook.sh         # PostToolUseフック（変更ファイルをレビューキューに蓄積）
│   └── skills/
│       ├── auto-orchestrator/
│       │   └── SKILL.md                 # オーケストレーターSkill定義
│       ├── codex-caller/
│       │   └── SKILL.md                 # Codex呼び出しSkill定義
│       └── design-principles/
│           └── SKILL.md                 # 設計原則Skill定義
│
├── .codex/                              # Codex CLI 設定ディレクトリ
│   └── config.toml                      # Codex設定（model: gpt-5.3-codex, reasoning: xhigh）
│
├── agent_base/                          # エージェント基盤のサブディレクトリ
│   ├── docs/
│   │   ├── revclip_plan.md              # ★ 実装プラン Rev.4確定版（1716行、最重要ファイル）
│   │   ├── revclip_plan_review.md       # ★ レビュー結果（LGTM済み）
│   │   ├── SOW.md                       # ★ 要件定義書（53機能・受け入れ基準・Phase全量・リスク一覧）
│   │   └── HANDOVER.md                  # この文書
│   └── src/
│       └── Clipy/                       # ★ Clipyの元ソースコード（git clone済み、読み取り参照用）
│           ├── Clipy.xcodeproj/         #   Xcodeプロジェクト設定
│           ├── Clipy.xcworkspace/       #   CocoaPodsワークスペース
│           ├── Clipy/                   #   ソースコード本体
│           │   ├── Generated/           #     SwiftGen自動生成コード
│           │   ├── Xibs/                #     XIBファイル
│           │   ├── Resources/           #     画像・ローカライズリソース
│           │   ├── Supporting Files/    #     Info.plist等
│           │   └── Sources/             #     Swiftソースコード
│           │       ├── AppDelegate.swift
│           │       ├── Constants.swift
│           │       ├── Services/        #       ClipService, PasteService, HotKeyService等
│           │       ├── Managers/        #       MenuManager
│           │       ├── Models/          #       CPYClip, CPYClipData, CPYFolder, CPYSnippet等
│           │       ├── Preferences/     #       設定画面（7タブ）
│           │       ├── Snippets/        #       スニペットエディタ
│           │       ├── Views/           #       カスタムビュー
│           │       ├── Extensions/      #       拡張
│           │       └── Utility/         #       共通ユーティリティ
│           ├── ClipyTests/              #   テストコード
│           ├── Podfile / Podfile.lock   #   CocoaPods依存定義
│           └── README.md
│
├── docs/                                # プロジェクト共通ドキュメント
│   ├── README.md                        # ドキュメント一覧
│   ├── official-docs-links.md           # 公式ドキュメントリンク集
│   ├── design/                          # アーキテクチャ設計
│   ├── entitlements/                    # 署名・公証用設定
│   ├── incidents/                       # インシデント記録
│   ├── manual/                          # 運用マニュアル
│   ├── prompts/                         # レビュワープロンプトテンプレート
│   ├── release-notes/                   # リリースノート
│   ├── requirements/                    # 要件定義書
│   └── roles/                           # 役割定義（Coder/Reviewer/Orchestrator）
│
├── rules/
│   └── 00-general.mdc                   # 一般ルール
│
├── scripts/                             # ビルド・ユーティリティスクリプト群
│   ├── build-dev.sh                     # 開発ビルドスクリプト
│   ├── codex-wrapper.sh                 # Codexラッパー（ベース）
│   ├── codex-wrapper-high.sh            # Coder用ラッパー（reasoning effort = high）
│   ├── codex-wrapper-medium.sh          # 軽量Coder用ラッパー（reasoning effort = medium）
│   ├── codex-wrapper-xhigh.sh           # Reviewer用ラッパー（reasoning effort = xhigh）
│   ├── hydra                            # Hydraスクリプト（マルチworktree管理）
│   ├── init-project.sh                  # プロジェクト初期化
│   ├── quality_gate.sh                  # 品質ゲート
│   ├── sign-and-build.sh               # 署名・ビルドスクリプト
│   └── template/                        # テンプレートスクリプト
│       ├── flutter-sign-template.sh
│       └── tauri-sign-template.sh
│
├── setup/
│   ├── bootstrap.sh                     # ブートストラップスクリプト
│   └── setup_rules.md                   # セットアップ手順
│
├── src/
│   └── .gitkeep                         # ★ Revclipのソースコード配置場所（空、ここに実装する）
│
├── test/
│   ├── hydra_test.sh                    # Hydraテスト
│   └── README.md                        # テストガイド
│
├── workflows/
│   ├── build-and-sign.yml               # GitHub Actions: ビルド・署名
│   └── ci.yml                           # GitHub Actions: CI
│
├── CLAUDE.md                            # ★ Claude CLI行動規定（オーケストレーターのハードルール含む）
├── AGENTS.md                            # ★ Codex CLI行動規定（ラッパースクリプト設定含む）
├── README.md                            # プロジェクト全体のREADME
└── .gitignore                           # Git除外設定
```

---

## 4. 重要ファイルの説明

### `revclip_plan.md`（実装プラン Rev.4確定版）
- **場所**: `/Users/sasuketorii/dev/Revclip/agent_base/docs/revclip_plan.md`
- **分量**: 1716行超の包括的設計文書
- **内容**:
  - セクション0: Clipyソースコード分析結果（ディレクトリ構成・全機能一覧・全ライブラリの代替マッピング）
  - セクション1: 技術スタック選定理由（Objective-C + AppKit、不採用技術の理由）
  - セクション2: アーキテクチャ設計（Revclipのディレクトリ構成・モジュール分割・データフロー）
  - セクション3: 機能マッピング（Clipy全機能のRevclip実装対応表、全設定項目マッピング、UIマッピング）
  - セクション4: **実装フェーズ（Phase 1〜3の詳細タスク一覧・優先度・完了基準）** -- 実装時に最も参照する部分
  - セクション5: ビルド・配布戦略（xcodebuild/ibtool/actool/codesign/notarytoolの全コマンド、project.yml定義、Makefile）
  - セクション6: リスクと対策（macOS 16プライバシー対応設計、Sequoiaホットキー制限対応設計、互換性・UX・配布リスク）
  - セクション7: ブランディングチェックリスト
  - セクション8: 実装上の重要な技術詳細（Carbon API、クリップボード監視、ペースト実行、SQLiteスキーマ、PasteboardType対応）
  - セクション9: テスト戦略（全テストファイル一覧・テスト内容・手動テスト項目）
  - セクション10: 工数見積もり
  - セクション11: 今後の拡張可能性
- **使い方**: 実装の際はこのファイルを「仕様書」として参照する。Phase 1のタスク1-1から順に実装を進める

### `revclip_plan_review.md`（レビュー結果）
- **場所**: `/Users/sasuketorii/dev/Revclip/agent_base/docs/revclip_plan_review.md`
- **内容**: Rev.4に対するレビュー結果。N-1〜N-3の3件の指摘事項がすべて解消済みであることを確認し、**LGTM**が出ている
- **経緯**: Rev.1で15件の指摘 -> Rev.2で全修正 -> Rev.3でXcode.app制約対応 -> Rev.3レビューで3件追加指摘 -> Rev.4で修正 -> LGTM
- **使い方**: プランが正式承認済みであることの証拠。実装はこのLGTMに基づいて開始する

### `SOW.md`（要件定義書 / Statement of Work）
- **場所**: `/Users/sasuketorii/dev/Revclip/agent_base/docs/SOW.md`
- **内容**:
  - 53機能の受け入れ基準付き要件定義
  - In Scope / Out of Scope の明確な定義
  - Phase 1/2/3の全タスクと完了条件
  - リスク一覧（R-001〜R-016）
  - 付録: 設定項目全量マッピング、SQLiteスキーマ、ディレクトリ構成
- **使い方**: 実装プラン（`revclip_plan.md`）と並ぶ重要参照文書。プランが「どう作るか」を定義するのに対し、SOWは「何を作るか・どこまでが範囲か」を定義する。実装着手前にスコープ確認、タスク完了時に受け入れ基準の照合に使用する

### `CLAUDE.md`（Claude CLI行動規定）
- **場所**: `/Users/sasuketorii/dev/Revclip/CLAUDE.md`
- **内容**:
  - **オーケストレーターのハードルール（CRITICAL）**: コード編集禁止、ドキュメント編集禁止、許可パスの限定
  - Codex呼び出しルール: wrapper経由必須（`codex-wrapper-high.sh` / `codex-wrapper-xhigh.sh`）
  - 委譲の原則: 全ての実作業をサブエージェントに委譲
  - auto_orchestrate.sh の使い方
  - Hooks設定、状態管理（state.json）の説明
- **重要**: オーケストレーターはこのファイルのルールに**絶対遵守**すること

### `AGENTS.md`（Codex CLI行動規定）
- **場所**: `/Users/sasuketorii/dev/Revclip/AGENTS.md`
- **内容**: Codex CLIの設定（config.toml）、ラッパースクリプトの使い方、セッション管理、役割対応表
- **重要**: サブエージェント（Codex）の行動規定

### `.agent_rules/RULES.md`（共通ルール）
- **場所**: `/Users/sasuketorii/dev/Revclip/.agent_rules/RULES.md`
- **内容**: 全エージェント共通のルール（36KB）。Phase 0-5の開発プロセス、役割定義、品質ゲート等
- **重要**: CLAUDE.mdとAGENTS.mdの両方から参照される上位ルール

### `.agent/PROJECT_CONTEXT.md`（プロジェクトコンテキスト）
- **場所**: `/Users/sasuketorii/dev/Revclip/.agent/PROJECT_CONTEXT.md`
- **内容**: Agent Base自体のプロジェクト概要（エージェント基盤のテンプレート運用）、ディレクトリ構造説明、開発ワークフロー、コミット規約

---

## 5. ユーザー確定済みの制約条件（絶対遵守）

以下の制約条件はユーザーが明示的に承認・指示したものであり、変更・交渉の余地はない。

1. **UX/UIはClipyそのまま**: メニューバーアイコン、ポップアップメニュー、設定画面（7タブ）、スニペットエディタのレイアウト・挙動をピクセル単位で再現する
2. **Swiftは使わない**: ユーザーが明示的にSwift不使用を方針として宣言済み
3. **Objective-C + AppKit（ユーザー承認済み）**: 技術スタックはObjective-C + AppKit (Cocoa)で確定している
4. **Apple Silicon対応必須**: Universal Binary（arm64 + x86_64）でビルドする
5. **最新macOS対応**: Deployment Target macOS 14.0、ターゲット15.0 (Sequoia)、macOS 16プライバシー対応も設計済み
6. **軽量アプリケーション**: 外部依存を最小限（Sparkle 2.x + FMDB程度）に抑える
7. **Apple公証対応（Developer Program契約済み）**: Hardened Runtime有効化、`xcrun notarytool submit` でApple公証取得、Developer ID Applicationで署名
8. **完全にRevclipとしてブランディング**: クラスプレフィックス `RC`、Bundle ID `com.revclip.Revclip`、「Clipy」の痕跡を一切残さない
9. **Xcode.appのIDE手動操作不要、すべてターミナル完結**: Xcode.appはApp Storeからインストールするが、IDEとして開く必要はない。すべてxcodebuild/ibtool/actool等のCLIツールで完結する

---

## 6. 次のステップ（具体的に）

### Phase 1 から実装を開始する

Phase 1の目標は「アプリの骨格を完成させ、クリップボード監視→履歴表示→ペーストの基本フローを動作させる」こと。

### Phase 1 タスク一覧（優先順序・依存関係付き）

| 順序 | タスクID | タスク名 | 優先度 | 依存 | 概要 |
|------|---------|---------|--------|------|------|
| 1 | 1-1 | プロジェクトセットアップ | 最高 | なし | xcodegen / project.yml 作成、.xcodeproj生成、Bundle ID・Deployment Target・Architectures設定、Makefile作成 |
| 2 | 1-2 | 定数・環境定義 | 最高 | 1-1 | `RCConstants.h/.m` + `RCEnvironment.h/.m`（シングルトンDIコンテナ）、全UserDefaultsキー定義（プランのセクション3.4） |
| 3 | 1-3 | データベース層 | 最高 | 1-1 | FMDB組込、`RCDatabaseManager`、SQLiteスキーマ作成（プランのセクション8.4）、マイグレーション |
| 4 | 1-4 | クリップボードモデル | 最高 | 1-3 | `RCClipItem.h/.m` + `RCClipData.h/.m`（NSCoding準拠） |
| 5 | 1-5 | クリップボード監視 | 最高 | 1-4 | `RCClipboardService` - dispatch_sourceタイマー750usポーリング、NSPasteboard変更検出→RCClipData作成→ファイル保存→DB INSERT |
| 6 | 1-6 | メニューマネージャー基盤 | 最高 | 1-5 | `RCMenuManager` - NSStatusItem作成、クリップ履歴からNSMenu構築、基本メニュー項目、data_hashベースのクリップ選択 |
| 7 | 1-7 | ペーストサービス | 最高 | 1-6 | `RCPasteService` - NSPasteboardへの書き戻し + CGEvent Cmd+Vシミュレーション + Beta修飾キー判定ロジック |
| 8 | 1-8 | Accessibility権限 | 高 | 1-1 | `RCAccessibilityService` - AXIsProcessTrustedWithOptions + 権限要求アラート |
| 9 | 1-9 | UserDefaults初期化 | 高 | 1-2 | `RCUtilities` - 全デフォルト設定の登録（セクション3.4の全項目のデフォルト値） |
| 10 | 1-10 | macOS 16プライバシー対応基盤 | 高 | 1-5 | `RCClipboardService` に accessBehavior チェック + detect メソッド対応の条件分岐を組込 |

**Phase 1 完了基準**: メニューバーにアイコン表示 → クリップボードコピーを検出 → 履歴メニューに表示 → クリックでペースト実行

### 依存関係の図

```
1-1 (プロジェクトセットアップ)
 ├── 1-2 (定数・環境定義) ─── 1-9 (UserDefaults初期化)
 ├── 1-3 (データベース層)
 │    └── 1-4 (クリップボードモデル)
 │         └── 1-5 (クリップボード監視)
 │              ├── 1-6 (メニューマネージャー基盤)
 │              │    └── 1-7 (ペーストサービス)
 │              └── 1-10 (macOS 16プライバシー対応基盤)
 └── 1-8 (Accessibility権限)
```

### 推奨サブエージェント構成

| 役割 | 人数 | 担当 | Wrapper |
|------|------|------|---------|
| **コーダー** | 1-2名 | 実装作業（Phase 1のタスクを順次実装） | `codex-wrapper-high.sh` |
| **レビュワー** | 1名 | 各タスク完了後のコードレビュー | `codex-wrapper-xhigh.sh` |

**注意**: Phase 1のタスクは依存関係が多いため、**基本的には1コーダーで順次実装**する方が安全。1-8 (Accessibility) は1-5以降と並列実行可能。

---

## 7. 全体のフェーズ構成

### Phase 1: 基盤構築（推定: 2-3週間）

**目標**: アプリの骨格を完成させ、クリップボード監視→履歴表示→ペーストの基本フローを動作させる

**タスク**: 1-1〜1-10（上記参照）

**完了条件**:
- メニューバーにRevclipアイコンが表示される
- クリップボードにコピーした内容が検出される
- 履歴メニューに表示される
- クリックでペースト実行される

### Phase 2: UI/UX完成（推定: 2-3週間）

**目標**: Clipyと同等のUI/UXを完全再現する

**主要タスク**:
- 2-1: グローバルホットキー（Carbon API RegisterEventHotKey直接使用、フォルダ個別ホットキー含む）
- 2-2: ホットキーレコーダーUI（RCHotKeyRecorderView、KeyHolderの代替）
- 2-3: 設定ウィンドウ（7タブ: General/Menu/Type/Exclude/Shortcuts/Updates/Beta）
- 2-4: スニペットエディタ（NSSplitView + NSOutlineView + NSTextView、D&D並替え）
- 2-5: スニペットインポート/エクスポート（NSXMLDocument、Clipy XML互換）
- 2-6: 除外アプリサービス（NSWorkspace通知、1Password等特殊アプリ対応）
- 2-7: データクリーンアップ（30分間隔、上限超過履歴削除）
- 2-8: メニュー高度機能（サムネイル・カラーコードプレビュー・ツールチップ等）
- 2-9: UIコンポーネント（RCDesignableView / RCDesignableButton）

**完了条件**:
- 設定画面全7タブが動作し、全設定項目が反映される
- スニペット作成・編集・ドラッグ並替えが動作する
- ホットキーによるメニューポップアップ（フォルダ個別含む）が動作する
- 除外アプリが動作する
- Beta機能の修飾キー動作が確認できる

**Phase 1への依存**: Phase 1の全タスクが完了していること

### Phase 3: ブランディング・配布準備（推定: 1-2週間）

**目標**: Revclipとしての完全ブランディングと配布可能な状態にする

**主要タスク**:
- 3-1: アイコン・ブランディング（AppIcon、StatusBarアイコン、全サイズ生成）
- 3-2: ローカライズ（en/ja/de/zh-Hans/it の5言語）
- 3-3: Sparkle 2.x統合（EdDSA署名鍵生成、appcast.xmlホスティング）
- 3-4: ログインアイテム（SMAppService macOS 13+）
- 3-5: "Applicationsフォルダへ移動"機能
- 3-6: スクリーンショット監視（NSMetadataQuery、Beta機能）
- 3-7: コード署名（Developer ID、Hardened Runtime）
- 3-8: 公証（xcrun notarytool submit）
- 3-9: DMG作成（create-dmg）
- 3-10: テスト（全Service/Managerのユニットテスト + 手動テスト）
- 3-11: クラッシュレポート（オプション）
- 3-12: macOS 16動作検証

**完了条件**:
- Revclipブランディングが完全に適用されている（Clipyの痕跡なし）
- Apple公証が通る
- DMGインストーラーが作成されている
- 全テストが通る
- Apple Silicon + Intel 両アーキテクチャで動作確認済み

**Phase 2への依存**: Phase 2の全タスクが完了していること

---

## 8. 開発環境セットアップ手順

### 前提条件
- macOS 14.0 (Sonoma) 以降が動作するMac（Apple Siliconまたは Intel）
- Apple Developer Program 契約済み（公証に必要）
- Homebrew インストール済み

### セットアップコマンド

```bash
# Step 1: Xcode.appのインストール
# App Store で "Xcode" を検索してインストールする
# ★ インストール後、Xcode.appを開く必要はない

# Step 2: xcode-select でXcode.appのDeveloperディレクトリを指定
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

# Step 3: ライセンス承諾（初回のみ）
sudo xcodebuild -license accept

# Step 4: オプションツールのインストール
brew install xcodegen create-dmg jq

# Step 5: ツール確認
xcodebuild -version
xcrun --find notarytool
xcrun --find stapler
xcrun --find ibtool
xcrun --find actool
```

### ビルドコマンド

```bash
# プロジェクト生成（project.yml作成後）
cd /path/to/Revclip/src/Revclip   # ★ 実装後のパス
xcodegen generate

# Debugビルド
xcodebuild -project Revclip.xcodeproj -scheme Revclip -configuration Debug build

# ビルド＆実行
xcodebuild -project Revclip.xcodeproj -scheme Revclip -configuration Debug build && \
open build/Debug/Revclip.app

# Releaseビルド（Universal Binary）
xcodebuild -project Revclip.xcodeproj -scheme Revclip -configuration Release \
  -arch arm64 -arch x86_64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="Developer ID Application: YOUR_NAME (TEAM_ID)" \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  OTHER_CODE_SIGN_FLAGS="--options=runtime" build
```

### テスト実行

```bash
# 全テスト実行
xcodebuild -project Revclip.xcodeproj -scheme Revclip -configuration Debug test

# 特定テストクラスのみ
xcodebuild -project Revclip.xcodeproj -scheme Revclip \
  -only-testing:RevclipTests/RCClipboardServiceTests test
```

### Makefileラッパー（プランのセクション5.6.6に定義あり）

```bash
make setup    # プロジェクト生成
make build    # Debugビルド
make run      # ビルド＆実行
make test     # テスト
make release  # Releaseビルド
make sign     # 署名検証
make clean    # クリーン
```

---

## 9. 注意事項・地雷ポイント

### 9.1 macOS 16 クリップボードプライバシー対応（C-1で指摘、プランのセクション6.5で設計済み）

- macOS 15.4で開発者プレビュー、macOS 16で正式導入される「Paste from Other Apps」プライバシー機能
- `NSPasteboard.changeCount` の比較自体はアラートなしで可能
- **内容読み取り**（`stringForType:`, `dataForType:`, `types`等）でシステムアラートが表示される
- **対応策**: `@available(macOS 16.0, *)` で条件分岐、`accessBehavior` による事前チェック、`detect` メソッドによるアラート回避、初回起動時のユーザーガイダンスUI
- **影響度: 最高** -- Phase 1のタスク1-10で基盤実装が必要

### 9.2 macOS Sequoia ホットキーAPI制限（C-2で指摘、プランのセクション6.6で設計済み）

- macOS Sequoia 15で、`RegisterEventHotKey` において **Option単独** または **Option+Shift** のみの修飾キー組み合わせが動作しなくなった
- Clipyのデフォルトホットキー（Cmd+Shift+V等）は影響を受けない（Cmd修飾キーを含むため）
- ユーザーがカスタムでOption系ホットキーを設定した場合に動作しない
- **対応策**: `RCHotKeyRecorderView` でOption系組み合わせ設定時に警告表示、将来的なプランBとして `CGEvent.tapCreate` ベースの実装を準備

### 9.3 ibtool/actool がXcode.app依存（N-1で指摘、Rev.4で修正済み）

- `ibtool`、`actool`、`xcodebuild` は **Xcode Command Line Tools 単体では動作しない**
- **Xcode.appのフルインストールが必須**（ただしIDEとしての手動操作は不要）
- セットアップ時に `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` が必要
- プラン中の全箇所（セクション1、5.6.1、Phase 1タスク1-1、セクション5.6.5）で統一して記載済み

### 9.4 notarytool のシンタックス（N-2, N-3で指摘、Rev.4で修正済み）

- `xcrun notarytool submit` では `--keychain-profile "AC_PASSWORD"` を使用する
- **旧altoolの** `--password "@keychain:AC_PASSWORD"` は**使えない**
- submission ID の抽出: `notarytool submit --wait` の出力をキャプチャし、`grep -m1 '  id:' | awk '{print $2}'` で抽出する
- `store-credentials` は初回のクレデンシャル保存用で、submit/logとは異なるシンタックス

### 9.5 Hardened Runtime + CGEvent.post の動作検証

- Hardened Runtime環境下で `CGEventPost` を使用する場合、Accessibility権限（TCC）が付与されていれば動作する
- 追加のEntitlementは不要だが、**Phase 1の早い段階で実機動作検証すること**（プランのセクション5.3に記載）

### 9.6 App Sandboxは有効にしない

- クリップボード監視・CGEventポスト・Accessibility API使用のため、App Sandboxとは非互換
- **Hardened Runtimeのみ有効化**する
- App Storeでの配布は不可（Webサイト直接配布 + DMG形式）

### 9.7 XIBファイルの編集方法

- XIBファイルはXML形式のテキストファイルであり、テキストエディタで直接編集可能
- 複雑なレイアウトが必要な場合は、コードベースのUI構築（プログラム的なNSView/NSWindow構築）も選択肢
- ibtoolでコンパイル検証: `ibtool --warnings --errors path/to/file.xib`

### 9.8 FMDB組込方法

- CocoaPodsは使わない。FMDBのソースコードを `Revclip/Vendor/FMDB/` に直接組込む
- Sparkle 2.x も同様に `Revclip/Vendor/Sparkle.framework/` に直接組込む

### 9.9 NSFilenamesPboardType の非推奨

- macOS 14で `NSFilenamesPboardType` が正式に非推奨
- `NSPasteboardTypeFileURL` (`public.file-url`) も併せてサポートする必要がある

### 9.10 Revclipのソースコード配置場所

- Revclipの実装コードは `/Users/sasuketorii/dev/Revclip/src/` に配置する（現在は空）
- Clipyの元ソースコードは `/Users/sasuketorii/dev/Revclip/agent_base/src/Clipy/` にあり、参照専用

---

## 10. ワークフロー指示

### オーケストレーターとしての振る舞い方

1. **自分ではコードを書かない**: `CLAUDE.md` のオーケストレーターハードルールに従い、`src/`、`test/`、`docs/` 配下のファイルをEdit/Writeしない
2. **すべての実作業をサブエージェントに委譲する**: Task ツール（Claude Code内蔵）でサブエージェントを起動する
3. **プランファイルを仕様書として渡す**: サブエージェントへのプロンプトに、実装プラン（`/Users/sasuketorii/dev/Revclip/agent_base/docs/revclip_plan.md`）の該当セクションを引用または参照指示として含める

### サブエージェントの使い方（コーダー -> レビュワー -> LGTMサイクル）

1. **コーダーに実装を依頼**:
   - タスクの範囲を明確に指定（例: 「Phase 1 タスク1-1: プロジェクトセットアップ」）
   - プランの該当セクションを引用して仕様を伝える
   - 制約条件（セクション5の「ユーザー確定済みの制約条件」）を必ず含める
   - 実装完了後、コーダーの出力を受け取る

2. **レビュワーにレビューを依頼**:
   - コーダーの実装結果をレビュワーに渡す
   - プランの該当セクションを基準としたレビューを依頼する
   - レビュワーはCodex（`codex-wrapper-xhigh.sh`）で実行する

3. **レビュー結果の処理**:
   - レビュワーがLGTMを出す -> 次のタスクに進む
   - レビュワーが指摘を出す -> コーダーに修正を依頼 -> 再レビュー
   - **レビュワーがLGTMを出すまでユーザーに報告しない**

4. **サイクルの繰り返し**:
   - 最大5回のレビュー反復（`--max-iterations 5`）
   - 5回で解消しない場合はエスカレーション（ユーザーに報告）

### Codex呼び出し時の注意

- **wrapper経由必須**: `codex exec` を直接呼ばず、必ず以下のwrapper経由で呼ぶ
  - コーダー用: `./scripts/codex-wrapper-high.sh`
  - レビュワー用: `./scripts/codex-wrapper-xhigh.sh`
  - 軽量タスク用: `./scripts/codex-wrapper-medium.sh`
- **`-c model=...` オプション指定禁止**: wrapperが自動設定する
- **`codex resume` はオーケストレーター経由で実行しない**: TTY必須のため動作しない。新規セッション（`codex exec`）で前回のコンテキストをプロンプトに含めて再実行すること

### メインブランチでの作業許可

ユーザーからメインブランチでの作業許可が出ている場合、サブエージェントへのプロンプトに以下を必ず明記すること:

```
## 許可事項
ユーザーからの明示的許可: メインブランチで作業してOKです。Worktree/ブランチを切る必要はありません。
```

### auto_orchestrate.sh の使い方（オプション）

```bash
# Phase 1の実装を自動オーケストレーション
./.claude/commands/auto_orchestrate.sh \
  --plan agent_base/docs/revclip_plan.md \
  --phase impl \
  --run-coder \
  --fix-until high \
  --max-iterations 5

# 状態確認
./.claude/commands/auto_orchestrate.sh \
  --resume .claude/tmp/revclip/state.json \
  --status
```

---

## 付録: クイックリファレンス

### 最も重要なファイル3つ

1. `/Users/sasuketorii/dev/Revclip/agent_base/docs/revclip_plan.md` -- 実装の全仕様
2. `/Users/sasuketorii/dev/Revclip/CLAUDE.md` -- オーケストレーターのルール
3. `/Users/sasuketorii/dev/Revclip/agent_base/docs/revclip_plan_review.md` -- LGTM確認

### Clipyソースコードの参照先

`/Users/sasuketorii/dev/Revclip/agent_base/src/Clipy/Clipy/Sources/` 配下にClipyの全Swiftソースがある。Revclipの各サービス/モデル/UIを実装する際に、Clipyの対応するSwiftファイルを参照して動作仕様を確認すること。

### Revclipの実装先

`/Users/sasuketorii/dev/Revclip/src/` -- ここにRevclipのソースコードを配置する（現在は空）

### プランのセクション逆引き

| やりたいこと | プランのセクション |
|------------|------------------|
| Phase 1のタスク詳細を見たい | セクション4「実装フェーズ」Phase 1 |
| SQLiteスキーマを確認したい | セクション8.4 |
| project.ymlの定義を確認したい | セクション5.1.2 |
| Makefileの定義を確認したい | セクション5.6.6 |
| Entitlementsを確認したい | セクション5.3 |
| macOS 16プライバシー対応の設計を見たい | セクション6.5 |
| ホットキー制限への対応を見たい | セクション6.6 |
| 設定項目の全一覧を見たい | セクション3.4 |
| UIマッピング（Clipy -> Revclip）を見たい | セクション3.3 |
| ビルド・署名・公証のコマンドを見たい | セクション5.1.5〜5.6.3 |
| テスト戦略を見たい | セクション9 |
| 全ライブラリの代替マッピングを見たい | セクション0.3 |
