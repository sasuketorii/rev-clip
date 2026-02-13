# ExecPlan: Task 2-8 メニュー高度機能

## 目的
- `RCMenuManager` のメニュー表示を強化し、Task 2-8 の要件（サムネイル、カラーコード、ツールチップ、数字キーEquivalent）を反映する。

## スコープ
- 対象: `src/Revclip/Revclip/Managers/RCMenuManager.m`
- 対象外: ほかクラスの仕様変更、テスト方針変更

## 実装ステップ
1. 既存 `RCMenuManager` の機能実装状況を確認し、未実装/仕様差分を特定する。
2. `clipMenuItemForClipItem:` と `imageForClipItem:` を中心に、以下を適用する。
   - `kRCShowImageInTheMenuKey` + TIFFData からのサムネイル表示
   - `kRCThumbnailWidthKey` / `kRCThumbnailHeightKey` のサイズ反映
   - `kRCPrefShowColorPreviewInTheMenu` + `isColorCode` 時の 16x16 カラースウォッチ
   - `kRCAddNumericKeyEquivalentsKey` 時の先頭9件 `1-9` 割り当て
   - ツールチップ仕様との整合確認
3. `xcodegen generate` を実行してプロジェクト生成を更新する。
4. `clang -fsyntax-only` で `RCMenuManager.m` の構文チェックを行う。
5. SOW に実施内容と検証結果を記録する。

## 例外運用
- Worktree 作成は省略（ユーザーからメインブランチ作業の明示許可あり）。
- Blueprint/TDD は省略（既存実装への差分修正タスクであり、構文検証を実施）。
