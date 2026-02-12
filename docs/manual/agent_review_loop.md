# エージェントレビュー反復ワークフロー（Claude/Codex）

## 目的
本ドキュメントは、**Agent A（Coder）→ Agent B（Reviewer）→ 修正 → 再レビュー**を
**合格（LGTM）するまで反復**する標準ワークフローを、実運用に即して定義する。

## 役割と固定ルール
- **Agent A（Coder）:** Claude または Codex（実装担当）
- **Agent B（Reviewer）:** **Codex 固定 / xhigh 固定**
- **Orchestrator:** **Claude Code 固定 / Opus ultra-think 固定**（統括・進行管理）

詳細は以下を参照:
- `docs/roles/coder.md`
- `docs/roles/reviewer.md`
- `docs/roles/orchestrator.md`

## 標準フロー（反復ループ）

```
1) Coder (Claude/Codex) が実装
     ↓
2) Codex レビュワー **複数並列** 実行（毎回新規セッション）
   - デフォルト: safety, perf, consistency
   - --reviewers で変更可能
     ↓
3) fix-until 以上の指摘なし → 完了
     ↓
4) 指摘あり:
   - --run-coder 指定時 → Coder が自動修正 → 再レビュー（2 へ戻る）
   - --run-coder なし → paused（手動修正待ち）
     ↓
5) max_iterations 到達 → エスカレーション（人間介入要求）
```

### フロー詳細

| ステップ | 動作 | 次の遷移 |
|---------|------|---------|
| 1. 実装 | Coder が Plan に従って実装 | → 2 |
| 2. レビュー | 複数レビュワーが並列実行、結果集約 | → 3 or 4 |
| 3. 完了判定 | `[fix-until]` 以上の指摘なし | → 完了 |
| 4a. 自動修正 | `--run-coder` 時、指摘を反映 | → 2 |
| 4b. 手動待ち | `--run-coder` なし、paused 状態 | → 中断 |
| 5. エスカレーション | max_iterations 到達、レポート生成 | → 失敗 |

## 事前準備（必須）
1. **Worktree 作成（原則必須）**  
   `./scripts/hydra new <task-name>`
2. **ExecPlan（複雑タスクのみ）**  
   `.agent/active/plan_YYYYMMDD_HHMM_<task>.md`
3. **Codex 実行は必ずラッパー経由**
   - Coder用: `scripts/codex-wrapper-high.sh`
   - Reviewer用: `scripts/codex-wrapper-xhigh.sh`

## 実行ステップ（詳細）

### 1) 実装フェーズ（Agent A）
- 変更実装
- テスト実行（必要な範囲）
- 監査（意地悪な監査員視点）
- SOW 作成: `.agent/active/sow/`

### 2) レビューフェーズ（Agent B）
- **複数の Codex レビュワーが並列実行**
  - デフォルト: `safety`, `perf`, `consistency`
  - `--reviewers` オプションで変更可能
  - `--reviewer-strategy auto` で動的選択（コード内容に応じて最適なレビュワーを選択）
- **常に新規セッションで実行**（`codex resume` は TTY 必須のためオーケストレーター経由では使用不可）
- 出力は `docs/roles/reviewer.md` の形式に準拠
- 結果は state.json で管理され、重大度別にカウント
  - `[High]`: ブロッカー（必ず修正が必要）
  - `[Medium]`: 推奨修正
  - `[Low]`: 軽微な指摘

### 3) 修正フェーズ（Agent A）
- `--run-coder` 指定時: Coder が自動で指摘内容を反映
- `--run-coder` なし: `paused` 状態となり、手動修正を待機
- 変更点を明確化
- 必要に応じてテスト再実行

### 4) 再レビューフェーズ（Agent B）
- **常に新規セッションで再レビュー**（`codex resume` は TTY 必須のためオーケストレーター経由では使用不可）
- 前回レビュー結果はプロンプトに含めてコンテキストを引き継ぐ
- `--fix-until` で指定したレベル以上の指摘がなくなるまで反復
  - `high`: `[High]` のみ修正（デフォルト: `all`）
  - `medium`: `[High]` + `[Medium]` を修正
  - `low` / `all`: すべての指摘を修正

## 状態管理
進捗は `.claude/tmp/<task>/state.json` で管理される。

### ステータス一覧

| status | 意味 | 次のアクション |
|--------|------|---------------|
| `running` | 実行中 | 自動継続 |
| `paused` | 手動修正待ち | 修正後、`--resume` で再開 |
| `completed` | 正常完了 | なし |
| `failed` | 失敗（エスカレーション含む） | レポート確認、手動対応 |
| `interrupted` | 中断（シグナル受信） | `--resume` で再開 |
| `recovered` | リカバリ済み | `--resume` で再開 |

### フェーズステータス

