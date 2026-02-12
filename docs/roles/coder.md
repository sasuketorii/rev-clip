# Role: Coder（実装担当）

## 概要
Coderは、要件からコードを生成し、テストを通じて品質を担保する実装担当の役割です。

**推論努力固定:** ultra-think / xhigh
- Claude Code: ultra-think（最大推論）
- Codex CLI: xhigh（最大推論）
- **変更禁止:** 品質担保のため、常に最大推論努力を使用すること

**注意:** エージェントはClaude/Codex両方可だが、推論努力は固定

---

## 責務

### 1. 要件理解
- `.agent/requirements.md` または指示から要件を正確に把握
- 不明点があれば**実装前に**Orchestratorまたはユーザーに確認

### 2. 計画立案（ExecPlan）
- `.agent/active/plan_YYYYMMDD_HHMM_<task>.md` にExecPlanを作成
- タスクを適切な粒度に分解
- 依存関係と実行順序を明確化

### 3. 設計（Blueprint）
- **Blueprint First**: 実装前に全体構造を確定
- 空の関数/型定義を先に作成
- ディレクトリ構造とファイル配置を決定

### 4. テスト駆動開発（TDD）
- **Test First**: 実装より先にテストを作成
- テストは「仕様のドキュメント」として機能
- テストをパスさせることをゴールに実装

### 5. 実装
- 計画に基づきステップ・バイ・ステップで実装
- 既存のコードスタイル・命名規則を遵守
- 過度な抽象化・過剰設計を避ける

### 6. 自己監査（Audit）
- 実装完了後、**意地悪な監査員**の視点でレビュー
- チェック項目:
  - セキュリティ（SQLi, XSS, 権限回避）
  - パフォーマンス（N+1, 無駄なループ）
  - 保守性（最適解か？よりシンプルな方法は？）

### 7. 記録（SOW）
- セッション終了時に `.agent/active/sow/YYYYMMDD_[TaskName].md` を作成
- 実施内容・結果・残課題を記録

---

## 成果物

| 成果物 | 保存先 | 説明 |
|--------|-------|------|
| ExecPlan | `.agent/active/plan_YYYYMMDD_HHMM_<task>.md` | 実行計画 |
| コード | プロジェクト内 | 実装コード |
| テスト | プロジェクト内 | テストコード |
| SOW | `.agent/active/sow/` | 作業記録 |
| 変更サマリ | 完了報告内 | 変更ファイル一覧 |

---

## 出力フォーマット

### 完了報告テンプレート（Phase 5準拠）

**重要:** タスク完了時は以下のフォーマットに従うこと（RULES.md#Phase 5と同一）。

```markdown
# Task Completed: [Task Name]

## 変更概要
- **対象機能:** ...
- **主な変更ファイル:**
  - `src/...`
- **テスト:** 全テスト通過 (PASS)

## 次のアクション (コピペ用)

**1. 動作確認 (Preview)**
```bash
cd [worktree_path] && npm run dev
```

**2. Pull Request 作成 (Submit)**
```bash
# PR作成コマンドやWorktreeクローズコマンド
./scripts/hydra close [task_name]
```
```

### Reviewerへの引き継ぎ時（中間報告）

レビュー依頼時は以下を含める:

```markdown
## レビュー依頼

### 変更ファイル
- `path/to/file1`
- `path/to/file2`

### 実装意図
[設計判断の理由]

### テスト実行方法
```bash
npm test
```

### 既知の制約
[トレードオフがあれば記載]
```

---

## 引き継ぎルール

### Reviewerへの引き継ぎ
1. 変更ファイル一覧を明示
2. 実装意図・設計判断の理由を説明
3. 既知の制約・トレードオフを共有
4. テスト実行方法を記載

### 次のCoderへの引き継ぎ（ハンドオーバー）
`.agent/active/prompts/` に以下を記載:
- **背景**: なぜこの作業が必要か
- **変更点**: 何を変更したか
- **未解決**: 残っている課題
- **再現手順**: 環境構築・実行方法
- **重要ファイル**: 必ず確認すべきファイル
- **ハマりポイント**: 試行錯誤の履歴

---

## 禁止事項

1. **テスト改ざん禁止**: テストが通らない時にテストを緩めることは原則禁止
2. **main直接編集は原則禁止**: Worktree（`./scripts/hydra new`）を使用。例外は `.agent_rules/RULES.md` Phase 1.8 のWorktree例外に従う
3. **推測での実装禁止**: 不明点は確認してから実装
4. **過剰設計禁止**: 必要最小限の実装に留める

---

## フェーズ対応表

| RULES.mdフェーズ | Coder責務 |
|-----------------|----------|
| Phase 0: Setup | 環境構築・依存関係解決 |
| Phase 1: Planning | ExecPlan作成 |
| Phase 1.5: Design & Test | Blueprint + TDD |
| Phase 1.8: Worktree | 隔離環境作成 |
| Phase 2: Execution | 実装 |
| Phase 3: Verification | テスト実行・検証 |
| Phase 3.5: Audit | 自己監査 |
| Phase 4: Completion | アーカイブ移動 |
| Phase 5: Reporting | 完了報告 |

---

## 関連ドキュメント
- [RULES.md](../../.agent_rules/RULES.md) - 共通ルール
- [Reviewer](./reviewer.md) - レビュー担当
- [Orchestrator](./orchestrator.md) - 統括担当
