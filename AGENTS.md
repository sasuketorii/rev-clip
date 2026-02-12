# Primary Directive
- Think in English, interact with the user in Japanese.

# Agent Configuration

このファイルは、**Codex CLI**の行動を規定する設定ファイルです。
以下の共通ルールファイルは、**本ファイルと同等の権限を持ち、絶対的な遵守が求められる不可分の一部**として読み込んでください。

- **共通ルール:** `.agent_rules/RULES.md` (CRITICAL / MUST FOLLOW)
- **役割定義:** `.agent_rules/RULES.md#13` → `docs/roles/*.md`
- **プロジェクトコンテキスト:** `.agent/PROJECT_CONTEXT.md` (プロジェクト固有設定)

上記共通ルールと本ファイルの内容を統合し、ユーザーの指示を実行してください。

---

# このファイルの範囲

| 含まれる内容 | 参照先 |
|------------|-------|
| Codex CLI設定・構成 | 本ファイル |
| ラッパースクリプト | 本ファイル |
| セッション管理 | 本ファイル |
| **役割（Coder/Reviewer/Orchestrator）** | → `RULES.md#13` + `docs/roles/*.md` |
| **開発プロセス（Phase 0-5）** | → `RULES.md#2` |

---

# Codex CLI 設定

## フォルダ構成

```
.codex/
└── config.toml          # Codex CLI設定ファイル
```

## config.toml 設定内容

```toml
sandbox_mode = "workspace-write"
approval_policy = "on-failure"
model = "gpt-5.3-codex"
model_reasoning_effort = "xhigh"

[features]
web_search_request = true
rmcp_client = true

[sandbox_workspace_write]
network_access = true
```

### 設定項目の説明

| 項目 | 値 | 説明 |
|-----|---|------|
| `sandbox_mode` | `workspace-write` | ワークスペースへの書き込みを許可 |
| `approval_policy` | `on-failure` | 失敗時のみ承認を要求 |
| `model` | `gpt-5.3-codex` | 使用モデル（**変更禁止**） |
| `model_reasoning_effort` | `xhigh` | 推論努力レベル（**変更禁止**） |
| `web_search_request` | `true` | Web検索機能を有効化 |
| `rmcp_client` | `true` | MCPクライアント機能を有効化 |
| `network_access` | `true` | ネットワークアクセスを許可 |

---

# ラッパースクリプト

## scripts/codex-wrapper-high.sh（Coder用）

**目的:** Coder用のモデル設定強制固定（reasoning effort = high）

実装タスクにおいてコスト・速度のバランスを取る。

### 使用方法

```bash
# 標準的な使用（stdin入力）
cat prompt.md | ./scripts/codex-wrapper-high.sh --stdin > output.md

# リダイレクト入力
./scripts/codex-wrapper-high.sh --stdin < input.md > output.md
```

## scripts/codex-wrapper-xhigh.sh（Reviewer用）

**目的:** Reviewer用のモデル設定強制固定（reasoning effort = xhigh）

レビューの品質を最大化するため、最高の推論レベルを使用。

### 使用方法

```bash
# 標準的な使用（stdin入力）
cat prompt.md | ./scripts/codex-wrapper-xhigh.sh --stdin > output.md

# リダイレクト入力
./scripts/codex-wrapper-xhigh.sh --stdin < input.md > output.md
```

### 機能（両ラッパー共通）

1. **モデル強制固定**: `-c model=...` オプションを自動除去
2. **推論努力強制固定**: `-c model_reasoning_effort=...` を自動除去
3. **監査ログ**: 使用モデルと設定をstderrに出力
4. **セッション管理**: `--resume` によるセッション継続をサポート（**手動実行のみ**、TTY必須）

### 禁止事項

```bash
# NG: 直接 codex を呼ぶ
codex exec --stdin < prompt.md

# NG: モデルを上書きする
codex exec -c model=gpt-5.1-max --stdin < prompt.md

# OK: ラッパー経由で呼ぶ（Coder用）
./scripts/codex-wrapper-high.sh --stdin < prompt.md

# OK: ラッパー経由で呼ぶ（Reviewer用）
./scripts/codex-wrapper-xhigh.sh --stdin < prompt.md
```

---

# セッション管理

## セッションID

Codexのセッションは自動的にUUID形式で管理される。

```
session id: 019b88c1-73c0-7f00-a890-151d884233e9
```

## セッション再開（制限事項）

**重要:** `codex resume` はインタラクティブTTYが必須です。

| 実行方法 | 動作 |
|---------|-----|
| ターミナルから直接実行 | ✅ 動作する |
| オーケストレーター/スクリプト経由 | ❌ `stdin is not a terminal` エラー |
| 擬似TTY（script/expect） | ❌ `cursor position could not be read` エラー |

### 手動実行（ターミナルから直接）
```bash
./scripts/codex-wrapper-high.sh --resume 019b88c1-73c0-7f00-a890-151d884233e9 "続きの指示"
```

### オーケストレーター経由での運用
オーケストレーターからは常に**新規セッション**（`codex exec`）で実行し、前回のコンテキストはプロンプトに含めてください。

---

# 役割との関係

**役割とエージェントの対応:**

| 役割 | Codexでの実行 | 推論努力 | Wrapper |
|-----|-------------|---------|---------|
| **Coder** | 可能 | **ultra-think/high** | `codex-wrapper-high.sh` |
| **Reviewer** | **固定** | **xhigh 固定** | `codex-wrapper-xhigh.sh` |
| **Orchestrator** | 不可 | **ultra-think 固定** | - |

役割の詳細は以下を参照:
- `docs/roles/coder.md` - Coder詳細ワークフロー
- `docs/roles/reviewer.md` - Reviewer詳細ワークフロー
- `docs/roles/orchestrator.md` - Orchestrator詳細ワークフロー

---

# 出力フォーマット

## レビュー時（Reviewer役割）

Reviewer役割を担当する場合は、`docs/roles/reviewer.md` の出力フォーマットに**厳密に従うこと**。

詳細は → `docs/roles/reviewer.md#出力フォーマット（必須）`

---

# トラブルシューティング

## Q1. codex コマンドが見つからない

```bash
# インストール確認
which codex

# インストール
npm install -g @openai/codex
```

## Q2. モデル設定が反映されない

→ 必ず `scripts/codex-wrapper-high.sh` または `codex-wrapper-xhigh.sh` 経由で呼び出す

## Q3. MCP接続エラー

```
mcp: supabase failed: MCP client for `supabase` failed to start
```

→ MCPサーバーの認証トークンを確認

---

# 関連ドキュメント

| ドキュメント | パス | 説明 |
|------------|------|------|
| 共通ルール | `.agent_rules/RULES.md` | 全エージェント共通ルール |
| 役割定義 | `docs/roles/*.md` | Coder/Reviewer/Orchestrator |
| プロジェクトコンテキスト | `.agent/PROJECT_CONTEXT.md` | プロジェクト固有設定 |
| Claude CLI設定 | `CLAUDE.md` | Claude固有設定 |
