# Handover: Security & Data Hardening 実装

**作成日**: 2026-02-16
**作成者**: Orchestrator (Claude Opus 4.6)
**引継ぎ先**: 次のオーケストレーター（コンテキスト共有なし）

---

## あなたの役割

あなたは **オーケストレーター** です。以下のルールに従ってください:

1. **自分でコード編集しない** — 全ての実装はサブエージェント（Codex xhigh）に委譲
2. **Codex呼び出しはwrapper経由必須** — 直接 `codex exec` を呼ばない
3. **レビュワーのLGTMで完了** — coder修正 → reviewer LGTM のサイクル
4. **メインブランチで作業OK** — ユーザーからの明示的許可あり

### Codex呼び出し方法

```bash
# Coder用（実装）: high effort
cat PROMPT.md | ./scripts/codex-wrapper-high.sh --stdin > output.md

# Reviewer用（レビュー）: xhigh effort
cat PROMPT.md | ./scripts/codex-wrapper-xhigh.sh --stdin > output.md
```

### Claude Code Bash ツールからの呼び出し（run_in_background使用時）

```bash
# 必ず bash -c でラップすること（リダイレクトが引数として解釈されるバグ回避）
bash -c 'cat prompt.md | ./scripts/codex-wrapper-high.sh --stdin > output.md 2>&1'
```

### サブエージェントへのプロンプトに必ず含めること

```markdown
## 許可事項
ユーザーからの明示的許可: メインブランチで作業してOKです。Worktree/ブランチを切る必要はありません。
```

---

## 現在の状態

### 完了済み
- [x] セキュリティ調査（5レーン並列Codex xhigh）
- [x] ExecPlan作成（Rev.3）
- [x] Codex xhigh レビュワーによるプランレビュー → **LGTM取得済み**
- [x] SOW作成
- [x] ハンドオーバー作成（本ファイル）

### 未着手
- [ ] **Phase 1: Data Growth Control** — 実装
- [ ] **Phase 2: Auto-Expiry** — 実装
- [ ] **Phase 3: Panic Button** — 実装
- [ ] **Phase 4: Security Hardening** — 実装
- [ ] **Phase 5: Existing Deletion Enhancement** — 実装
- [ ] 各Phase完了後のCodex xhighレビュー → LGTM取得
- [ ] 全Phase統合後の最終確認

---

## 読むべきファイル（優先順）

| 優先度 | ファイル | 説明 |
|--------|---------|------|
| **必読** | `.agent/active/plan_20260216_security-and-data-hardening.md` | ExecPlan (Rev.3, LGTM済み) — 全Phaseの詳細仕様 |
| **必読** | `.agent/active/sow/20260216_security-and-data-hardening.md` | SOW — 成果物定義、受入基準、実装順序 |
| **必読** | `CLAUDE.md` | エージェント設定 — オーケストレーターのハードルール |
| **必読** | `.agent_rules/RULES.md` | 共通ルール — 全エージェント遵守事項 |
| 参考 | `.agent/PROJECT_CONTEXT.md` | プロジェクト固有コンテキスト |
| 参考 | `.claude/skills/codex-caller/SKILL.md` | Codex呼び出しスキル詳細 |

---

## プロジェクト構造

### リポジトリルート
```
/Users/sasuketorii/dev/Revclip/
```

### Gitブランチ
```
master (現在のブランチ, commit 9b1a907)
```

### ソースコードルート
```
src/Revclip/Revclip/
```

### 主要ファイル（全Phase共通で変更が多いもの）
```
src/Revclip/Revclip/App/RCConstants.h          — 定数宣言（Phase 1,2,3で変更）
src/Revclip/Revclip/App/RCConstants.m          — 定数定義（Phase 1,2,3で変更）
src/Revclip/Revclip/Services/RCDataCleanService.h — クリーンアップAPI（Phase 1,2で変更）
src/Revclip/Revclip/Services/RCDataCleanService.m — クリーンアップ実装（Phase 1,2,4,5で変更）
src/Revclip/Revclip/Managers/RCDatabaseManager.h  — DB API（Phase 2,3で変更）
src/Revclip/Revclip/Managers/RCDatabaseManager.m  — DB実装（Phase 2,3,4で変更）
```

### エージェント成果物
```
.agent/active/plan_20260216_security-and-data-hardening.md  — ExecPlan
.agent/active/sow/20260216_security-and-data-hardening.md   — SOW
.agent/active/prompts/                                       — プロンプト格納先
.claude/tmp/                                                 — 一時ファイル（state.json等）
```

---

## 実装手順の詳細

### 推奨実装順序

ExecPlanには「Phase 1 と Phase 4 は並列実装可能」と記載がありますが、
`RCDataCleanService.m` と `RCDatabaseManager.m` が複数Phaseで競合するため、
**直列実装を推奨**します:

```
Phase 4 → Phase 1 → Phase 2 → Phase 3 → Phase 5
```

### 各Phaseの実装フロー

```
1. プランからPhase仕様を抽出してCoderプロンプトを作成
2. Codex xhigh (coder/high) でコーディング実行
3. Coder出力を確認
4. Codex xhigh (reviewer/xhigh) でレビュー実行
5. LGTM → 次のPhaseへ
   NEEDS_CHANGES → Coderに修正指示 → 3に戻る
6. ユーザーに報告するのは「Coder修正完了 + Reviewer LGTM」のセットのみ
```