| phase.status | 意味 |
|--------------|------|
| `pending` | 未開始 |
| `running` | Coder 実行中 |
| `review` | レビュー実行中 |
| `fixing` | 修正実行中 |
| `completed` | 完了 |
| `escalated` | エスカレーション済み |
| `failed` | 失敗 |

### state.json 例:
```json
{
  "status": "running",
  "task": {
    "name": "feat-foo",
    "plan_path": ".agent/active/plan_YYYYMMDD_feat-foo.md"
  },
  "phases": [
    {
      "name": "impl",
      "status": "review",
      "iteration": 2,
      "max_iterations": 5,
      "reviews": [
        {
          "iteration": 1,
          "has_blockers": true,
          "severity_counts": {"high": 2, "medium": 3, "low": 1}
        }
      ]
    }
  ]
}
```

## Codex セッション運用ルール
**重要:** `codex resume` は廃止済み。オーケストレーター経由では常に新規セッション（`codex exec`）で実行する。

### 運用ルール
1. **Codex レビュワーは常に新規セッションで実行**
2. **コンテキスト引き継ぎはプロンプト内で明示的に行う**（前回レビュー結果を含める等）
3. **`codex resume` は手動実行（ターミナル直接）でのみ使用可能**

### Codex 未インストール時の挙動
`codex` CLI が見つからない場合、**レビュー反復はスキップ**される。

```
[WARN] codex CLI が見つかりません。レビュー反復をスキップします。
```

この場合、Coder の出力のみで完了となる。Codex をインストールするには:
```bash
# Codex CLI のインストール
npm install -g @openai/codex
```

## 合格条件（LGTM）
`--fix-until` で指定したレベル以上の指摘がなくなった時点で完了。

| --fix-until | 合格条件 |
|-------------|---------|
| `high` | `[High]` が 0 件 |
| `medium` | `[High]` + `[Medium]` が 0 件 |
| `low` / `all` | すべての指摘が 0 件（または "No issues found"） |

指摘が残る場合は **必ず修正 → 再レビュー** に戻る。

## セッション終了条件
**修正と再レビューで合格（LGTM）した時点で初めてセッションを閉じる。**  
レビュー未通過の状態では、セッションを閉じずに反復を継続する。

例外（やむを得ない中断）:
- タイムアウトや環境障害で継続不能になった場合
- ユーザーが明示的に中断を指示した場合

## エスカレーション条件
以下は Orchestrator がユーザーへ確認・判断を求める条件:

### 自動エスカレーション
- **max_iterations 到達**: デフォルト 5 回、`--max-iterations` で変更可能
  - エスカレーションレポートが自動生成される
  - レポート: `.claude/tmp/<task>/<phase>_escalation_report_<timestamp>.md`

### 手動エスカレーション
- **仕様が曖昧で合意が取れない**
- **技術的に解決不能**
- **構造的/アーキテクチャ上の問題で自動修正不可**

### エスカレーションレポートの内容
```
# Escalation Report

## Quick Summary
| Severity | Count |
|----------|-------|
| [High]   | N     |
| [Medium] | N     |
| [Low]    | N     |

## Context
- Phase: impl
- Iterations Attempted: 5 / 5
- Status: FAILED - Issues remain after maximum iterations

## Remaining Issues
（未解決の指摘一覧）

## Recommendation
Human intervention required.
```

## 成果物（運用で残すもの）
- ExecPlan: `.agent/active/plan_YYYYMMDD_HHMM_<task>.md`
- SOW: `.agent/active/sow/`
- Coder 出力: `.claude/tmp/<task>/<phase>_coder.md`
- 修正出力: `.claude/tmp/<task>/<phase>_coder_fix<N>.md`
- レビュー出力: `.claude/tmp/<task>/<phase>_reviews.md`（集約済み）
- 個別レビュー: `.claude/tmp/<task>/<phase>_review_<reviewer>.md`
- エスカレーションレポート: `.claude/tmp/<task>/<phase>_escalation_report_<timestamp>.md`
- state.json: `.claude/tmp/<task>/state.json`

## コマンドオプション一覧

| オプション | 説明 | デフォルト |
|-----------|------|-----------|
| `--plan PATH` | プランファイルのパス | 必須（新規時） |
| `--phase PHASE` | フェーズ名（test, impl 等） | 必須（新規時） |
| `--resume STATE_FILE` | state.json から再開 | - |
| `--run-coder` | Coder を自動起動 | false |
| `--reviewers LIST` | レビュワー一覧 | `safety,perf,consistency` |
| `--reviewer-strategy MODE` | `fixed` / `auto` | `fixed` |
| `--fix-until LEVEL` | 修正対象レベル | `all` |
| `--max-iterations N` | 反復上限 | `5` |
| `--gate LEVEL` | 品質ゲート | - |
| `--continue-session` | 前回セッション継続 | false |
| `--fork-session` | 前回セッション分岐 | false |
| `--recover` | stale state リカバリ | false |
| `--status` | 状態サマリー表示 | false |
