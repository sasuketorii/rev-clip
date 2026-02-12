# Primary Directive
- Think in English, interact with the user in Japanese.

# Orchestrator Hard Rules（CRITICAL / MUST FOLLOW）

Orchestrator（統括担当）として動作する場合の**絶対遵守ルール**。

## 実装・編集の禁止
- **コード編集禁止**: `src/`、`test/` 配下のファイルを Edit/Write しない
- **ドキュメント編集禁止**: `docs/` 配下のファイルを Edit/Write しない
- **基盤ファイル変更禁止**: `.agent_rules/`、`.claude/commands/`、`.codex/` を変更しない
- **許可パス以外の書き込み禁止**: 上記「許可される操作」に明記したパス以外への Edit/Write は禁止

## 許可される操作
- **読み取り**: 全ファイルの Read は許可
- **オーケストレーション成果物の作成**:
  - `.agent/active/plan_*.md`（ExecPlan）
  - `.agent/active/prompts/**`（依頼プロンプト）
  - `.agent/active/sow/**`（SOW）
  - `.claude/tmp/**`（state.json 等）
  - `.agent/archive/**`（完了時のアーカイブ移動）

## Codex 呼び出しルール
- **wrapper 経由必須**: `codex exec` を直接呼ばず、必ず専用 wrapper 経由
  - **軽量タスク用**: `./scripts/codex-wrapper-medium.sh` (reasoning effort = medium)
  - **Coder用**: `./scripts/codex-wrapper-high.sh` (reasoning effort = high)
  - **Reviewer用**: `./scripts/codex-wrapper-xhigh.sh` (reasoning effort = xhigh)
- **オプション指定禁止**: `-c model=...`、`-c model_reasoning_effort=...` を付与しない
- **resume 禁止**: `codex resume` はオーケストレーター経由で実行しない
  - **理由**: `codex resume` はTTY（対話型端末）が必須であり、スクリプトやサブプロセスから呼び出すと動作しない
  - **代替手段**: 新規セッション（`codex exec`）で前回の結果をプロンプトに含めて再実行する

## 役割変更ルール
- **明示宣言必須**: 役割変更時は「役割を X → Y に変更します」と宣言してから切替
- **曖昧指示への対応**: 確認質問を挟み、現ロール維持が原則

## 委譲の原則
- **全ての実作業を委譲**: 実装・レビューは以下の手段で委譲
  - **Task ツール（Claude Code 内蔵）**: サブエージェントを起動して委譲
  - **auto_orchestrate.sh**: `./.claude/commands/auto_orchestrate.sh` で自動化フロー実行
  - **依頼プロンプト**: `.agent/active/prompts/` に依頼内容を記載
- **Task 起動時の AGENT_ROLE 明示**: `AGENT_ROLE=coder` 等をプロンプトに記載

## 並列Codex時のコンフリクト管理
- **単一Codex実行時:** ユーザー許可があればメインで作業可、Worktree不要
- **並列Codex実行時:** コンフリクトリスクがある場合は、オーケストレーターの責任でWorktreeを切る指示を出すこと
  - 同一ファイル/ディレクトリへの変更が予想される場合 → Worktree分離必須
  - 独立した機能の並列開発 → メインで作業可
- **判断基準:** コンフリクトリスクの有無はオーケストレーターが判断し、必要に応じてWorktree切り替えを指示

## サブエージェントへのプロンプト明記ルール（CRITICAL）
ユーザーがメインブランチでの作業を許可した場合、**サブエージェント（Codex/Claude Coder等）へのプロンプトに必ず以下を明記すること**：

- **許可の伝達必須:** 「メインで作業可」「Worktree不要」「現在のブランチで直接作業してください」等をプロンプト冒頭に記載
- **記載例:**
  ```
  ## 許可事項
  ユーザーからの明示的許可: メインブランチで作業してOKです。Worktree/ブランチを切る必要はありません。
  ```
- **理由:** サブエージェントはRULES.mdを読み込むが、ユーザー許可の有無はプロンプト経由でしか伝わらない
- **省略禁止:** この明記を省略すると、サブエージェントはデフォルト動作（Worktree作成）を実行する可能性がある

# Agent Configuration

このファイルは、**Claude CLI**の行動を規定する設定ファイルです。
以下の共通ルールファイルは、**本ファイルと同等の権限を持ち、絶対的な遵守が求められる不可分の一部**として読み込んでください。

