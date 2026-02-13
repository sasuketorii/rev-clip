# ExecPlan: Task 2-1a フォルダ個別ホットキー

## 背景
Task 2-1で実装済みのグローバルホットキー基盤を拡張し、スニペットフォルダごとに個別ホットキーを登録・解除できるようにする。

## スコープ
- `RCHotKeyService` にフォルダ個別ホットキーAPIを追加
- `kRCFolderKeyCombos` への保存/削除を実装
- フォルダ用HotKey ID（100+）と識別子マッピング実装
- フォルダホットキー通知の追加
- `RCMenuManager` で通知受信して該当フォルダメニューを表示

## 実装ステップ
1. `RCHotKeyService.h/.m` のAPI/通知/内部マッピング追加
2. 永続化 (`kRCFolderKeyCombos`) と `reloadFolderHotKeys` 実装
3. `RCMenuManager.m` にフォルダ通知の受信・表示実装
4. `xcodegen generate` と構文チェック
5. SOW記録

## 検証
- `cd src/Revclip && xcodegen generate`
- `xcrun clang -fobjc-arc -fsyntax-only ... RCHotKeyService.m`
- `xcrun clang -fobjc-arc -fsyntax-only ... RCMenuManager.m`

## 省略方針
- Blueprint/TDDは省略（既存クラスへの局所拡張のため）。
