# SOW: Task 1-2 Constants / Environment Definitions

## 概要
- `RCConstants` の命名規約不一致を修正。
- Menuカテゴリの7キーを `kRC...Key` 形式へ統一し、`.h`/`.m` の宣言・定義・文字列値を一致させた。
- Betaキーの `kRCBetapasteAndDeleteHistoryModifier` を `kRCBetaPasteAndDeleteHistoryModifier` に修正。

## 実施内容
- `src/Revclip/Revclip/App/RCConstants.h`:
  - Menuカテゴリの以下7定数を改名
    - `menuItemsAreMarkedWithNumbers` → `kRCMenuItemsAreMarkedWithNumbersKey`
    - `showToolTipOnMenuItem` → `kRCShowToolTipOnMenuItemKey`
    - `maxLengthOfToolTipKey` → `kRCMaxLengthOfToolTipKey`
    - `showImageInTheMenu` → `kRCShowImageInTheMenuKey`
    - `addNumericKeyEquivalents` → `kRCAddNumericKeyEquivalentsKey`
    - `thumbnailWidth` → `kRCThumbnailWidthKey`
    - `thumbnailHeight` → `kRCThumbnailHeightKey`
  - `kRCBetapasteAndDeleteHistoryModifier` → `kRCBetaPasteAndDeleteHistoryModifier`
- `src/Revclip/Revclip/App/RCConstants.m`:
  - 上記と同一の定数名に改名。
  - 文字列値も定数名と同一になるように更新。
- `xcodegen generate` を再実行し、`src/Revclip/Revclip.xcodeproj` を再生成。

## 検証結果
- `xcodegen generate` 実行成功（project 再生成完了）。
- 構文チェック:
  - `xcrun clang -fsyntax-only -x objective-c -fobjc-arc -isysroot "$(xcrun --sdk macosx --show-sdk-path)" Revclip/App/RCConstants.m`
  - 結果: エラーなし（PASS）

## 例外・省略
- Worktree作成は省略: ユーザーから「メインブランチで作業してOK」の明示許可あり。
- Blueprint/TDDは省略: 既存定数名の整合性修正のみで、ロジック追加・仕様拡張を伴わないため。
