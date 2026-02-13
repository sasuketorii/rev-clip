# SOW: Task 2-9 UIコンポーネント修正

## 概要
- `RCDesignableView` / `RCDesignableButton` に対する指摘4件を修正。
- 目的は「描画責務の重複排除」「hover時の意図しない透明化防止」「初期hover状態の取りこぼし防止」「不要なレイヤ再設定削減」。

## 実施内容
- `src/Revclip/Revclip/UI/Views/RCDesignableView.m`
  - `drawRect:` での塗り/線描画を削除し、見た目反映を `CALayer` 更新のみに統一。
  - `rc_applyLayerStyle` 内の `self.wantsLayer = YES` を削除（`rc_commonInit` で一度だけ設定）。

- `src/Revclip/Revclip/UI/Views/RCDesignableButton.h`
  - `hoverBackgroundColor` を `nullable` 化。

- `src/Revclip/Revclip/UI/Views/RCDesignableButton.m`
  - `hoverBackgroundColor` のデフォルトを `nil` に変更。
  - `setHoverBackgroundColor:` で `clearColor` へ強制変換しないよう修正。
  - `rc_currentBackgroundColor` の既存フォールバック（`hoverBackgroundColor ?: buttonBackgroundColor`）を有効化。
  - `updateTrackingAreas` に `NSTrackingAssumeInside` を追加。
  - `updateTrackingAreas` 後に現在のマウス位置から hover 状態を同期する `rc_updateHoverStateFromCurrentMouseLocation` を追加。
  - `rc_applyLayerStyle` 内の `self.wantsLayer = YES` を削除（`rc_commonInit` で一度だけ設定）。

## 検証結果
- 構文チェック（PASS）
  - `cd src/Revclip && xcrun --sdk macosx clang -fobjc-arc -fsyntax-only -fmodules -isysroot "$(xcrun --sdk macosx --show-sdk-path)" -I Revclip -I Revclip/UI/Views Revclip/UI/Views/RCDesignableView.m Revclip/UI/Views/RCDesignableButton.m`
- `make -C src/Revclip debug` を実行。
- 結果: 失敗（環境依存）
  - `xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance`

## 例外・省略
- Worktree作成は省略: ユーザーから「メインブランチで作業OK」の明示許可あり。
- テスト/ビルドはローカル環境のXcode未導入のため完了不可。
