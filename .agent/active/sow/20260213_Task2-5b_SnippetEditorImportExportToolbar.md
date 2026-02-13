# SOW: Task 2-5b Snippet Editor Import/Export Toolbar

## 概要
- `RCSnippetEditorWindowController` にインポート/エクスポートボタンを追加し、スニペットエディタから直接入出力可能にした。
- インポートは Clipy 既定ファイル（`~/Library/Application Support/com.clipy-app.Clipy/snippets.xml`）と任意ファイル選択の両方に対応。
- エクスポートは Revclip 独自 XML plist（`.revclipsnippets`）で全件／選択中（フォルダ or スニペット）を出力可能にした。

## 実施内容
- `src/Revclip/Revclip/UI/SnippetEditor/RCSnippetEditorWindowController.m`
  - 下部ボタン列に `インポート` / `エクスポート` を追加
  - SF Symbols:
    - `square.and.arrow.down`
    - `square.and.arrow.up`
  - インポート導線:
    - Clipy既定ファイルが存在する場合: 既定ファイル読み込み or ファイル選択
    - それ以外: `NSOpenPanel` で選択
  - エクスポート導線:
    - 選択中のみ / すべて を選択
    - `NSSavePanel` で `.revclipsnippets` 保存
- `src/Revclip/Revclip/Services/RCSnippetImportExportService.h/.m`
  - Revclip XML plist 形式エクスポートを実装（全件 + 任意フォルダ配列）
  - インポートで以下を受理:
    - Revclip XML plist
    - Clipy 互換 XML（`<folders>/<folder>/<snippets>/<snippet>`）
    - plist由来のフォルダ/スニペット配列
  - `merge:YES` 時は既存優先で重複スキップ（上書きしない）
- `src/Revclip/Revclip/App/RCAppDelegate.m`
  - メニュー経由のインポート/エクスポート拡張子を `revclipsnippets/xml/plist` に調整
- `src/Revclip/Revclip/Resources/en.lproj/Localizable.strings`
- `src/Revclip/Revclip/Resources/ja.lproj/Localizable.strings`
  - 新規UI文言を追加

## 参考調査
- Clipy公開ソース（`/tmp/clipy-src-20260213`）を確認
  - `Clipy/Sources/Snippets/CPYSnippetsEditorWindowController.swift`
  - `Clipy/Sources/Constants.swift`
  - 既存Clipy入出力は `<folders>` ルートのXML構造を利用していることを確認

## 検証結果
- 実行コマンド:
  - `xcodebuild -project src/Revclip/Revclip.xcodeproj -scheme Revclip -configuration Debug -sdk macosx build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- 結果: `BUILD SUCCEEDED`

## 例外・補足
- Worktree作成は省略（ユーザーから現ブランチ直接作業の明示許可あり）。
