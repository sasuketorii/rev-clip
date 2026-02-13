# SOW: Task 2-9 UIコンポーネント

## 概要
- 設定画面等で利用する `RCDesignableView` / `RCDesignableButton` を新規実装。
- 両コンポーネントを `IB_DESIGNABLE` + `IBInspectable` 対応とし、Interface Builder から見た目を調整可能にした。

## 実施内容
- `src/Revclip/Revclip/UI/Views/RCDesignableView.h` を追加:
  - `backgroundColor` / `cornerRadius` / `borderColor` / `borderWidth` を公開
- `src/Revclip/Revclip/UI/Views/RCDesignableView.m` を追加:
  - `wantsLayer = YES` の初期化
  - `drawRect:` で背景色・角丸・ボーダー描画
  - `layer.cornerRadius` / `layer.borderWidth` / `layer.borderColor` / `layer.backgroundColor` を更新
  - `IBInspectable` 変更時に即時反映
- `src/Revclip/Revclip/UI/Views/RCDesignableButton.h` を追加:
  - `buttonBackgroundColor` / `cornerRadius` / `borderColor` / `borderWidth` / `hoverBackgroundColor` を公開
- `src/Revclip/Revclip/UI/Views/RCDesignableButton.m` を追加:
  - `wantsLayer = YES` の初期化
  - `trackingArea` 管理 (`updateTrackingAreas`) による hover 検知
  - `mouseEntered:` / `mouseExited:` で背景色を hover 状態に応じて切り替え
  - `layer.cornerRadius` / `layer.borderWidth` / `layer.borderColor` / `layer.backgroundColor` を更新
- `src/Revclip` で `xcodegen generate` を実行し、`Revclip.xcodeproj` を再生成。

## 検証結果
- `xcodegen generate`: 成功
- 構文チェック（PASS）:
  - `xcrun clang -fobjc-arc -fsyntax-only ... Revclip/UI/Views/RCDesignableView.m`
  - `xcrun clang -fobjc-arc -fsyntax-only ... Revclip/UI/Views/RCDesignableButton.m`

## 例外・省略
- Worktree作成は省略: ユーザーから「メインブランチで作業してOK」の明示許可あり。
- Blueprint/TDDは省略: 小規模なUIコンポーネント追加タスクのため、実装後の構文チェックで妥当性確認を実施。