- **共通ルール:** `.agent_rules/RULES.md` (CRITICAL / MUST FOLLOW)
- **役割定義:** `.agent_rules/RULES.md#13` → `docs/roles/*.md`
- **プロジェクトコンテキスト:** `.agent/PROJECT_CONTEXT.md` (プロジェクト固有設定)

上記共通ルールと本ファイルの内容を統合し、ユーザーの指示を実行してください。

---

# このファイルの範囲

| 含まれる内容 | 参照先 |
|------------|-------|
| Claude CLI設定・構成 | 本ファイル |
| Skills/Hooks/Commands | 本ファイル |
| セッション管理・state.json | 本ファイル |
| **役割（Coder/Reviewer/Orchestrator）** | → `RULES.md#13` + `docs/roles/*.md` |
| **開発プロセス（Phase 0-5）** | → `RULES.md#2` |

---

# エージェント自動化フレームワーク

## 概要

Agent Base は、複数のエージェント（Claude/Codex等）を連携させ、
フェーズ単位（test→impl→review→fix）で自動反復開発を実現する
**エージェント駆動開発基盤**です。

**役割とエージェントの対応:**
| 役割 | エージェント | 推論努力 | Wrapper |
|-----|------------|---------|---------|
| Coder | Claude/Codex両方可 | **ultra-think/high** | `codex-wrapper-high.sh` |
| Coder (軽量) | Claude/Codex両方可 | **ultra-think/medium** | `codex-wrapper-medium.sh` |
| Reviewer | **Codex 固定** | **xhigh 固定** | `codex-wrapper-xhigh.sh` |
| Orchestrator | **Claude Code 固定** | **ultra-think 固定** | - |

詳細は `RULES.md#13` を参照

```
  ┌────────────────┐                     ┌────────────────┐
  │    Claude      │ ──────実装────────► │     Codex      │
  │  (Anthropic)   │                     │    (OpenAI)    │
  │                │ ◄────レビュー────── │                │
  └────────────────┘                     └────────────────┘
         │                                       │
         └───────────────────────────────────────┘
                           │
                           ▼
                  ┌────────────────┐
                  │  品質保証済み   │
                  │    コード      │
                  └────────────────┘
```

---

## フォルダ構成

### エージェント駆動開発の中核: `.agent/`

```
.agent/
├── requirements.md          # 要件定義書（ユーザー投下）
├── PROJECT_CONTEXT.md       # プロジェクト固有コンテキスト
│
├── active/                  # 現在進行中のタスク
│   ├── plan_YYYYMMDD_*.md   # ExecPlan（実装中）
│   ├── sow/                 # セッション別SOW
│   └── prompts/             # ハンドオーバー/レビュー用
│
└── archive/                 # 完了した作業
    ├── plans/               # 完了したプラン
    ├── sow/                 # 完了したSOW
    ├── prompts/             # 完了したハンドオーバー
    ├── feedback/            # 過去のレビューフィードバック
    ├── test/                # アーカイブされたテスト
    └── docs/                # アーカイブされたドキュメント
```

### Claude CLI 設定: `.claude/`

```
.claude/
├── settings.json            # Hook設定
├── commands/
│   ├── auto_orchestrate.sh  # メインオーケストレーター
│   ├── README.md            # コマンド使用ガイド
│   └── lib/                 # 共有ライブラリ
├── hooks/
│   └── codex-review-hook.sh # PostToolUseフック
├── skills/
│   └── auto-orchestrator/   # Skillプラグイン
└── tmp/                     # 一時ファイル
```

---

## Skills マッピング

| Skill | 説明 | 実装パス |
|-------|------|---------|
| **auto-orchestrator** | Coder/Reviewerの並列統合オーケストレーション | `.claude/skills/auto-orchestrator/SKILL.md` |

### auto-orchestrator の呼び出し

```bash
# 標準実行
./.claude/commands/auto_orchestrate.sh \
  --plan .agent/active/plan_*.md \
  --phase impl \
  --run-coder \
  --fix-until high

# セッション継続
./.claude/commands/auto_orchestrate.sh \
  --resume .claude/tmp/task/state.json \
  --continue-session
```

---

## Command Library

### メインコマンド: `auto_orchestrate.sh`

**用途:** Phase ごとの自動反復（test→impl→review→fix）

**基本オプション:**

