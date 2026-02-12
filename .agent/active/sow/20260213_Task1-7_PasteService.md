# SOW: Task 1-7 ペーストサービス

## 概要
- `RCPasteService` を新規実装し、クリップ選択時の「Pasteboard書き戻し + Cmd+V送信」をサービス化。
- `RCMenuManager` から直接Pasteboard操作していた経路を `RCPasteService` 呼び出しに置換。
- `RCAppDelegate` 起動時DIに `pasteService` を登録。

## 実施内容
- `src/Revclip/Revclip/Services/RCPasteService.h` を追加:
  - `+shared`
  - `-pasteClipData:`
  - `-pastePlainText:`
  - `-sendPasteKeyStroke`
- `src/Revclip/Revclip/Services/RCPasteService.m` を追加:
  - `kRCPrefInputPasteCommandKey` に応じた Cmd+V 送信制御
  - `kRCBetaPastePlainText` + `kRCBetaPastePlainTextModifier` による修飾キー判定 (`isPressedModifier:`)
  - 修飾キー押下時のプレーンテキストPasteboard書き込み
  - メニュークローズ後に貼り付けるため `dispatch_after(0.05s)` を実施
  - `NSWorkspace.sharedWorkspace.frontmostApplication` を再アクティブ化してから送信
  - `RCAccessibilityService` で権限チェックし、未許可時は `NSLog` で警告してスキップ
  - `CGEvent` で `CGKeyCode 9`（Vキー）の keyDown/keyUp を `kCGAnnotatedSessionEventTap` に送信
  - `sendPasteKeyStroke` のメインスレッド実行保証
- `src/Revclip/Revclip/Managers/RCMenuManager.m` を更新:
  - `selectClipMenuItem:` の処理を `[[RCPasteService shared] pasteClipData:clipData]` へ変更
- `src/Revclip/Revclip/App/RCAppDelegate.m` を更新:
  - 起動時に `RCPasteService *pasteService = [RCPasteService shared];`
  - `RCEnvironment.shared.pasteService` へ登録
- `src/Revclip` で `xcodegen generate` を実行し、`Revclip.xcodeproj` を更新。

## 検証結果
- `xcodegen generate`: 成功
- 構文チェック（PASS）:
  - `xcrun clang -fobjc-arc -fsyntax-only ... Revclip/Services/RCPasteService.m`
  - `xcrun clang -fobjc-arc -fsyntax-only ... Revclip/Managers/RCMenuManager.m`
  - `xcrun clang -fobjc-arc -fsyntax-only ... Revclip/App/RCAppDelegate.m`

## 例外・省略
- Worktree作成は省略: ユーザーから「メインブランチで作業してOK」の明示許可あり。
- Blueprint/TDDは省略: 既存フローへの機能追加を優先し、構文チェックで妥当性を確認。
