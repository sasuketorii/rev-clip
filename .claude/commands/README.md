# .claude/commands

ClaudeCode / Codex のサブスク環境で使うローカルコマンド定義の置き場。
スクリプト化したワークフロー（例: オーケストレーター起動、ログ収集、レビューワイヤ送信）が増えたらここに追加する。

## auto_orchestrate.sh - 完全自動化オーケストレーター

ClaudeCode（Coder）と Codex（Reviewer）を連携させ、要件定義→テスト→実装→レビュー→修正を自動反復するスクリプト。

### 基本的な使い方

```bash
# 1) 作業ブランチとプラン作成
./scripts/hydra new feat-foo

# 2) テストフェーズ（完全自動）
./.claude/commands/auto_orchestrate.sh \
  --plan .agent/plan_YYYYMMDD_feat-foo.md \
  --phase test \
  --run-coder \
  --gate levelB

# 3) 実装フェーズ
./.claude/commands/auto_orchestrate.sh \
  --plan .agent/plan_YYYYMMDD_feat-foo.md \
  --phase impl \
  --run-coder \
  --gate levelB
```

### オプション一覧

| オプション | 説明 |
|-----------|------|
| `--plan PATH` | プランファイルのパス（必須） |
| `--phase PHASE` | フェーズ名: test, impl など（必須） |
| `--run-coder` | ClaudeCode CLIでCoderを自動起動 |
| `--reviewers LIST` | レビュワー一覧（デフォルト: safety,perf,consistency） |
| `--coder-output FILE` | Coder出力ファイル（手動で用意する場合） |
| `--gate levelA\|B\|C` | 品質ゲートのレベル |
| `--max-iterations N` | レビュー反復の最大回数（デフォルト: 5） |

### 動作フロー

1. `--run-coder` 指定時: ClaudeCode CLI でフェーズ別プロンプトを実行
2. Codex で 3 観点（安全/性能/整合）レビューを並列実行
3. `[High]` 指摘がある限り修正→再レビューを反復（最大 5 回）
4. `--gate` 指定時: `scripts/quality_gate.sh` を実行

### 必要な CLI

- `claude` (Claude Code CLI) - `--run-coder` 使用時
- `codex` (Codex CLI) - レビュー実行時

### 入出力ファイル

- 入力: `.agent/plan_*.md`
- 出力: `.claude/tmp/<task>/<phase>_*.md`

## codex CLI 呼び出しガイド（オーケストレーター向け）

**重要:** Codex CLIは必ず専用ラッパー経由で呼び出すこと。
- **Coder用:** `scripts/codex-wrapper-high.sh` (reasoning effort = high)
- **Reviewer用:** `scripts/codex-wrapper-xhigh.sh` (reasoning effort = xhigh)

基本形（標準入力でプロンプトを渡す）:
```bash
# Coder（実装）用
cat PROMPT.md PAYLOAD.md \
  | ./scripts/codex-wrapper-high.sh --stdin \
  > /tmp/output.md

# Reviewer（レビュー）用
cat PROMPT.md PAYLOAD.md \
  | ./scripts/codex-wrapper-xhigh.sh --stdin \
  > /tmp/output.md
```

ポイント
- **モデル・reasoning effort はラッパーで強制固定** (`gpt-5.3-codex` + 役割に応じた effort)。`-c model=...` や `-c model_reasoning_effort=...` は自動的にブロックされる。
- **`-c` オプションは原則禁止**。Wrapper が必要な設定を自動適用するため、追加のオプション指定は不要。
- 入力は必ず `--stdin` で渡す（ファイル名を渡してもコンテキストにならないため）。
- 出力は Markdown で保存し、オーケストレーターが次のエージェントに渡せるパスを明示する。
- エラー時は終了コードをそのまま拾い、上位で再実行する（リトライ回数はオーケストレーター側で制御）。
