# SOW: Task 2-3d Exclude Settings Panel

## 概要
- `RCExcludePreferencesViewController` に除外アプリ設定パネルを実装。
- `NSTableView`（cell-based）+ `NSScrollView` で除外アプリ一覧表示を追加。
- `+ / - / Add Current App` 操作で `RCExcludeAppService` と連携して除外リストを管理可能にした。

## 実施内容
- `src/Revclip/Revclip/UI/Preferences/RCExcludePreferencesViewController.m`
  - `RCExcludeAppService` をインポートし、一覧データ取得・追加・削除を実装。
  - `NSTableViewDataSource` / `NSTableViewDelegate` を実装。
  - 2カラムのcell-basedテーブルをコードで構築:
    - icon列（幅24固定）
    - name列（アプリ名、解決不能時はbundle identifier）
  - アプリアイコン取得:
    - `URLForApplicationWithBundleIdentifier:` でパス解決
    - `iconForFile:` でアイコン取得
  - `Add (+)`:
    - `NSOpenPanel` を `/Applications` 起点で表示
    - `.app` のみ許可 (`UTTypeApplicationBundle`)
    - 選択アプリのbundle identifierを抽出してサービスに追加
  - `Remove (-)`:
    - 選択行のbundle identifierをサービスから削除
  - `Add Current App`:
    - `NSWorkspace.sharedWorkspace.frontmostApplication` のbundle identifierを追加
  - 追加/削除後に一覧再読込・選択状態更新を実施。
- `src/Revclip/Revclip/UI/Preferences/RCExcludePreferencesView.xib`
  - 旧プレースホルダラベルを削除し、固定サイズ `480x350` のコンテナビューへ整理。

## 検証結果
- 構文チェック（PASS）:
  - `xcrun clang -fobjc-arc -fmodules -fsyntax-only -isysroot "$(xcrun --show-sdk-path)" -I src/Revclip/Revclip -I src/Revclip/Revclip/UI -I src/Revclip/Revclip/UI/Preferences -I src/Revclip/Revclip/Services src/Revclip/Revclip/UI/Preferences/RCExcludePreferencesViewController.m`
- XML整形式チェック（PASS）:
  - `xmllint --noout src/Revclip/Revclip/UI/Preferences/RCExcludePreferencesView.xib`
- 実行不可:
  - `xcodebuild` / `ibtool` はこの環境でフルXcode未導入のため実行不可。

## 例外・省略
- Worktree作成は省略: ユーザーから「メインブランチで作業してOK」の明示許可あり。
- Blueprint/TDDは省略: ユーザー指示（テスト不要）に基づき、UI実装を優先。
