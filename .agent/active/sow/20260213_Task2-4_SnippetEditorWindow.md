# SOW: Task 2-4 Snippet Editor Window

## 概要
- `RCSnippetEditorWindowController` と `RCSnippetEditorWindow.xib` を新規追加し、スニペット編集ウィンドウ（左: Outline、右: Editor、下部: Add/Remove/Save）を実装。
- フォルダ/スニペットのCRUD、`NSOutlineView` のドラッグ&ドロップ並べ替え、フォルダ個別ホットキー記録を追加。
- `RCAppDelegate` / `RCMenuManager` に「Edit Snippets...」導線を追加。
- `RCDatabaseManager` に Task 2-4 指定API（`insertSnippet:inFolder:` / `updateSnippet:` / `updateSnippetFolder:`）を追加。

## 実施内容
- `src/Revclip/Revclip/Managers/RCDatabaseManager.h/.m`
  - 追加API:
    - `- (BOOL)updateSnippetFolder:(NSDictionary *)folderDict;`
    - `- (BOOL)insertSnippet:(NSDictionary *)snippetDict inFolder:(NSString *)folderIdentifier;`
    - `- (BOOL)updateSnippet:(NSDictionary *)snippetDict;`
  - 既存 `...withDict:` APIは維持し、追加APIを薄いラッパーとして実装。

- `src/Revclip/Revclip/UI/SnippetEditor/RCSnippetEditorWindowController.h/.m`（新規）
  - singleton `shared`
  - ウィンドウ設定:
    - title: `Snippet Editor`
    - size: `700x500`
    - min: `500x400`
    - resizable
    - `NSWindowCollectionBehaviorMoveToActiveSpace`
    - `releasedWhenClosed = NO`
  - UI構成（コード生成）:
    - `NSSplitView` 左右分割
    - 左: `NSOutlineView`
    - 右: `Title` / `Content (NSTextView)` / `Shortcut (RCHotKeyRecorderView)`
    - 下部: `NSPopUpButton(+)` / `-` / `Save`
  - `NSOutlineViewDataSource/Delegate`:
    - 2レベル（Folder / Snippet）
    - D&D並べ替え（`writeItems`, `validateDrop`, `acceptDrop`）
  - CRUD:
    - Add Folder / Add Snippet / Remove / Save
    - DB永続化 + メニュー再構築
  - ホットキー:
    - フォルダ選択時のみ recorder 表示
    - 記録: `registerSnippetFolderHotKey:forFolderIdentifier:`
    - クリア: `unregisterSnippetFolderHotKey:`

- `src/Revclip/Revclip/UI/SnippetEditor/RCSnippetEditorWindow.xib`（新規）
  - File's Owner: `RCSnippetEditorWindowController`
  - `window` outlet 接続
  - ベースウィンドウ定義を追加（XML手書き）

- `src/Revclip/Revclip/App/RCAppDelegate.m`
  - `#import "RCSnippetEditorWindowController.h"` を追加
  - `- (IBAction)showSnippetEditor:(id)sender` を追加

- `src/Revclip/Revclip/Managers/RCMenuManager.m`
  - Application sectionに `Edit Snippets...` を追加
  - `openSnippetEditor:` を追加し `showSnippetEditor:` を送信

- `.agent/active/plan_20260213_0517_task2-4_snippet-editor-window.md` を追加

## 検証結果
- `cd src/Revclip && xcodegen generate`: 成功
- 構文チェック（PASS）:
  - `xcrun clang ... Revclip/UI/SnippetEditor/RCSnippetEditorWindowController.m`
  - `xcrun clang ... Revclip/Managers/RCMenuManager.m`
  - `xcrun clang ... Revclip/App/RCAppDelegate.m`
  - `xcrun clang ... Revclip/Managers/RCDatabaseManager.m`
- XIB検証（PASS）:
  - `xmllint --noout Revclip/UI/SnippetEditor/RCSnippetEditorWindow.xib`

## 例外・省略
- Worktree作成は省略: ユーザーから「メインブランチで作業してOK」の明示許可あり。
- Blueprint/TDDは省略: ユーザー制約（テスト不要）に従い、構文検証 + XML検証で妥当性を確認。