| オプション | 必須 | 説明 |
|-----------|------|------|
| `--plan PATH` | 新規時 | プランファイルのパス |
| `--phase PHASE` | 新規時 | フェーズ名（test, impl等） |
| `--resume STATE_FILE` | 再開時 | state.json へのパス |
| `--run-coder` | 任意 | Claude Code で Coder を自動起動 |
| `--continue-session` | 任意 | 前回セッションを継続 |
| `--fork-session` | 任意 | 前回セッションから分岐 |
| `--fix-until LEVEL` | 任意 | 修正対象レベル（high/medium/low/all） |
| `--max-iterations N` | 任意 | レビュー反復回数（デフォルト: 5） |
| `--reviewers LIST` | 任意 | レビュワー一覧（デフォルト: safety,perf,consistency） |
| `--reviewer-strategy MODE` | 任意 | fixed / auto（動的選択） |
| `--agent-strategy MODE` | 任意 | fixed / dynamic（複数Coder） |
| `--gate levelA\|B\|C` | 任意 | 品質ゲートレベル |
| `--codex-timeout SECS` | 任意 | Codex タイムアウト（デフォルト: 7200） |
| `--claude-timeout SECS` | 任意 | Claude タイムアウト（デフォルト: 1800） |
| `--recover` | 任意 | stale state をリカバリ |
| `--status` | 任意 | 状態サマリーを表示 |

### ライブラリ関数（lib/）

#### utils.sh - ユーティリティ関数

```bash
# ログ出力
log_info "message"       # [INFO] メッセージ
log_warn "message"       # [WARN] メッセージ
log_error "message"      # [ERROR] メッセージ
log_success "message"    # [OK] メッセージ
die "message"            # [ERROR] で終了（exit 1）

# タイムスタンプ・UUID
get_timestamp            # ISO8601 形式（UTC）
generate_uuid            # UUID v4 生成

# ファイル操作
ensure_cmd "command"     # コマンド存在確認
ensure_dir "path"        # ディレクトリ作成
ensure_file "path"       # ファイル存在確認

# ロック
lock_acquire "lock_file" [timeout]
lock_release "lock_file"

# セキュリティ検証
_validate_identifier "value" "name"  # 英数字・-・_・. のみ許可
```

#### state.sh - 実行状態管理

```bash
# 初期化・読込・保存
state_init "plan_path" "task_name" [output_dir]
state_load "state_file"
state_save

# 値操作（jq パス検証済み）
state_get ".status"
state_set ".status" '"running"'
state_append ".phases" '{...}'

# フェーズ管理
state_upsert_phase "phase_name" [max_iterations]
state_set_phase_status "phase_name" "status"

# セッション記録
state_record_session "session_id" "phase" "iteration"
state_get_last_session [phase]

# その他
state_show_summary
state_is_stale [threshold_secs]
```

#### coder.sh - Claude CLI 制御

```bash
# セッション管理
coder_run "plan" "phase" "output_file"
coder_resume "session_id" "prompt" "output_file"
coder_fork "parent_session_id" "prompt" "output_file"

# 修正実行
coder_run_fix "plan" "phase" "reviews" "iteration" "output_file" "session_id"

# ユーティリティ
coder_build_prompt "plan" "phase" "context"
coder_analyze_task_complexity "plan_path"
```

#### reviewer.sh - Codex CLI 制御

```bash
# 並列レビュー
reviewer_run_all "safety,perf,consistency" "coder_output" "task_tmpdir" "phase"

# 動的選択
reviewer_select_dynamic "coder_output"
reviewer_list_available

# セッション管理（※関数は state.sh に定義）
# reviewer_get_session_id "phase" "reviewer_name"
# reviewer_set_session_id "phase" "iteration" "reviewer_name" "session_id"
```

#### session.sh - セッションライフサイクル

```bash
session_start "prompt"
session_resume "session_id" "prompt"
session_fork "parent_id" "prompt"

_validate_session_id "session_id"  # UUID形式検証
```

#### timeout.sh - タイムアウト管理

```bash
timeout_run "secs" "command" [args...]
```

---

## Hooks 設定

**依存関係:** フックの実行には `jq` が必要です。インストールされていない場合はエラーになります。
- macOS: `brew install jq`
- Linux: `apt install jq` / `yum install jq`

### PostToolUse フック

