# SOW: Task 2-8 メニュー高度機能

## 概要
- `RCMenuManager` のメニューアイテム生成を調整し、Task 2-8 要件のうち未一致だった仕様を反映。
- サムネイル画像表示のサイズ参照を `kRCThumbnailWidthKey` / `kRCThumbnailHeightKey` に統一。
- カラーコードプレビューを 16x16 固定スウォッチ化。
- 数字キーEquivalentを先頭9件の `1-9`（修飾キーなし）に統一。

## 実施内容
- `src/Revclip/Revclip/Managers/RCMenuManager.m` を更新:
  - `kRCMaximumNumberedMenuItems` を `9` に変更。
  - `imageForClipItem:clipData:` 内のカラーコード分岐を 16x16 固定で `NSImage+Color` 生成に変更。
  - 画像プレビュー分岐で `kRCThumbnailWidthKey` / `kRCThumbnailHeightKey` を参照し、`resizedImageToFitSize:` でリサイズ。
  - TIFFData 優先で `NSImage` を生成し、未取得時のみ `thumbnailPath` をフォールバック使用。
  - `numericKeyEquivalentForGlobalIndex:` を先頭9件の `1-9` 返却に簡素化。
- 既存で実装済みだった以下は維持:
  - `kRCShowToolTipOnMenuItemKey` + `kRCMaxLengthOfToolTipKey` のツールチップ設定
  - `item.keyEquivalentModifierMask = 0` の無修飾キー設定

## 検証結果
- `xcodegen generate`: 成功
  - 実行ディレクトリ: `src/Revclip`
- 構文チェック（PASS）:
  - `cd src/Revclip && SDKROOT=$(xcrun --sdk macosx --show-sdk-path) && xcrun clang -fobjc-arc -fsyntax-only -x objective-c -isysroot "$SDKROOT" -I Revclip -I Revclip/App -I Revclip/Managers -I Revclip/Models -I Revclip/Services -I Revclip/Utilities -I Revclip/Vendor/FMDB -F Revclip/Vendor -include Revclip/Revclip-Prefix.pch Revclip/Managers/RCMenuManager.m`

## 例外・省略
- Worktree作成は省略: ユーザーから「メインブランチで作業してOK」の明示許可あり。
- Blueprint/TDDは省略: 既存 `RCMenuManager` への仕様差分修正タスクのため、実装後の構文検証で妥当性を確認。
