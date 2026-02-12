# Project Context / プロジェクトコンテキスト

このファイルは、プロジェクト固有の情報をエージェントに伝えるためのコンテキストファイルです。
`.agent_rules/RULES.md` の汎用ルールを補完し、本プロジェクト固有の設定を定義します。

---

## プロジェクト概要

**Agent Base** は、Claude（Coder）と Codex（Reviewer）が人間の介入なしに自律的に協調し、
コード品質を担保するマルチベンダーAI協調開発基盤です。

---

## 技術スタック

| カテゴリ | 技術 | バージョン/備考 |
|---------|------|----------------|
| 言語 | Bash (Shell Script) | POSIX互換 |
| CLI | Claude Code CLI | Anthropic |
| CLI | Codex CLI | OpenAI |
| JSON処理 | jq | 必須依存 |
| バージョン管理 | Git | Worktree対応 |

---

## テンプレート運用

**agent_base は「テンプレート」として使用します。**

```bash
# 新規プロジェクト作成
git clone https://github.com/your-org/agent_base.git my_project
cd my_project
rm -rf .git && git init
```

---

## ディレクトリ構造

```
my_project/                  # agent_baseをコピーした新リポジトリ
│
├── src/                     # ← アプリケーションコード（推奨配置場所）
│   ├── api/                 #    APIエンドポイント
│   ├── components/          #    UIコンポーネント
│   ├── services/            #    ビジネスロジック
│   └── utils/               #    ユーティリティ
│
├── test/                    # テストコード
│
├── .agent/                  # エージェント駆動開発の中核
│   ├── requirements.md      # 要件定義書（ユーザー投下）
│   ├── PROJECT_CONTEXT.md   # このファイル
│   ├── active/              # 現在進行中のタスク
│   │   ├── plan_YYYYMMDD_HHMM_<task>.md  # ExecPlan
│   │   ├── sow/             # セッション別SOW
│   │   └── prompts/         # ハンドオーバー/レビュー用
│   └── archive/             # 完了した作業
│
├── .agent_rules/            # 汎用ルール（全エージェント共通）
│   └── RULES.md
│
├── .claude/                 # Claude CLI設定
│   ├── commands/            # CLIコマンド
│   ├── hooks/               # PostToolUseフック
│   ├── skills/              # Skillプラグイン
│   └── tmp/                 # 一時ファイル
│
├── .codex/                  # Codex CLI設定
│   └── config.toml
│
├── docs/                    # プロジェクトドキュメント
│   ├── requirements/        #    要件定義書、ユーザーストーリー
│   ├── design/              #    アーキテクチャ設計、DBスキーマ、API仕様
│   ├── manual/              #    運用マニュアル、セットアップガイド
│   ├── roles/               #    役割定義（Coder/Reviewer/Orchestrator）
│   ├── prompts/             #    レビュワープロンプトテンプレート
│   ├── release-notes/       #    リリースノート
│   ├── incidents/           #    インシデント記録
│   └── entitlements/        #    署名・公証用設定
│
├── scripts/                 # ビルド・ユーティリティ
├── setup/                   # セットアップ
│
└── workspace/               # Hydra worktree用（.gitignore済み）
```

### 重要: コード配置ルール

| ディレクトリ | 用途 | 備考 |
|-------------|------|------|
| `src/` | **アプリケーションコード** | 推奨配置場所 |
| `test/` | テストコード | src/と対応 |
| `workspace/` | Hydra worktree作業用 | **恒久的コード配置禁止**（.gitignore）※Hydra worktree内の作業コードは可 |

---

## 開発ワークフロー

### 1. 要件定義
```bash
# ユーザーが .agent/requirements.md に要件を記載
```

### 2. プラン生成
```bash
# エージェントが .agent/active/plan_YYYYMMDD_HHMM_<task>.md を生成
```

### 3. 実装（Coder）
```bash
./.claude/commands/auto_orchestrate.sh \
  --plan .agent/active/plan_YYYYMMDD_HHMM_<task>.md \
  --phase impl \
  --run-coder
```

### 4. レビュー（Reviewer）
```bash
# auto_orchestrate.sh が自動でCodexレビューを実行
```

### 5. 完了・アーカイブ
```bash
# タスク完了後、プランは自動的に .agent/archive/plans/ へ移動
```

---

## テスト実行

```bash
# テストスイート実行
./test/run_tests.sh

# 品質ゲート
./scripts/quality_gate.sh
```

---

## コミット規約

```
<type>: <subject>

Types:
- feat: 新機能
- fix: バグ修正
- docs: ドキュメント
- refactor: リファクタリング
- test: テスト追加/修正
- chore: 雑務（ビルド、CI等）
```

---

## 注意事項

1. **mainブランチ直接編集は原則禁止**: Worktreeを使用。例外は `.agent_rules/RULES.md` Phase 1.8 に従う
2. **Codex呼び出し**: 専用ラッパー経由で呼び出す（Coder: `codex-wrapper-high.sh` / `codex-wrapper-medium.sh`, Reviewer: `codex-wrapper-xhigh.sh`）
3. **セッション継続**: API課金なしでコンテキスト保持可能
