---
name: codex-caller
description: Call Codex CLI correctly. Use when you need to run Codex for any purpose (coding, reviewing, etc.). Triggers codex, コーデックス.
allowed-tools: Read, Bash, Grep, Glob
---

# Skill: Codex Caller

Codex CLI の正しい呼び出し方。実装とレビューで使用するラッパーが異なる。

## 目的

セッションが長くなっても Codex の呼び出し方を忘れないよう、正しい手順を永続化する。

## これだけ覚える

```bash
# 軽量タスク（ドキュメント生成、簡易修正）用: medium effort
cat PROMPT.md PAYLOAD.md | ./scripts/codex-wrapper-medium.sh --stdin > output.md

# Coder（実装）用: high effort
cat PROMPT.md PAYLOAD.md | ./scripts/codex-wrapper-high.sh --stdin > output.md

# Reviewer（レビュー）用: xhigh effort
cat PROMPT.md PAYLOAD.md | ./scripts/codex-wrapper-xhigh.sh --stdin > output.md
```

違うのはプロンプトの中身と使用するラッパー。役割に応じて適切なラッパーを選択する。

## Worktree許可の伝達（オーケストレーター向け）

ユーザーがメインブランチでの作業を許可した場合、**プロンプトに必ず許可を明記すること**。

```markdown
## 許可事項
ユーザーからの明示的許可: メインブランチで作業してOKです。Worktree/ブランチを切る必要はありません。
```

**理由:** Codex は RULES.md を読み込むが、ユーザー許可の有無はプロンプト経由でしか伝わらない。省略するとデフォルト動作（Worktree作成）を実行する可能性がある。

## Codex 呼び出しルール（CRITICAL）

### 1. Wrapper 経由必須

**絶対に直接 `codex exec` を呼ばないこと。**

```bash
# ✅ 正しい呼び出し方（Coder用）
cat prompt.md payload.md \
  | ./scripts/codex-wrapper-high.sh --stdin \
  > output.md

# ✅ 正しい呼び出し方（Reviewer用）
cat prompt.md payload.md \
  | ./scripts/codex-wrapper-xhigh.sh --stdin \
  > output.md

# ❌ 間違い（直接呼び出し禁止）
codex exec -c model=gpt-5.3-codex prompt.md
```

**理由:**
- Wrapper が `model=gpt-5.3-codex` と適切な `model_reasoning_effort` を強制適用
- Coder用: `high` (コスト・速度のバランス)
- Reviewer用: `xhigh` (最高品質レビュー)
- 誤ったモデル指定を自動的にブロック

### 2. `-c` オプション禁止

**`-c` オプションは原則禁止です。** Wrapper が `model=...` と `model_reasoning_effort=...` を自動的にブロックしますが、運用上は `-c` オプション自体を使用しないルールとします。

```bash
# ✅ 正しい（オプション指定なし）
./scripts/codex-wrapper-high.sh --stdin
./scripts/codex-wrapper-xhigh.sh --stdin

# ❌ 間違い（model/effort はブロックされる）
./scripts/codex-wrapper-high.sh --stdin -c model=gpt-4
./scripts/codex-wrapper-xhigh.sh --stdin -c model_reasoning_effort=low

# ❌ 間違い（他の `-c` も原則禁止）
./scripts/codex-wrapper-high.sh --stdin -c temperature=0.5
```

**Wrapper のログ出力例:**
```
[codex-wrapper-high] WARN: Blocked override attempt: -c model=gpt-4
[codex-wrapper-high] INFO: Model: gpt-5.3-codex
[codex-wrapper-high] INFO: Reasoning Effort: high
```

### 3. Resume の制限

`codex resume` は TTY が必要なため、**オーケストレーター経由では使用不可。手動 TTY 操作なら使用可能。**

```bash
# ❌ オーケストレーター経由（自動化スクリプト内）では使用不可
# auto_orchestrate.sh 内での呼び出しなど
./scripts/codex-wrapper-high.sh --resume <session_id>

# ✅ 手動 TTY 操作時のみ使用可能
# ターミナルで直接実行する場合（Wrapper 経由、TTY 必須）
./scripts/codex-wrapper-high.sh --resume <session_id>
```

