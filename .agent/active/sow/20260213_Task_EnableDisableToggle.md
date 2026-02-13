# SOW: Snippet Editor Enable/Disable Toggle

## 日時
- 2026-02-13

## 許可・前提
- ユーザー明示許可により `feat/enable-disable` で直接作業
- 作業ディレクトリ: `/tmp/revclip-wt-enable`

## 実施内容
1. `RCSnippetEditorWindowController.m` に「有効/無効」ボタンを追加（削除ボタン右隣）
2. 選択中フォルダ/スニペットの `enabled` を反転するトグル処理を追加
3. 選択状態に応じて SF Symbol (`eye` / `eye.slash`) を切替
4. OutlineView の disabled 項目を `secondaryLabelColor` でグレーアウト表示
5. `Localizable.strings`（en/ja）へ `Enable/Disable` 文言を追加

## 検証
- `xcodebuild -project src/Revclip/Revclip.xcodeproj -scheme Revclip -configuration Debug -sdk macosx build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- 結果: `BUILD SUCCEEDED`

## 補足
- メニュー側（`RCMenuManager`）および DB 層（`RCDatabaseManager`）の `enabled` 対応は既存実装済みであることを確認。
