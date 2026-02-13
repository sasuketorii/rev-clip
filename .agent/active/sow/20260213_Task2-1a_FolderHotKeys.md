# SOW: Task 2-1a フォルダ個別ホットキー

## 概要
- `RCHotKeyService` にフォルダ個別ホットキー登録/解除/再読み込みAPIを追加。
- `kRCFolderKeyCombos`（`{folderIdentifier: {keyCode, modifiers}}`）への保存/削除を実装。
- フォルダ用 `EventHotKeyID.id` を `100+` で採番し、既存の `1-4` と衝突しないように管理。
- フォルダ識別子ごとの `EventHotKeyRef` マッピングを追加。
- フォルダホットキー発火時に `RCHotKeySnippetFolderTriggeredNotification` を `userInfo` に `folderIdentifier` を含めて通知。
- `RCMenuManager` でフォルダ通知を受信し、対象フォルダのスニペットメニューをポップアップ。

## 実施内容
- `src/Revclip/Revclip/Services/RCHotKeyService.h`:
  - API追加:
    - `registerSnippetFolderHotKey:forFolderIdentifier:`
    - `unregisterSnippetFolderHotKey:`
    - `reloadFolderHotKeys`
  - 通知追加:
    - `RCHotKeySnippetFolderTriggeredNotification`
    - `RCHotKeyFolderIdentifierUserInfoKey`
- `src/Revclip/Revclip/Services/RCHotKeyService.m`:
  - フォルダ用IDベース値 `100` を追加。
  - `identifier -> EventHotKeyRef`、`identifier -> hotKeyID`、`hotKeyID -> identifier` の辞書管理を追加。
  - `kRCFolderKeyCombos` の読み書きロジックを追加。
  - `reloadFolderHotKeys` で `fetchAllSnippetFolders` に基づいて再登録。
  - 通知発火でフォルダIDを `userInfo` に含める分岐を追加。
  - 起動時ロード処理 `loadAndRegisterHotKeysFromDefaults` から `reloadFolderHotKeys` を呼ぶよう更新。
- `src/Revclip/Revclip/Managers/RCMenuManager.m`:
  - `RCHotKeySnippetFolderTriggeredNotification` 監視を追加。
  - `handleHotKeySnippetFolderTriggered:` を追加。
  - `popUpSnippetFolderMenuFromHotKeyWithIdentifier:` を追加し、該当フォルダのみのスニペットメニューを表示。
  - スニペット描画重複を避けるため `appendSnippetsForFolderIdentifier:toMenu:` を追加。

## 検証結果
- `cd src/Revclip && xcodegen generate`: 成功
- 構文チェック（PASS）:
  - `xcrun clang -fobjc-arc -fmodules -fsyntax-only -IRevclip -IRevclip/App -IRevclip/Services -IRevclip/Managers -IRevclip/Models -IRevclip/Utilities -IRevclip/Vendor/FMDB Revclip/Services/RCHotKeyService.m`
  - `xcrun clang -fobjc-arc -fmodules -fsyntax-only -IRevclip -IRevclip/App -IRevclip/Services -IRevclip/Managers -IRevclip/Models -IRevclip/Utilities -IRevclip/Vendor/FMDB Revclip/Managers/RCMenuManager.m`
- 全体ビルド:
  - `xcodebuild` はこの環境では不可（`xcode-select` が Command Line Tools を指しているため）

## 例外・省略
- Worktree作成は省略: ユーザーから「メインブランチで作業してOK」の明示許可あり。
- Blueprint/TDDは省略: 既存クラスへの局所拡張のため。
