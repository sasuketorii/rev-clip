# SOW: Task 2-5 Snippet Import/Export (XML)

## 概要
- Clipy互換XMLのスニペットインポート/エクスポート機能を `RCSnippetImportExportService` として新規実装。
- Import時の `merge` / `replace` 挙動を実装し、エラーコード1001-1005の `NSError` ハンドリングを追加。
- メニューバーに `File` メニューを追加し、`Import Snippets...` / `Export Snippets...` を `RCAppDelegate` から実行可能にした。

## 実施内容
- `src/Revclip/Revclip/Services/RCSnippetImportExportService.h/.m` を新規追加:
  - `shared` singleton
  - Export API:
    - `exportSnippetsAsXMLData:`
    - `exportSnippetsToURL:error:`
  - Import API:
    - `importSnippetsFromData:merge:error:`
    - `importSnippetsFromURL:merge:error:`
  - `NSXMLDocument`/`NSXMLElement` によるXML生成・パース
  - UTF-8 + prettyPrint出力
  - 互換考慮でルート要素は `<snippets>` を正としつつ、旧 `<folders>` も受理
  - `merge:YES` 時は重複identifier（フォルダ/任意snippet identifier）をスキップ
  - `merge:NO` 時は既存スニペットデータを全削除して置換
  - カスタムエラー domain: `com.revclip.snippet-import-export`
  - エラーコード:
    - 1001: File read error
    - 1002: Invalid XML format
    - 1003: Missing required element
    - 1004: File write error
    - 1005: Database error
- `src/Revclip/Revclip/Managers/RCDatabaseManager.h/.m` を更新:
  - `deleteAllSnippetFolders`
  - `snippetFolderExistsWithIdentifier:`
  - `snippetExistsWithIdentifier:`
  - （既存宣言と整合のため）`updateSnippetFolder:(NSDictionary *)` / `insertSnippet:inFolder:` / `updateSnippet:(NSDictionary *)` の定義を明示
- `src/Revclip/Revclip/App/RCAppDelegate.m` を更新:
  - `importSnippets:` / `exportSnippets:` actionを追加
  - `NSOpenPanel`/`NSSavePanel` で `.xml` を選択
  - merge/replace選択アラート
    - `Merge with existing snippets`
    - `Replace all snippets`
  - Import成功後に `RCHotKeyService reloadFolderHotKeys` と `RCMenuManager rebuildMenu` を実行
  - 失敗時は `NSAlert` でエラー表示
- `src/Revclip/Revclip/Resources/MainMenu.xib` を更新:
  - メニューバーに `File` メニュー追加
  - `Import Snippets...` / `Export Snippets...` を `RCAppDelegate` actionへ接続
- `cd src/Revclip && xcodegen generate` を実行し、`Revclip.xcodeproj/project.pbxproj` を更新

## 検証結果
- `xcodegen generate`: 成功
- 構文チェック（PASS）:
  - `RCSnippetImportExportService.m`
  - `RCDatabaseManager.m`
  - `RCAppDelegate.m`
- XIB妥当性チェック（PASS）:
  - `xmllint --noout src/Revclip/Revclip/Resources/MainMenu.xib`

## 例外・省略
- Worktree作成は省略: ユーザーからメインブランチ直接作業の明示許可あり。
- Blueprint/TDDは省略: ユーザー要件で「テスト不要」が明示されているため、構文検証とXIB妥当性検証で確認した。