**注:** 手動操作時も Wrapper 経由**必須**。TTY 必須のため自動化フローには組み込めません。

**オーケストレーター経由の代替案:**
- 新しいセッションで同じプロンプトを再実行
- 新規 `exec` で前回の結果をプロンプトに含めて再実行する（必要に応じて `.agent/active/prompts/` を使用）
- State を `.claude/tmp/` に保存して継続性を維持

### 4. 標準入力でプロンプトを渡す

ファイル名を引数で渡してもコンテキストにならないため、必ず `--stdin` を使用します。

```bash
# ✅ 正しい（標準入力経由）
cat prompt.md context.md | ./scripts/codex-wrapper-high.sh --stdin > output.md

# ❌ 間違い（ファイル名を渡してもコンテキストにならない）
./scripts/codex-wrapper-high.sh prompt.md context.md > output.md
```

---

## 使用例

### 実装タスク（Coder用: high）

```bash
cat .agent/active/prompts/impl_task.md context.md \
  | ./scripts/codex-wrapper-high.sh --stdin \
  > .claude/tmp/impl_output.md
```

### レビュータスク（Reviewer用: xhigh）

```bash
cat docs/prompts/reviewer_safety.md changes.diff \
  | ./scripts/codex-wrapper-xhigh.sh --stdin \
  > .claude/tmp/review_safety.md
```

### 修正タスク（Coder用: high）

```bash
cat .agent/active/prompts/fix_task.md review_feedback.md \
  | ./scripts/codex-wrapper-high.sh --stdin \
  > .claude/tmp/fix_output.md
```

### 並列レビュー実行（Reviewer用: xhigh）

```bash
# 複数のレビューを同時実行
cat docs/prompts/reviewer_safety.md code.diff \
  | ./scripts/codex-wrapper-xhigh.sh --stdin \
  > review_safety.md &

cat docs/prompts/reviewer_perf.md code.diff \
  | ./scripts/codex-wrapper-xhigh.sh --stdin \
  > review_perf.md &

wait
```

### Claude Code Bash ツール（run_in_background）からの呼び出し

Claude Code の Bash ツールで `run_in_background: true` を使う場合、**リダイレクト（`>`, `2>`）がシェル構文として解釈されず、codex の引数として渡されるバグが発生する。** 必ず `bash -c '...'` でラップすること。

```bash
# ✅ 正しい（bash -c でラップ）
bash -c 'cat prompt.md payload.md | ./scripts/codex-wrapper-high.sh --stdin > output.md 2>&1'

# ✅ 正しい（複数レーン並列 — 各レーンを個別の Bash ツール呼び出しで実行）
# Lane A:
bash -c 'cat lane_a.md | ./scripts/codex-wrapper-medium.sh --stdin > lane_a_output.md 2>&1'
# Lane B:
bash -c 'cat lane_b.md | ./scripts/codex-wrapper-medium.sh --stdin > lane_b_output.md 2>&1'

# ❌ 間違い（bash -c なしだとリダイレクトが引数として解釈される）
cat prompt.md | ./scripts/codex-wrapper-high.sh --stdin > output.md 2> error.log
```

**なぜ必要か:**
- Bash ツールの `run_in_background` はコマンドをサブプロセスで実行するため、シェルのリダイレクト構文が正しくパースされないケースがある
- `bash -c` で明示的にシェルを介すことで、`>`, `2>`, `|` が確実にシェル構文として処理される
- `2>&1` で stderr も stdout に統合し、出力ファイルに全ログを集約する

**ターミナル直接実行との違い:**
- ターミナルで直接実行する場合は `bash -c` ラップ不要（シェルが直接解釈するため）
- Bash ツール（`run_in_background: false`）の場合も通常は不要だが、安全のため `bash -c` ラップを推奨

---

## トラブルシューティング

### Q1. Codex がタイムアウトする

