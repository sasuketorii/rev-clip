# ExecPlan: Task 2-5 Snippet Import/Export (XML)

## 背景
Clipy互換XMLによるスニペット移行機能を追加し、Revclip内でのスニペット管理と他ツール間のデータ連携を可能にする。

## スコープ
- `RCSnippetImportExportService.h/.m` の新規追加
- 既存DB APIの最小拡張（import時のreplace/重複判定のため）
- メニューバー `File` メニューへのImport/Export導線追加（MainMenu.xib + AppDelegate）

## 実装ステップ
1. エラー定義とXML入出力ロジックを持つ `RCSnippetImportExportService` を実装
2. `RCDatabaseManager` に以下を追加
   - スニペット全削除
   - スニペットidentifier存在確認
   - スニペットフォルダidentifier存在確認
3. `RCAppDelegate` に Import/Export アクションを追加
4. `MainMenu.xib` に `File` メニューと `Import Snippets...` / `Export Snippets...` を追加
5. `xcodegen generate` + 構文チェック + SOW記録

## 検証
- `cd src/Revclip && xcodegen generate`
- `xcrun clang -fobjc-arc -fsyntax-only ... RCSnippetImportExportService.m`
- `xcrun clang -fobjc-arc -fsyntax-only ... RCAppDelegate.m`

## 省略方針
- Worktree作成は省略: ユーザーからメインブランチ作業の明示許可あり。
- Blueprint/TDDは省略: ユーザー要件で「テスト不要」が明示されているため、実装後の構文検証で品質確認する。