**設定:** `.claude/settings.json`

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "./.claude/hooks/codex-review-hook.sh"
          }
        ]
      }
    ]
  }
}
```

**動作:** Edit/Write ツール使用後、変更ファイルを `.claude/tmp/review_queue.json` にキュー蓄積

---

## 状態管理（state.json）

**ファイル:** `.claude/tmp/<task_name>/state.json`

**スキーマ概要:**

```json
{
  "version": "1.0.0",
  "task": {
    "id": "uuid",
    "name": "task_name",
    "plan_path": "path/to/plan.md"
  },
  "status": "running|completed|error",
  "phases": [
    {
      "name": "impl",
      "status": "pending|running|review|fixing|completed|escalated",
      "iteration": 1,
      "max_iterations": 5,
      "coder": { "session_id": "...", "output_file": "..." },
      "reviews": [...],
      "fixes": [...]
    }
  ],
  "sessions": { "coder_sessions": [], "reviewer_sessions": [] },
  "quality_gate": { "level": "levelB", "status": "passed|failed" },
  "heartbeat": { "last_updated": "...", "pid": 12345 },
  "error": null
}
```

**用途:**
- 中断→再開時のコンテキスト復元
- Phase ステータス追跡
- セッションID記録
- エラー/エスカレーション情報保存

---

## ワークフロー例

### 標準フロー（全自動）

```bash
# 1. 要件を .agent/requirements.md に記載

# 2. プラン作成
# エージェントが .agent/active/plan_YYYYMMDD_feat-foo.md を生成

# 3. テストフェーズ
./.claude/commands/auto_orchestrate.sh \
  --plan .agent/active/plan_YYYYMMDD_feat-foo.md \
  --phase test \
  --run-coder \
  --gate levelB

# 4. 実装フェーズ
./.claude/commands/auto_orchestrate.sh \
  --plan .agent/active/plan_YYYYMMDD_feat-foo.md \
  --phase impl \
  --run-coder \
  --gate levelB
```

### 中断・再開フロー

```bash
# 前回の state.json から再開
./.claude/commands/auto_orchestrate.sh \
  --resume .claude/tmp/feat-foo/state.json \
  --continue-session

# stale state をリカバリ
./.claude/commands/auto_orchestrate.sh \
  --resume .claude/tmp/feat-foo/state.json \
  --recover

# 状態確認
./.claude/commands/auto_orchestrate.sh \
  --resume .claude/tmp/feat-foo/state.json \
  --status
```

### セッション分岐（異なるアプローチ）

```bash
./.claude/commands/auto_orchestrate.sh \
  --resume .claude/tmp/feat-foo/state.json \
  --fork-session
```

---

## セキュリティ

### 入力検証

- **識別子検証:** `_validate_identifier()` で全入力をチェック
- **jq パス検証:** `_validate_jq_path()` で JSON操作を検証
- **セッション検証:** UUID形式のセッションIDのみ許可

### 保護対象

| 脅威 | 対策 | 実装箇所 |
|-----|------|---------|
| コマンドインジェクション | printf '%s' でのエスケープ | session.sh |
| 引数インジェクション | `--` 引数終端子 | session.sh |
| パストラバーサル | ホワイトリスト検証 | reviewer.sh |
| セッションID偽装 | UUID形式検証 | session.sh |
| 環境変数インジェクション | 数値範囲チェック | session.sh |
| レースコンディション | mkdir ベースロック | auto_orchestrate.sh |
| jq パスインジェクション | ホワイトリストパターン | state.sh |

---

## トラブルシューティング

### Q1. 実行が stale state で止まる

```bash
./.claude/commands/auto_orchestrate.sh \
  --resume .claude/tmp/task/state.json \
  --recover
```

### Q2. 指摘が解消されない（max-iterations 到達）

→ エスカレーションレポートが `.claude/tmp/task/escalation_report_*.md` に生成
→ 手動レビューが必要

### Q3. セッションを分岐したい

```bash
./.claude/commands/auto_orchestrate.sh \
  --resume .claude/tmp/task/state.json \
  --fork-session
```

### Q4. レビュワーを追加したい

```bash
# カスタムレビュワープロンプトを作成
# docs/prompts/ にレビュワープロンプトを追加後

./.claude/commands/auto_orchestrate.sh \
  --plan .agent/active/plan_*.md \
  --phase impl \
  --run-coder \
  --reviewers safety,perf,my_custom_reviewer
```

---

## 関連ドキュメント

| ドキュメント | パス | 説明 |
|------------|------|------|
| 共通ルール | `.agent_rules/RULES.md` | 全エージェント共通ルール |
| プロジェクトコンテキスト | `.agent/PROJECT_CONTEXT.md` | プロジェクト固有設定 |
| 要件定義書 | `.agent/requirements.md` | ユーザー要件の入り口 |
| Skill定義 | `.claude/skills/auto-orchestrator/SKILL.md` | オーケストレーター設計思想 |
| コマンドガイド | `.claude/commands/README.md` | コマンド使用法詳細 |
| Codex設定 | `.codex/config.toml` | Codex CLI設定 |
| セットアップ | `setup/setup_rules.md` | セットアップ手順 |