```bash
# タイムアウトを延長（デフォルト: 7200秒）
timeout 10800 ./scripts/codex-wrapper-high.sh --stdin < input.md > output.md

# macOS の場合: brew install coreutils
gtimeout 10800 ./scripts/codex-wrapper-high.sh --stdin < input.md > output.md
```

### Q2. 出力が空になる

```bash
# ❌ 間違い（ファイル名を渡してもコンテキストにならない）
./scripts/codex-wrapper-high.sh --stdin prompt.md

# ✅ 正しい（標準入力で渡す）
cat prompt.md | ./scripts/codex-wrapper-high.sh --stdin
```

### Q3. Wrapper が model オプションをブロックする

正常動作です。Wrapper が適切な設定を強制適用します。

```bash
# ❌ ブロックされる
./scripts/codex-wrapper-high.sh --stdin -c model=gpt-4

# ✅ オプションなしで実行
./scripts/codex-wrapper-high.sh --stdin
```

### Q4. プロンプトの書き方がわからない

プロンプトは明確に。以下を含める:

- 何をするか（目的）
- 対象ファイル
- 制約条件
- 期待する出力形式

詳細は `docs/prompts/README.md` 参照。

### Q5. run_in_background で `2>` がエラーになる

`bash -c` でラップしていない。「Claude Code Bash ツールからの呼び出し」セクションを参照。

```bash
# ❌ リダイレクトが引数として解釈される
cat prompt.md | ./scripts/codex-wrapper-high.sh --stdin > out.md 2> err.log

# ✅ bash -c でラップ
bash -c 'cat prompt.md | ./scripts/codex-wrapper-high.sh --stdin > out.md 2>&1'
```

### Q6. Coder と Reviewer でどちらのラッパーを使うべきか

| 役割 | ラッパー | Reasoning Effort | 用途 |
|-----|---------|------------------|------|
| 軽量タスク | `codex-wrapper-medium.sh` | medium | ドキュメント生成、簡易修正 |
| Coder | `codex-wrapper-high.sh` | high | 実装・修正タスク |
| Reviewer | `codex-wrapper-xhigh.sh` | xhigh | レビュータスク |

- **Coder:** コスト・速度のバランスを取りたい実装作業
- **Reviewer:** 最高品質のレビューが必要な場合

---

## 関連ドキュメント

| ドキュメント | パス | 説明 |
|------------|------|------|
| Codex Wrapper (軽量) | `scripts/codex-wrapper-medium.sh` | 軽量タスク用 Wrapper |
| Codex Wrapper (Coder) | `scripts/codex-wrapper-high.sh` | Coder用 Wrapper |
| Codex Wrapper (Reviewer) | `scripts/codex-wrapper-xhigh.sh` | Reviewer用 Wrapper |
| コマンドガイド | `.claude/commands/README.md` | Codex 呼び出し方法 |
| Auto Orchestrator Skill | `.claude/skills/auto-orchestrator/SKILL.md` | オーケストレーター設計 |
| プロジェクトルール | `.agent_rules/RULES.md` | 共通ルール |
| エージェント設定 | `CLAUDE.md` | Codex 呼び出しルール |
| Coder ロール定義 | `docs/roles/coder.md` | Coder の責務詳細 |
| Reviewer ロール定義 | `docs/roles/reviewer.md` | Reviewer の責務詳細 |

## Progressive Disclosure リンク

詳細が必要な場合は以下を参照:

- **Wrapper 実装詳細 (軽量):** `scripts/codex-wrapper-medium.sh`
- **Wrapper 実装詳細 (Coder):** `scripts/codex-wrapper-high.sh`
- **Wrapper 実装詳細 (Reviewer):** `scripts/codex-wrapper-xhigh.sh`
- **オーケストレーター詳細:** `.claude/commands/auto_orchestrate.sh`
- **State 管理:** `.claude/commands/lib/state.sh`
- **Coder 制御:** `.claude/commands/lib/coder.sh`
- **Reviewer 制御:** `.claude/commands/lib/reviewer.sh`
- **セッション管理:** `.claude/commands/lib/session.sh`