### Coderプロンプトのテンプレート

```markdown
# Implementation Task: Phase X - [タスク名]

## 許可事項
ユーザーからの明示的許可: メインブランチで作業してOKです。Worktree/ブランチを切る必要はありません。

## 前提
- Revclip は macOS クリップボードマネージャー（Objective-C）
- 現在のコードは完璧に動作しており、既存動作を壊してはいけない
- ソースコードルート: src/Revclip/Revclip/

## タスク
[ExecPlanから該当Phase仕様をコピー]

## 対象ファイル
[ExecPlanから対象ファイルリストをコピー]

## 仕様
[ExecPlanから仕様をコピー]

## テスト確認事項
- 既存機能（コピー→ペースト、履歴表示、スニペット）が壊れていないこと
- 新機能が仕様通り動作すること
- エッジケースの処理
```

### Reviewerプロンプトのテンプレート

```markdown
# Code Review: Phase X - [タスク名]

## Role
あなたはシニアソフトウェアアーキテクトです。macOS Objective-Cアプリケーションのコード変更をレビューしてください。

## 対象
[変更されたファイルリスト]

## 基準
1. 既存動作が壊れていないか
2. 仕様通りに実装されているか
3. エッジケースが処理されているか
4. メモリリーク/クラッシュのリスクがないか
5. セキュリティ上の問題がないか

## 出力形式
### Review Verdict: LGTM / NEEDS_CHANGES

### Findings
- Severity: Critical/High/Medium/Low/Nit
- Location: ファイル:行番号
- Issue: 問題点
- Suggestion: 修正案
```

---

## 重要な注意事項

### 1. TIFF互換性（Phase 1-2）
**画像本体（`RCClipData.TIFFData`）には一切手を加えない。**
JPEG圧縮はサムネイルのみ。貼り付け経路（`RCClipData` → `NSPasteboardTypeTIFF`）の互換性を壊すと全ユーザーに影響。

### 2. Panicのデッドロック回避（Phase 3）
Panicシーケンス全体を**専用バックグラウンド直列キュー（`panicQueue`）**で実行する。
**メインスレッドからの`dispatch_sync` drainは禁止。**
`RCClipboardService`の`monitoringQueue → main queue`同期呼び出しとの相互待ちでデッドロックする。

### 3. Panic後は常にアプリ終了（Phase 3）
「終了しない」オプションは提供しない。全サービス停止後の復帰は複雑すぎるため、再起動で対応。

### 4. 既存ユーザーへの影響ゼロ
- DBスキーマ変更なし
- 新Preferenceは全てregisterDefaultsで安全初期化
- auto_vacuum移行は初回起動時に透過的実行

### 5. レガシーサムネイル（Rev.3 Low指摘）
パーミッション修復対象に `.thumb`（レガシーサムネイル拡張子）も含めること。
`RCDataCleanService.m` で `.thumb` がレガシーとして扱われている。

### 6. ファイル競合リスク
`RCDataCleanService.m` と `RCDatabaseManager.m` は複数Phaseで変更が入る。
**並列Codex実行する場合はWorktree分離が必要。直列実装なら不要。**

---

## 調査結果サマリ（参考）

5つのCodex xhigh並列調査の結果は以下に保存されています:

| 調査 | 出力ファイル |
|------|------------|
| セキュリティ一般 | `/tmp/codex_security_general.out` |
| データセキュリティ | `/tmp/codex_security_data.out` |
| データ成長 | `/tmp/codex_data_growth.out` |
| Auto-Expiry設計 | `/tmp/codex_auto_expiry.out` |
| Secure Wipe & Panic | `/tmp/codex_secure_wipe.out` |

**注意**: `/tmp/` ファイルはシステム再起動で消える可能性があります。必要な情報はExecPlanとSOWに反映済みです。

---

## 全体像

```
                    調査完了 ✅
                       │
                  ExecPlan Rev.3 ✅
                       │
                  LGTM取得 ✅
                       │
                   SOW作成 ✅
                       │
                ハンドオーバー ✅  ← 今ここ
                       │
          ┌────────────┼────────────┐
          │            │            │
     Phase 4      Phase 1      Phase 2
     Security     DataGrowth   AutoExpiry
          │            │            │
          └────────────┼────────────┘
                       │
                  Phase 3
                  Panic Button
                       │
                  Phase 5
                  Deletion Enhancement
                       │
                  統合テスト
                       │
                  ユーザーへ報告
```

---

## 次のオーケストレーターへの最終メッセージ

1. まず `CLAUDE.md` と `.agent_rules/RULES.md` を読んでプロジェクトのルールを理解してください
2. 次に ExecPlan (`plan_20260216_security-and-data-hardening.md`) を読んで全仕様を把握してください
3. SOW (`sow/20260216_security-and-data-hardening.md`) で受入基準を確認してください
4. Phase 4 から順に、Coder → Reviewer のサイクルで実装を進めてください
5. 各Phase完了時にユーザーへ報告（Coder完了 + Reviewer LGTM のセットで報告）
6. 全Phase完了後に統合レポートをユーザーに提出してください
