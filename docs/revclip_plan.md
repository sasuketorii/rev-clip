# Revclip 実装プラン

> Clipy (macOSクリップボードマネージャー) を「Revclip」として完全リブランド・再実装するための包括的実装プラン
>
> **Rev.2** (2026-02-13) — レビュー指摘事項 C-1, C-2, M-1〜M-6, m-1〜m-7 への対応を反映
>
> **Rev.3** (2026-02-13) — Xcode.app不使用制約への対応。ビルドシステム・開発フローをすべてターミナル(Claude Code)完結に修正
>
> **Rev.4** (2026-02-13) — レビュー指摘事項 N-1〜N-3 への対応。Xcode.app依存の明記、notarytoolシンタックス修正、submission ID抽出修正

---

## 0. Clipy ソースコード分析結果

### 0.1 ディレクトリ構成

```
Clipy/
├── Clipy.xcodeproj/          # Xcode プロジェクト設定
├── Clipy.xcworkspace/        # CocoaPods ワークスペース
├── Clipy/
│   ├── Generated/            # SwiftGen 自動生成コード
│   │   ├── AssetsImages.swift
│   │   ├── Colors.swift
│   │   └── LocalizedStrings.swift
│   ├── Xibs/
│   │   └── MainMenu.xib      # メインメニューNIB
│   ├── Resources/
│   │   ├── Images.xcassets/   # アイコン・画像アセット
│   │   ├── en.lproj/         # 英語ローカライズ
│   │   ├── ja.lproj/         # 日本語ローカライズ
│   │   ├── de.lproj/         # ドイツ語
│   │   ├── zh-Hans.lproj/    # 中国語(簡体字)
│   │   ├── it.lproj/         # イタリア語
│   │   └── colors.txt        # カラー定義
│   ├── Supporting Files/
│   │   ├── Info.plist
│   │   └── dsa_pub.pem       # Sparkle用DSA公開鍵
│   └── Sources/
│       ├── AppDelegate.swift              # アプリケーションエントリポイント
│       ├── Constants.swift                # 定数定義
│       ├── Environments/
│       │   ├── Environment.swift          # DI環境コンテナ
│       │   └── AppEnvironment.swift       # 環境スタック管理
│       ├── Services/
│       │   ├── ClipService.swift          # クリップボード監視・保存
│       │   ├── PasteService.swift         # ペースト実行（Cmd+Vシミュレート）
│       │   ├── HotKeyService.swift        # グローバルホットキー管理
│       │   ├── AccessibilityService.swift # Accessibility権限管理
│       │   ├── ExcludeAppService.swift    # 除外アプリ管理
│       │   └── DataCleanService.swift     # 古い履歴の定期クリーンアップ
│       ├── Managers/
│       │   └── MenuManager.swift          # メニューバー・ポップアップメニュー構築
│       ├── Models/
│       │   ├── CPYClip.swift              # Realmモデル: クリップ履歴
│       │   ├── CPYClipData.swift          # NSCoding: クリップデータ本体
│       │   ├── CPYFolder.swift            # Realmモデル: スニペットフォルダ
│       │   ├── CPYSnippet.swift           # Realmモデル: スニペット
│       │   ├── CPYAppInfo.swift           # 除外アプリ情報
│       │   └── CPYDraggedData.swift       # D&Dデータ
│       ├── Enums/
│       │   └── MenuType.swift             # メニュー種別(main/history/snippet)
│       ├── Preferences/
│       │   ├── CPYPreferencesWindowController.swift
│       │   └── Panels/
│       │       ├── CPYGeneralPreferenceViewController   (xib)
│       │       ├── CPYMenuPreferenceViewController      (xib)
│       │       ├── CPYTypePreferenceViewController.swift
│       │       ├── CPYExcludeAppPreferenceViewController.swift
│       │       ├── CPYShortcutsPreferenceViewController.swift
│       │       ├── CPYUpdatesPreferenceViewController.swift
│       │       └── CPYBetaPreferenceViewController.swift
│       ├── Snippets/
│       │   └── CPYSnippetsEditorWindowController.swift  # スニペットエディタ
│       ├── Views/
│       │   ├── DesignableView/
│       │   │   ├── CPYDesignableView.swift   # IBDesignable NSView
│       │   │   └── CPYDesignableButton.swift # IBDesignable NSButton
│       │   ├── TableViewCell/
│       │   ├── SplitViews/
│       │   └── TextViews/
│       ├── Extensions/
│       │   ├── NSPasteboard+Deprecated.swift  # 旧PasteboardType互換
│       │   ├── Realm+Migration.swift          # DBマイグレーション
│       │   ├── Realm+NoCatch.swift
│       │   ├── NSImage+Resize.swift
│       │   ├── NSImage+NSColor.swift
│       │   └── (その他ユーティリティ)
│       └── Utility/
│           └── CPYUtilities.swift          # 共通ユーティリティ
├── ClipyTests/
├── Podfile / Podfile.lock
├── fastlane/
└── README.md
```

### 0.2 主要機能一覧

| 機能 | 実装箇所 | 説明 |
|------|---------|------|
| クリップボード監視 | `ClipService.swift` | `NSPasteboard.general.changeCount` を750usポーリング |
| 履歴保存 | `ClipService.swift` + `CPYClip.swift` + `CPYClipData.swift` | RealmDB + NSKeyedArchiverでファイル保存 |
| ペースト実行 | `PasteService.swift` | `CGEvent` で Cmd+V キーイベントをポスト |
| メニューバー常駐 | `MenuManager.swift` | `NSStatusItem` でステータスバーアイコン |
| ポップアップメニュー | `MenuManager.swift` | `NSMenu.popUp()` で履歴・スニペット表示 |
| グローバルホットキー | `HotKeyService.swift` | Magnetライブラリ経由でCarbonホットキー登録 |
| スニペット管理 | `CPYSnippetsEditorWindowController.swift` | NSOutlineView + Realm |
| スニペットインポート/エクスポート | 同上 | AEXML (XML形式) |
| 設定画面 | `CPYPreferencesWindowController.swift` | 7タブ（General/Menu/Type/Exclude/Shortcuts/Updates/Beta） |
| 除外アプリ | `ExcludeAppService.swift` | フロントアプリ監視 + 特殊アプリ(1Password等)対応 |
| 定期クリーンアップ | `DataCleanService.swift` | 30分間隔で溢れた履歴削除 |
| スクリーンショット監視 | `AppDelegate.swift` (Screeen/RxScreeen) | Beta機能 |
| ログイン時自動起動 | `AppDelegate.swift` (LoginServiceKit) | ログインアイテム登録 |
| 自動アップデート | Sparkle | appcast.xml 経由 |
| カラーコードプレビュー | `CPYClipData.swift` (SwiftHEXColors) | HEXカラー文字列の色プレビュー |
| Accessibility権限チェック | `AccessibilityService.swift` | macOS 10.14+でペーストに必須 |
| i18n (多言語対応) | Resources/*.lproj | 英/日/独/中(簡)/伊 |

### 0.3 使用フレームワーク/ライブラリ

| ライブラリ | 用途 | Revclipでの代替 |
|-----------|------|----------------|
| **RealmSwift** (10.7.2) | データ永続化 (クリップ履歴・スニペット) | SQLite (FMDB) |
| **RxSwift/RxCocoa** (5.1.1) | リアクティブプログラミング・UserDefaults監視 | NSNotificationCenter + KVO + GCD |
| **Magnet** (3.2.0) | グローバルホットキー登録(Carbon API) | Carbon API直接利用 |
| **KeyHolder** (4.0.0) | ショートカット記録UI | カスタム実装 (RCHotKeyRecorderView) |
| **Sauce** (2.1.0) | キーコード変換 | Objective-C Carbon API直接利用 |
| **Sparkle** (1.26.0) | 自動アップデート | Sparkle 2.x (Objective-C版を直接利用) |
| **PINCache** (3.0.3) | サムネイル画像キャッシュ | NSCache + ファイルベースキャッシュ |
| **LoginServiceKit** (2.2.0) | ログインアイテム登録 | SMAppService (macOS 13+) |
| **AEXML** (4.6.0) | XML パース（スニペットインポート/エクスポート） | NSXMLParser / NSXMLDocument |
| **LetsMove** (1.25) | "Applicationsフォルダに移動"ダイアログ | Objective-C版を直接利用 |
| **SwiftHEXColors** (1.4.1) | HEXカラー文字列→NSColor変換 | Objective-Cで自作 (NSColor+HexString) |
| **Screeen/RxScreeen** (2.0.1) | スクリーンショット監視 | NSMetadataQuery |
| **BartyCrouch** | ローカライズ管理（開発ツール） | 手動 / スクリプト |
| **SwiftGen** | コード自動生成（開発ツール） | 不要（Obj-C直接参照） |
| **SwiftLint** | Lintツール | clang-format |

### 0.4 UI/UX構成

1. **メニューバーアイコン**: `NSStatusItem` でステータスバーに常駐（黒/白/非表示の3状態）
2. **クリップメニュー**: メインメニュー = 履歴 + スニペット + 操作項目
3. **履歴メニュー**: 履歴のみ独立表示
4. **スニペットメニュー**: スニペットのみ独立表示
5. **設定ウィンドウ**: タブ切替式、7パネル
6. **スニペットエディタ**: NSSplitView（左：NSOutlineView / 右：NSTextView）
7. **LSUIElement = true**: Dockに表示しないエージェントアプリ

---

## 1. 技術スタック選定理由

### [Rev.2 修正] 選定結果: **Objective-C + Cocoa ネイティブ（ユーザー承認済み）**

> **注記**: 技術スタックは **Objective-C + AppKit** でユーザーから承認済みである。
> ユーザーはSwiftを使わない方針を明示しており、ClipyのUXを完全再現するためには
> AppKit (NSMenu, NSStatusItem, NSOutlineView等) のネイティブUIが必須であるため、
> Objective-C + AppKit が最適解として確定している。

| 項目 | 選定 | 理由 |
|------|------|------|
| **言語** | Objective-C (ユーザー承認済み) | Swiftを使わない制約。macOS APIとの親和性が最高。Cライブラリとの相互運用が容易。Apple Silicon完全対応 |
| **UIフレームワーク** | AppKit (Cocoa) | ClipyのUXをそのまま再現。NSMenu/NSStatusItem/NSWindowController等 |
| **データ永続化** | SQLite3 (FMDB) | Realmより軽量。依存が少ない。Objective-Cとの相性が良い。マイグレーションが明確 |
| **ホットキー** | Carbon API (RegisterEventHotKey) 直接利用 | Magnetの内部実装と同等。追加依存なし |
| **自動アップデート** | Sparkle 2.x (Obj-C版) | Clipyと同じ更新機構。Obj-C版は元々ネイティブ |
| **XML処理** | NSXMLParser / NSXMLDocument | macOS標準API。追加依存なし |
| **画像キャッシュ** | NSCache + ファイルキャッシュ | PINCache不要。シンプルで軽量 |
| **ログイン起動** | SMAppService (macOS 13+) | Apple推奨の最新API。Service Management framework |
| **ビルドシステム** | [Rev.3 修正][Rev.4 修正] xcodebuild (CLI) + .xcodeproj | Xcode.appのインストールが必要（ただしIDEとしての手動操作は不要）。すべてターミナル(xcodebuild/ibtool/actool等)で完結。CocoaPodsは使わない。直接組込 |

### Clipyとの比較

| 観点 | Clipy | Revclip |
|------|-------|---------|
| 言語 | Swift 5 | Objective-C |
| 依存管理 | CocoaPods (15+ライブラリ) | 最小限の外部依存 (Sparkle + FMDB程度) |
| DB | Realm (重量級、バイナリサイズ大) | SQLite3 (macOS標準搭載、軽量) |
| リアクティブ | RxSwift/RxCocoa | NSNotificationCenter + KVO + GCD |
| バイナリサイズ | 大（Realm + Rx + 多数Pod） | 小（ネイティブAPI中心） |
| macOS最小要件 | 10.10 | 14.0 (Sonoma)、ターゲット15.0 (Sequoia) |

### 代替案として検討し不採用とした技術

| 技術 | 不採用理由 |
|------|----------|
| Electron/Tauri | メニューバーアプリとしてはオーバーヘッドが大きい。Tauri 2.xはバイナリ2-5MBと軽量だが、NSMenu.popUp()によるネイティブポップアップメニューのカスタマイズに限界があり、ClipyのUX完全再現が困難 |
| Rust + objc2 crate | objc2 crateは成熟してきたが、AppKit UIの構築はまだ困難。UX再現性90%程度 |
| Python + PyObjC | パフォーマンス懸念。ランタイム依存。公証が複雑 |
| C + Cocoa (Pure C) | UIコードが冗長すぎる。Obj-Cで十分ネイティブ |
| Go + macdriver | AppKitバインディングが未成熟。メニューバーアプリの実装が限定的 |

---

## 2. アーキテクチャ設計

### [Rev.2 修正] 2.1 ディレクトリ構成

```
Revclip/
├── Revclip.xcodeproj/
├── Revclip/
│   ├── main.m                              # アプリケーションエントリポイント
│   ├── Info.plist
│   ├── Revclip.entitlements                # Hardened Runtime用
│   ├── Resources/
│   │   ├── Assets.xcassets/                # アイコン・画像
│   │   │   ├── AppIcon.appiconset/
│   │   │   ├── StatusBarIcon.imageset/
│   │   │   └── SnippetEditor/
│   │   ├── MainMenu.xib                   # メインメニューNIB
│   │   ├── en.lproj/Localizable.strings   # 英語
│   │   ├── ja.lproj/Localizable.strings   # 日本語
│   │   ├── de.lproj/Localizable.strings   # ドイツ語
│   │   ├── zh-Hans.lproj/Localizable.strings  # [Rev.2 追加] 中国語(簡体字)
│   │   └── it.lproj/Localizable.strings       # [Rev.2 追加] イタリア語
│   │
│   ├── App/
│   │   ├── RCAppDelegate.h / .m           # アプリケーションデリゲート
│   │   ├── RCConstants.h / .m             # 定数定義
│   │   └── RCEnvironment.h / .m           # 環境/DIコンテナ (シングルトン)
│   │
│   ├── Services/
│   │   ├── RCClipboardService.h / .m      # クリップボード監視・保存
│   │   ├── RCPasteService.h / .m          # ペースト実行 (CGEvent)
│   │   ├── RCHotKeyService.h / .m         # グローバルホットキー (Carbon API)
│   │   ├── RCAccessibilityService.h / .m  # Accessibility権限管理
│   │   ├── RCExcludeAppService.h / .m     # 除外アプリ管理
│   │   ├── RCDataCleanService.h / .m      # データクリーンアップ
│   │   └── RCLoginItemService.h / .m      # ログインアイテム管理
│   │
│   ├── Managers/
│   │   ├── RCMenuManager.h / .m           # メニュー構築・管理
│   │   └── RCDatabaseManager.h / .m       # SQLiteデータベース管理
│   │
│   ├── Models/
│   │   ├── RCClipItem.h / .m              # クリップ履歴モデル
│   │   ├── RCClipData.h / .m              # クリップデータ本体
│   │   ├── RCSnippetFolder.h / .m         # スニペットフォルダモデル
│   │   ├── RCSnippet.h / .m              # スニペットモデル
│   │   ├── RCAppInfo.h / .m               # 除外アプリ情報
│   │   └── RCDraggedData.h / .m           # D&Dデータ
│   │
│   ├── UI/
│   │   ├── Preferences/
│   │   │   ├── RCPreferencesWindowController.h / .m
│   │   │   ├── RCGeneralPreferenceVC.h / .m + .xib
│   │   │   ├── RCMenuPreferenceVC.h / .m + .xib
│   │   │   ├── RCTypePreferenceVC.h / .m + .xib
│   │   │   ├── RCExcludeAppPreferenceVC.h / .m + .xib
│   │   │   ├── RCShortcutsPreferenceVC.h / .m + .xib
│   │   │   ├── RCUpdatesPreferenceVC.h / .m + .xib
│   │   │   └── RCBetaPreferenceVC.h / .m + .xib
│   │   ├── SnippetEditor/
│   │   │   ├── RCSnippetEditorWindowController.h / .m + .xib
│   │   │   ├── RCSnippetEditorCell.h / .m
│   │   │   └── RCPlaceholderTextView.h / .m
│   │   ├── HotKeyRecorder/
│   │   │   └── RCHotKeyRecorderView.h / .m  # KeyHolderの代替
│   │   └── Views/
│   │       ├── RCSplitView.h / .m
│   │       ├── RCDesignableView.h / .m    # [Rev.2 追加] IBDesignable NSView
│   │       └── RCDesignableButton.h / .m  # [Rev.2 追加] IBDesignable NSButton
│   │
│   ├── Utilities/
│   │   ├── RCUtilities.h / .m             # 共通ユーティリティ
│   │   ├── NSColor+HexString.h / .m       # HEXカラー変換
│   │   ├── NSImage+Resize.h / .m          # 画像リサイズ
│   │   └── NSImage+Color.h / .m           # カラーイメージ生成
│   │
│   └── Vendor/                            # 外部ライブラリ (ソース組込)
│       ├── FMDB/                          # SQLiteラッパー
│       └── Sparkle.framework/             # 自動アップデート (2.x)
│
├── RevclipTests/                          # [Rev.2 修正] テスト拡充
│   ├── RCClipboardServiceTests.m
│   ├── RCDatabaseManagerTests.m
│   ├── RCSnippetTests.m
│   ├── RCHotKeyServiceTests.m
│   ├── RCPasteServiceTests.m             # [Rev.2 追加]
│   ├── RCExcludeAppServiceTests.m        # [Rev.2 追加]
│   ├── RCMenuManagerTests.m              # [Rev.2 追加]
│   ├── RCDataCleanServiceTests.m         # [Rev.2 追加]
│   ├── RCAccessibilityServiceTests.m     # [Rev.2 追加]
│   └── RCUtilitiesTests.m               # [Rev.2 追加]
│
├── project.yml                            # [Rev.3 追加] xcodegen プロジェクト定義ファイル
├── Makefile                               # [Rev.3 追加] 便利コマンドのラッパー
│
├── Scripts/
│   ├── build.sh                           # ビルドスクリプト
│   ├── notarize.sh                        # [Rev.3 修正] ビルド・署名・公証・DMG作成の全自動スクリプト
│   ├── create_dmg.sh                      # DMG作成スクリプト
│   └── export_strings.sh                  # ローカライズ文字列エクスポート
│
└── Distribution/
    ├── dmg_background.png
    └── entitlements.plist
```

### 2.2 モジュール分割

```
┌─────────────────────────────────────────────┐
│                RCAppDelegate                │  アプリライフサイクル
├─────────────────────────────────────────────┤
│              RCEnvironment                  │  DIコンテナ (シングルトン)
├──────────┬──────────┬───────────┬───────────┤
│ Services │ Managers │  Models   │    UI     │
├──────────┼──────────┼───────────┼───────────┤
│ Clipboard│ Menu     │ ClipItem  │ Prefs WC  │
│ Paste    │ Database │ ClipData  │ Snippet WC│
│ HotKey   │          │ Snippet   │ HotKey    │
│ Access.  │          │ Folder    │ Recorder  │
│ Exclude  │          │ AppInfo   │ Designable│  [Rev.2 追加]
│ DataClean│          │ DragData  │ View/Btn  │  [Rev.2 追加]
│ LoginItem│          │           │           │
└──────────┴──────────┴───────────┴───────────┘
         ↓               ↓
   ┌─────────┐    ┌──────────┐
   │ Carbon  │    │  SQLite  │
   │ HotKey  │    │  (FMDB)  │
   │ CGEvent │    └──────────┘
   └─────────┘
```

### 2.3 データフロー

```
NSPasteboard (750usポーリング)
    ↓ changeCount変更検出
    ↓ [Rev.2 追加] macOS 16+: accessBehavior / detect で事前チェック
RCClipboardService
    ↓ 除外アプリチェック
    ↓ データ型フィルタ
RCClipData (NSCoding準拠、ファイル保存)
    ↓
RCDatabaseManager (SQLite INSERT)
    ↓ NSNotification
RCMenuManager (NSMenu再構築)
    ↓ [Rev.2 追加] data_hashでクリップ特定・選択
NSStatusItem.menu に反映
```

---

## 3. 機能マッピング

### 3.1 コア機能

| # | Clipy機能 | Clipy実装 | Revclip実装 |
|---|----------|----------|------------|
| 1 | クリップボード監視 | `Observable.interval(750us)` + `NSPasteboard.general.changeCount` | `dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER)` で750usタイマー + `NSPasteboard.general.changeCount` |
| 2 | 履歴データ保存 | `NSKeyedArchiver.archiveRootObject()` → ファイル保存 + Realm DB | `NSKeyedArchiver` → ファイル保存 + SQLite (FMDB) |
| 3 | ペースト実行 | `CGEvent(keyboardEventSource:virtualKey:keyDown:)` で Cmd+V | 同一実装 (Objective-CからCore Graphics C APIを直接呼出) |
| 4 | メニューバーアイコン | `NSStatusBar.system.statusItem()` | 同一実装 |
| 5 | ポップアップメニュー | `NSMenu.popUp(positioning:at:in:)` | 同一実装 |
| 6 | グローバルホットキー | Magnetライブラリ (内部: `RegisterEventHotKey`) | Carbon API `RegisterEventHotKey` / `UnregisterEventHotKey` を直接使用 |
| 7 | Accessibility権限 | `AXIsProcessTrustedWithOptions()` | 同一API (Objective-Cから直接呼出) |
| 8 | ログイン起動 | LoginServiceKit (`LSSharedFileList`) | `SMAppService.mainApp` (macOS 13+) |
| 9 | 自動アップデート | Sparkle (Swift bridge) | Sparkle 2.x (Objective-Cネイティブ版を直接利用) |
| 10 | データクリーンアップ | `Observable.interval(30分)` + Realm削除 | `NSTimer` / `dispatch_source` + SQLite DELETE |

### 3.2 データモデル

| Clipy (Realm) | Revclip (SQLite) |
|---------------|-----------------|
| `CPYClip` (dataPath, title, dataHash, primaryType, updateTime, thumbnailPath, isColorCode) | `clip_items` テーブル (id INTEGER PRIMARY KEY, data_path TEXT, title TEXT, data_hash TEXT UNIQUE, primary_type TEXT, update_time INTEGER, thumbnail_path TEXT, is_color_code INTEGER) |
| `CPYFolder` (index, enable, title, identifier, snippets→List) | `snippet_folders` テーブル (id INTEGER PRIMARY KEY, folder_index INTEGER, enabled INTEGER, title TEXT, identifier TEXT UNIQUE) |
| `CPYSnippet` (index, enable, title, content, identifier, folders→LinkingObjects) | `snippets` テーブル (id INTEGER PRIMARY KEY, folder_id TEXT REFERENCES snippet_folders(identifier), snippet_index INTEGER, enabled INTEGER, title TEXT, content TEXT, identifier TEXT UNIQUE) |

#### [Rev.2 追加] data_hashベースのクリップ検索ロジック (m-7対応)

Clipyの `CPYClip` モデルでは `dataHash` がRealmの主キーとして使用されており、`MenuManager` でメニューアイテム選択時に `menuItem.representedObject = clip.dataHash` でクリップを特定している（`AppDelegate.selectClipMenuItem` 内で `realm.object(ofType: CPYClip.self, forPrimaryKey: primaryKey)` として検索）。

RevclipのSQLiteスキーマでは `id INTEGER PRIMARY KEY AUTOINCREMENT` を主キーとし、`data_hash` にはUNIQUE制約 + INDEXを設定しているため、`RCMenuManager` でのクリップ選択は以下のように `data_hash` で検索する:

```objc
// RCMenuManager.m - メニューアイテム選択時
- (void)selectClipMenuItem:(NSMenuItem *)menuItem {
    NSString *dataHash = menuItem.representedObject;
    RCClipItem *clip = [[RCDatabaseManager shared] clipItemWithDataHash:dataHash];
    if (clip) {
        [[RCEnvironment shared].pasteService pasteWithClip:clip];
    }
}
```

### 3.3 UI マッピング

| Clipy UI | Revclip 実装 |
|----------|-------------|
| MainMenu.xib | MainMenu.xib (Objective-C接続に変更) |
| CPYPreferencesWindowController + 7パネルxib | RCPreferencesWindowController + 7パネルxib (同一レイアウト) |
| CPYSnippetsEditorWindowController.xib | RCSnippetEditorWindowController.xib (同一レイアウト) |
| RecordView (KeyHolder) | RCHotKeyRecorderView (カスタムNSView、KeyHolderと同等UI) |
| CPYSnippetsEditorCell | RCSnippetEditorCell |
| CPYPlaceHolderTextView | RCPlaceholderTextView |
| CPYSplitView | RCSplitView |
| CPYDesignableView | RCDesignableView [Rev.2 追加] |
| CPYDesignableButton | RCDesignableButton [Rev.2 追加] |

#### [Rev.2 追加] RCDesignableView / RCDesignableButton の設計 (M-5対応)

Clipyの `CPYDesignableView` は `@IBDesignable` な `NSView` サブクラスで、Interface Builderから `backgroundColor`、`borderColor`、`borderWidth`、`cornerRadius` をカスタマイズ可能にしている。設定画面のタブバー背景等に使用されている。

```objc
// RCDesignableView.h
@interface RCDesignableView : NSView
@property (nonatomic, strong) IBInspectable NSColor *backgroundColor;
@property (nonatomic, strong) IBInspectable NSColor *borderColor;
@property (nonatomic, assign) IBInspectable CGFloat borderWidth;
@property (nonatomic, assign) IBInspectable CGFloat cornerRadius;
@end
```

`CPYDesignableButton` は `NSButton` サブクラスで、`textColor` プロパティをIBInspectableでカスタマイズ可能にしている。

```objc
// RCDesignableButton.h
@interface RCDesignableButton : NSButton
@property (nonatomic, strong) IBInspectable NSColor *textColor;
@end
```

### [Rev.2 修正] 3.4 設定項目マッピング (M-3, M-4対応)

Clipyの全UserDefaults設定キーをRevclipでも同等にサポートする。キープレフィックスを `kCPY` から `kRC` に変更する。

**Constants.swift の全キーを網羅的にマッピング**:

#### General カテゴリ

| 設定項目 | Clipyキー | Revclipキー | デフォルト値 |
|---------|----------|------------|------------|
| 最大履歴数 | kCPYPrefMaxHistorySizeKey | kRCPrefMaxHistorySizeKey | 30 |
| ログイン起動 | loginItem | loginItem | NO |
| ログイン起動アラート抑制 | suppressAlertForLoginItem | suppressAlertForLoginItem | NO |
| ペーストコマンド入力 | kCPYPrefInputPasteCommandKey | kRCPrefInputPasteCommandKey | YES |
| ペースト後に履歴を並べ替え | kCPYPrefReorderClipsAfterPasting | kRCPrefReorderClipsAfterPasting | YES | [Rev.2 追加] |
| ステータスバー表示タイプ (0:none/1:black/2:white) | kCPYPrefShowStatusItemKey | kRCPrefShowStatusItemKey | 1 (black) | [Rev.2 追加] |
| 保存対象タイプ | kCPYPrefStoreTypesKey | kRCPrefStoreTypesKey | 全タイプYES |
| 同一履歴の上書き | kCPYPrefOverwriteSameHistroy | kRCPrefOverwriteSameHistory | YES | [Rev.2 追加] |
| 同一履歴のコピー | kCPYPrefCopySameHistroy | kRCPrefCopySameHistory | YES | [Rev.2 追加] |
| クラッシュレポート収集 | kCPYCollectCrashReport | kRCCollectCrashReport | YES | [Rev.2 追加] |

#### Menu カテゴリ

| 設定項目 | Clipyキー | Revclipキー | デフォルト値 |
|---------|----------|------------|------------|
| インライン表示数 | kCPYPrefNumberOfItemsPlaceInlineKey | kRCPrefNumberOfItemsPlaceInlineKey | 0 |
| フォルダ内表示数 | kCPYPrefNumberOfItemsPlaceInsideFolderKey | kRCPrefNumberOfItemsPlaceInsideFolderKey | 10 |
| 最大タイトル長 | kCPYPrefMaxMenuItemTitleLengthKey | kRCPrefMaxMenuItemTitleLengthKey | 20 |
| メニューアイコンサイズ | kCPYPrefMenuIconSizeKey | kRCPrefMenuIconSizeKey | 16 | [Rev.2 追加] |
| メニューにアイコン表示 | kCPYPrefShowIconInTheMenuKey | kRCPrefShowIconInTheMenuKey | YES | [Rev.2 追加] |
| 番号表示 | menuItemsAreMarkedWithNumbers | menuItemsAreMarkedWithNumbers | YES |
| 番号を0から開始 | kCPYPrefMenuItemsTitleStartWithZeroKey | kRCPrefMenuItemsTitleStartWithZeroKey | NO | [Rev.2 追加] |
| ツールチップ | showToolTipOnMenuItem | showToolTipOnMenuItem | YES |
| ツールチップ最大長 | maxLengthOfToolTipKey | maxLengthOfToolTipKey | 200 | [Rev.2 追加] |
| 画像表示 | showImageInTheMenu | showImageInTheMenu | YES |
| カラーコードプレビュー | kCPYPrefShowColorPreviewInTheMenu | kRCPrefShowColorPreviewInTheMenu | YES |
| 数字キーショートカット付加 | addNumericKeyEquivalents | addNumericKeyEquivalents | NO | [Rev.2 追加] |
| サムネイル幅 | thumbnailWidth | thumbnailWidth | 100 | [Rev.2 追加] |
| サムネイル高さ | thumbnailHeight | thumbnailHeight | 32 | [Rev.2 追加] |
| 「履歴クリア」メニュー項目表示 | kCPYPrefAddClearHistoryMenuItemKey | kRCPrefAddClearHistoryMenuItemKey | YES | [Rev.2 追加] |
| 履歴クリア前の確認アラート | kCPYPrefShowAlertBeforeClearHistoryKey | kRCPrefShowAlertBeforeClearHistoryKey | YES | [Rev.2 追加] |

#### Type カテゴリ

| 設定項目 | Clipyキー | Revclipキー |
|---------|----------|------------|
| 保存対象タイプ | kCPYPrefStoreTypesKey | kRCPrefStoreTypesKey |

#### Exclude カテゴリ

| 設定項目 | Clipyキー | Revclipキー |
|---------|----------|------------|
| 除外アプリ | kCPYExcludeApplications | kRCExcludeApplications |

#### Shortcuts カテゴリ

| 設定項目 | Clipyキー | Revclipキー |
|---------|----------|------------|
| メインメニュー | kCPYHotKeyMainKeyCombo | kRCHotKeyMainKeyCombo |
| 履歴メニュー | kCPYHotKeyHistoryKeyCombo | kRCHotKeyHistoryKeyCombo |
| スニペットメニュー | kCPYHotKeySnippetKeyCombo | kRCHotKeySnippetKeyCombo |
| 履歴クリア | kCPYClearHistoryKeyCombo | kRCClearHistoryKeyCombo | [Rev.2 追加] |
| フォルダ個別ホットキー | kCPYFolderKeyCombos | kRCFolderKeyCombos | [Rev.2 追加] |
| ホットキーマイグレーションフラグ | kCPYMigrateNewKeyCombo | kRCMigrateNewKeyCombo | [Rev.2 追加] |
| レガシーホットキー設定 | kCPYPrefHotKeysKey | kRCPrefHotKeysKey | [Rev.2 追加] |

#### Updates カテゴリ

| 設定項目 | Clipyキー | Revclipキー | デフォルト値 |
|---------|----------|------------|------------|
| 自動チェック | kCPYEnableAutomaticCheckKey | kRCEnableAutomaticCheckKey | YES |
| チェック間隔 (秒) | kCPYUpdateCheckIntervalKey | kRCUpdateCheckIntervalKey | 86400 | [Rev.2 追加] |

#### [Rev.2 追加] Beta カテゴリ (M-3対応: 修飾キー設定4つを含む)

| 設定項目 | Clipyキー | Revclipキー | デフォルト値 |
|---------|----------|------------|------------|
| プレーンテキスト貼付 | kCPYBetaPastePlainText | kRCBetaPastePlainText | YES |
| プレーンテキスト貼付の修飾キー (0:Cmd/1:Shift/2:Ctrl/3:Option) | kCPYBetaPastePlainTextModifier | kRCBetaPastePlainTextModifier | 0 (Cmd) | [Rev.2 追加] |
| 履歴削除 | kCPYBetaDeleteHistory | kRCBetaDeleteHistory | NO |
| 履歴削除の修飾キー | kCPYBetaDeleteHistoryModifier | kRCBetaDeleteHistoryModifier | 0 (Cmd) | [Rev.2 追加] |
| ペースト後に履歴を削除 | kCPYBetaPasteAndDeleteHistory | kRCBetaPasteAndDeleteHistory | NO | [Rev.2 追加] |
| ペースト&削除の修飾キー | kCPYBetapasteAndDeleteHistoryModifier | kRCBetapasteAndDeleteHistoryModifier | 0 (Cmd) | [Rev.2 追加] |
| スクリーンショット監視 | kCPYBetaObserveScreenshot | kRCBetaObserveScreenshot | NO |

#### [Rev.2 追加] Snippets カテゴリ

| 設定項目 | Clipyキー | Revclipキー |
|---------|----------|------------|
| スニペット削除アラート抑制 | kCPYSuppressAlertForDeleteSnippet | kRCSuppressAlertForDeleteSnippet | [Rev.2 追加] |

#### [Rev.2 追加] RCPasteService の修飾キー判定ロジック (M-3対応)

Clipyの `PasteService.swift` では、Beta機能として以下の修飾キー判定ロジックを実装している:

1. メニューからクリップを選択した時点で `NSEvent.modifierFlags` を確認
2. `pastePlainTextModifier` の値 (0=Cmd/1=Shift/2=Ctrl/3=Option) に応じて対応する修飾キーが押されているかチェック
3. 修飾キーが押されていれば対応するアクション（プレーンテキスト貼付、履歴削除、ペースト&削除）を実行

```objc
// RCPasteService.m
- (BOOL)isPressedModifier:(NSInteger)flag {
    NSEventModifierFlags flags = [NSEvent modifierFlags];
    switch (flag) {
        case 0: return (flags & NSEventModifierFlagCommand) != 0;
        case 1: return (flags & NSEventModifierFlagShift) != 0;
        case 2: return (flags & NSEventModifierFlagControl) != 0;
        case 3: return (flags & NSEventModifierFlagOption) != 0;
        default: return NO;
    }
}
```

### [Rev.2 追加] 3.5 スニペットフォルダ個別ホットキー (M-2対応)

Clipyの `HotKeyService.swift` はメイン/履歴/スニペット/履歴クリアの4つの全体ホットキーに加え、**スニペットフォルダごとの個別ホットキー** (`folderKeyCombos`) を実装している。

#### Clipy側の実装詳細

- `folderKeyCombos` はUserDefaultsに `NSKeyedArchiver` でアーカイブされた `[String: KeyCombo]` 辞書として保存 (キー = フォルダのidentifier)
- `setupSnippetHotKeys()` で起動時に全フォルダのホットキーを一括登録
- `registerSnippetHotKey(with:keyCombo:)` でフォルダ個別ホットキーの登録
- `unregisterSnippetHotKey(with:)` でフォルダ個別ホットキーの解除
- `popupSnippetFolder(_:)` でホットキー押下時に対象フォルダのスニペットメニューをポップアップ
- スニペットエディタUI (`CPYSnippetsEditorWindowController`) の `folderShortcutRecordView` (RecordView) でフォルダ選択時にホットキー設定可能

#### Revclip側の設計

```objc
// RCHotKeyService.h
@interface RCHotKeyService : NSObject

// フォルダ個別ホットキー
- (void)registerSnippetHotKeyWithIdentifier:(NSString *)identifier
                                    keyCode:(UInt32)keyCode
                                  modifiers:(UInt32)modifiers;
- (void)unregisterSnippetHotKeyWithIdentifier:(NSString *)identifier;
- (NSDictionary<NSString *, NSDictionary *> *)folderKeyCombos;
- (void)setupSnippetHotKeys;

@end
```

`RCSnippetEditorWindowController` のフォルダ選択時に `RCHotKeyRecorderView` を表示し、フォルダ個別のホットキーを設定可能にする。ホットキー押下時には対象フォルダの `RCMenuManager.popUpSnippetFolder:` を呼び出す。

---

## 4. 実装フェーズ

### Phase 1: 基盤構築 (推定: 2-3週間)

**目標**: アプリの骨格を完成させ、クリップボード監視〜履歴表示〜ペーストの基本フローを動作させる

| タスク | 詳細 | 優先度 |
|-------|------|--------|
| 1-1. プロジェクトセットアップ | [Rev.3 修正] ターミナルから .xcodeproj を生成/設定（xcodebuildで操作）。Bundle ID: `com.revclip.Revclip`。LSUIElement=YES。Deployment Target: macOS 14.0。Architectures: arm64 + x86_64 (Universal)。Xcode.appの手動操作は不要 | 最高 |
| 1-2. 定数・環境定義 | `RCConstants.h/.m` + `RCEnvironment.h/.m` (シングルトンDIコンテナ)。全UserDefaultsキーの定義（セクション3.4の全項目） | 最高 |
| 1-3. データベース層 | FMDB組込。`RCDatabaseManager` でスキーマ作成・マイグレーション。clip_items / snippet_folders / snippets テーブル | 最高 |
| 1-4. クリップボードモデル | `RCClipItem` / `RCClipData` (NSCoding準拠) | 最高 |
| 1-5. クリップボード監視 | `RCClipboardService` - dispatch_source タイマーで750usポーリング。NSPasteboard変更検出 → RCClipData作成 → ファイル保存 → DB INSERT | 最高 |
| 1-6. メニューマネージャー基盤 | `RCMenuManager` - NSStatusItem作成。クリップ履歴からNSMenu構築。基本メニュー項目（設定・終了）。data_hashベースのクリップ選択ロジック [Rev.2 修正] | 最高 |
| 1-7. ペーストサービス | `RCPasteService` - NSPasteboardへの書き戻し + CGEvent Cmd+Vシミュレーション + Beta修飾キー判定ロジック [Rev.2 修正] | 最高 |
| 1-8. Accessibility権限 | `RCAccessibilityService` - AXIsProcessTrustedWithOptions + 権限要求アラート | 高 |
| 1-9. UserDefaults初期化 | `RCUtilities` - 全デフォルト設定の登録 (セクション3.4の全項目のデフォルト値) [Rev.2 修正] | 高 |
| 1-10. [Rev.2 追加] macOS 16プライバシー対応基盤 | `RCClipboardService` に accessBehavior チェック + detect メソッド対応の条件分岐を組込 | 高 |

**Phase 1 完了基準**: メニューバーにアイコン表示 → クリップボードコピーを検出 → 履歴メニューに表示 → クリックでペースト実行

### Phase 2: UI・UX完成 (推定: 2-3週間)

**目標**: Clipyと同等のUI/UXを完全再現する

| タスク | 詳細 | 優先度 |
|-------|------|--------|
| 2-1. グローバルホットキー | `RCHotKeyService` - Carbon API `RegisterEventHotKey` 直接使用。Cmd+Shift+V (メイン) / Cmd+Ctrl+V (履歴) / Cmd+Shift+B (スニペット) + 履歴クリアホットキー [Rev.2 修正] | 最高 |
| 2-1a. [Rev.2 追加] フォルダ個別ホットキー | `RCHotKeyService` に `registerSnippetHotKey` / `unregisterSnippetHotKey` 実装。フォルダidentifierベースの辞書管理 | 高 |
| 2-2. ホットキーレコーダーUI | `RCHotKeyRecorderView` - カスタムNSView。キー入力を受け取りKeyCombo表示。KeyHolderと同等のUI。[Rev.2 追加] Option単独/Option+Shift組み合わせの警告表示 | 高 |
| 2-3. 設定ウィンドウ | `RCPreferencesWindowController` - 7タブ切替。Clipyと同一レイアウト | 高 |
| 2-3a. General設定パネル | 最大履歴数 / ログイン起動 / ステータスアイコン / ペーストコマンド / ペースト後並べ替え / 同一履歴の上書き・コピー [Rev.2 修正] | 高 |
| 2-3b. Menu設定パネル | インライン数 / フォルダ内数 / タイトル長 / 番号表示 / 番号起点(0/1) / ツールチップ / ツールチップ最大長 / 画像表示 / アイコンサイズ / アイコン表示 / 数字キーEquivalent / サムネイルサイズ / 履歴クリアメニュー項目 [Rev.2 修正] | 高 |
| 2-3c. Type設定パネル | 保存対象タイプ（String/RTF/RTFD/PDF/Filenames/URL/TIFF）チェックボックス | 高 |
| 2-3d. Exclude設定パネル | 除外アプリ追加/削除。NSOpenPanel + NSTableView | 高 |
| 2-3e. Shortcuts設定パネル | 4つのショートカット記録（メイン/履歴/スニペット/履歴クリア） [Rev.2 修正: 履歴クリア追加] | 高 |
| 2-3f. Updates設定パネル | Sparkle連携。自動チェック間隔。バージョン表示 | 中 |
| 2-3g. Beta設定パネル | プレーンテキスト貼付 + 修飾キー選択 / 履歴削除 + 修飾キー選択 / ペースト&削除 + 修飾キー選択 / スクリーンショット監視 [Rev.2 修正: 修飾キー4つ追加] | 中 |
| 2-4. スニペットエディタ | `RCSnippetEditorWindowController` - NSSplitView + NSOutlineView + NSTextView。フォルダ/スニペットのCRUD。ドラッグ&ドロップ並替え。フォルダ個別ホットキーレコーダー [Rev.2 修正] | 高 |
| 2-5. スニペットインポート/エクスポート | NSXMLDocument / NSXMLParser でXML処理。Clipyフォーマット互換 | 中 |
| 2-6. 除外アプリサービス | `RCExcludeAppService` - NSWorkspace通知でフロントアプリ監視。1Password等特殊アプリ対応 | 高 |
| 2-7. データクリーンアップ | `RCDataCleanService` - 30分間隔タイマー。上限超過履歴削除 + 孤立ファイル削除 | 中 |
| 2-8. メニュー高度機能 | サムネイル画像表示 / カラーコードプレビュー / ツールチップ / 数字キーEquivalent / フォルダ分割表示 | 高 |
| 2-9. [Rev.2 追加] UIコンポーネント | `RCDesignableView` / `RCDesignableButton` の実装。設定画面タブバー等で使用 | 中 |

**Phase 2 完了基準**: 設定画面全タブ動作（全設定項目反映）。スニペット作成・編集・ドラッグ並替え。ホットキーによるメニューポップアップ（フォルダ個別含む）。除外アプリ動作。Beta機能の修飾キー動作。

### Phase 3: ブランディング・配布準備 (推定: 1-2週間)

**目標**: Revclipとしての完全ブランディングと配布可能な状態にする

| タスク | 詳細 | 優先度 |
|-------|------|--------|
| 3-1. アイコン・ブランディング | Revclipオリジナルアイコン作成 (AppIcon, StatusBar icon)。全サイズ生成 (16x16 ~ 1024x1024) | 最高 |
| 3-2. ローカライズ | [Rev.2 修正] en/ja/de/zh-Hans/it の5言語をサポート。Clipyの翻訳を参考に「Clipy」→「Revclip」に全置換 | 高 |
| 3-3. Sparkle統合 | [Rev.2 修正] Sparkle 2.x framework組込。**EdDSA (ed25519) 署名鍵生成** (`generate_keys` ツール使用)。appcast.xml ホスティング設定。XPC Service経由のセキュアなアップデート | 高 |
| 3-4. ログインアイテム | `RCLoginItemService` - SMAppService (macOS 13+) でログイン時自動起動 | 高 |
| 3-5. "Applicationsフォルダへ移動"機能 | LetsMove (Obj-C版) 組込 or 自前実装 | 中 |
| 3-6. スクリーンショット監視 | NSMetadataQuery でスクリーンショットフォルダ監視 (Beta機能) | 低 |
| 3-7. コード署名 | Apple Developer証明書でコード署名。Hardened Runtime有効化 | 最高 |
| 3-8. 公証 (Notarization) | `xcrun notarytool submit` でApple公証取得 | 最高 |
| 3-9. DMG作成 | create-dmg等でインストーラーDMG作成。背景画像・レイアウト設定 | 高 |
| 3-10. [Rev.2 修正] テスト | 全Serviceクラス・全Managerクラスのユニットテスト + 全機能の手動テスト。Apple Silicon実機検証。詳細はセクション9参照 | 最高 |
| 3-11. クラッシュレポート | 将来的にSentry等の導入検討（初期リリースではオプション） | 低 |
| 3-12. [Rev.2 追加] macOS 16動作検証 | macOS 16ベータ/正式版でのクリップボードプライバシー動作検証 | 高 |

---

## 5. ビルド・配布戦略

### [Rev.3 修正] 5.1 ビルドシステム

> **制約**: Xcode.app (IDE) は一切使用しない。すべてのビルド操作はターミナル（Claude Code）から
> Xcode Command Line Tools（xcodebuild, ibtool, actool, codesign, xcrun等）で完結させる。

#### 5.1.1 ビルド方式の選定: xcodebuild + .xcodeproj

| 方式 | 利点 | 欠点 | 採否 |
|------|------|------|------|
| **xcodebuild + .xcodeproj** | XIB/Asset Catalog/Framework組込を自動処理。署名・公証が確実。Apple公式ツールチェーン | .xcodeprojファイルの生成が必要（ただしターミナルから可能） | **採用** |
| Makefile + clang 純粋ビルド | 依存がシンプル。ビルドプロセスが透明 | XIBコンパイル・Asset Catalog処理・Framework埋込を手動で全部記述する必要あり。Sparkle.frameworkの@rpath設定が煩雑 | 不採用 |

**選定理由**: Revclipは XIBファイル（MainMenu.xib + 設定画面8個 + スニペットエディタ1個）、Asset Catalog（AppIcon + StatusBarIcon等）、外部Framework（Sparkle 2.x）を使用するため、これらのリソースコンパイル・バンドル構成を自動処理する xcodebuild が最適。.xcodeprojファイルは手動生成（PBXProject形式のテキストファイル）またはスクリプトで生成可能であり、Xcode.appを開く必要はない。

#### 5.1.2 .xcodeproj の生成方法

.xcodeprojの `project.pbxproj` はテキストファイル（Apple Plist形式）であり、以下のいずれかの方法でターミナルから生成する:

```bash
# 方法1: xcodebuild -create コマンド（推奨）
# project.pbxproj をテンプレートから手動生成し、Scripts/generate_project.sh で管理

# 方法2: xcodegenを使用（Homebrew経由でインストール）
brew install xcodegen
# project.yml を定義してから生成
xcodegen generate
```

**project.yml（xcodegen使用時の定義ファイル）**:

```yaml
name: Revclip
options:
  deploymentTarget:
    macOS: "14.0"
  bundleIdPrefix: com.revclip
  xcodeVersion: "16.0"
  createIntermediateGroups: true

targets:
  Revclip:
    type: application
    platform: macOS
    sources:
      - path: Revclip
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.revclip.Revclip
        MACOSX_DEPLOYMENT_TARGET: "14.0"
        ARCHS: "arm64 x86_64"
        ONLY_ACTIVE_ARCH: false
        INFOPLIST_FILE: Revclip/Info.plist
        CODE_SIGN_ENTITLEMENTS: Revclip/Revclip.entitlements
        ENABLE_HARDENED_RUNTIME: true
        CODE_SIGN_IDENTITY: "Developer ID Application"
        CLANG_ENABLE_OBJC_ARC: true
        GCC_PREFIX_HEADER: Revclip/Revclip-Prefix.pch
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        LD_RUNPATH_SEARCH_PATHS: "@executable_path/../Frameworks"
      configs:
        Release:
          ONLY_ACTIVE_ARCH: false
        Debug:
          ONLY_ACTIVE_ARCH: true
    dependencies:
      - framework: Revclip/Vendor/Sparkle.framework
        embed: true

  RevclipTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: RevclipTests
    dependencies:
      - target: Revclip
    settings:
      base:
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/Revclip.app/Contents/MacOS/Revclip"
        BUNDLE_LOADER: "$(TEST_HOST)"
```

#### 5.1.3 XIBファイルのコンパイル（ibtool）

XIBファイル（Interface Builder形式）は `ibtool` コマンドでコンパイルする。xcodebuildのビルドプロセスに自動で組み込まれるが、個別にコンパイルする場合:

```bash
# XIBファイルを .nib にコンパイル
ibtool --compile Revclip/Resources/MainMenu.nib Revclip/Resources/MainMenu.xib

# 設定画面の各XIBをコンパイル
ibtool --compile build/RCGeneralPreferenceVC.nib \
  Revclip/UI/Preferences/RCGeneralPreferenceVC.xib

# すべてのXIBを一括コンパイル（スクリプト例）
for xib in $(find Revclip -name "*.xib"); do
  nib="${xib%.xib}.nib"
  echo "Compiling: $xib -> $nib"
  ibtool --compile "$nib" "$xib"
done

# XIBのエラーチェック（コンパイルせずにバリデーションのみ）
ibtool --warnings --errors Revclip/Resources/MainMenu.xib
```

**注意**: xcodebuild でビルドする場合、XIBのコンパイルはビルドプロセスの一部として自動実行されるため、上記の手動コマンドは個別デバッグ時にのみ使用する。

#### 5.1.4 Asset Catalogのコンパイル（actool）

Asset Catalog (`.xcassets`) は `actool` コマンドでコンパイルする。xcodebuildのビルドプロセスに自動で組み込まれるが、個別にコンパイルする場合:

```bash
# Asset Catalogをコンパイル
xcrun actool \
  --compile build/Release/Revclip.app/Contents/Resources \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --app-icon AppIcon \
  --output-partial-info-plist build/assetcatalog_generated_info.plist \
  Revclip/Resources/Assets.xcassets

# AppIconのみを .icns に変換（DMG作成用）
xcrun actool \
  --compile build/Icons \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --app-icon AppIcon \
  --output-partial-info-plist /dev/null \
  Revclip/Resources/Assets.xcassets
```

**注意**: xcodebuild でビルドする場合、Asset Catalogのコンパイルはビルドプロセスの一部として自動実行される。

#### 5.1.5 ビルドコマンド（xcodebuild）

```bash
# --- Debug ビルド（開発時） ---
xcodebuild \
  -project Revclip.xcodeproj \
  -scheme Revclip \
  -configuration Debug \
  -arch arm64 \
  ONLY_ACTIVE_ARCH=YES \
  build

# --- Release ビルド (Universal Binary: Apple Silicon + Intel) ---
xcodebuild \
  -project Revclip.xcodeproj \
  -scheme Revclip \
  -configuration Release \
  -arch arm64 -arch x86_64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="Developer ID Application: YOUR_NAME (TEAM_ID)" \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  OTHER_CODE_SIGN_FLAGS="--options=runtime" \
  build

# --- ビルド成果物の確認 ---
ls -la build/Release/Revclip.app/
file build/Release/Revclip.app/Contents/MacOS/Revclip
# 出力例: Mach-O universal binary with 2 architectures:
#   arm64, x86_64

# --- クリーンビルド ---
xcodebuild \
  -project Revclip.xcodeproj \
  -scheme Revclip \
  clean

# --- ビルドログの詳細表示 ---
xcodebuild \
  -project Revclip.xcodeproj \
  -scheme Revclip \
  -configuration Debug \
  build 2>&1 | tee build.log
```

#### 5.1.6 テスト実行（xcodebuild test）

```bash
# ユニットテスト実行
xcodebuild \
  -project Revclip.xcodeproj \
  -scheme Revclip \
  -configuration Debug \
  test

# 特定のテストクラスのみ実行
xcodebuild \
  -project Revclip.xcodeproj \
  -scheme Revclip \
  -configuration Debug \
  -only-testing:RevclipTests/RCClipboardServiceTests \
  test

# テスト結果の詳細表示（xcpretty使用）
xcodebuild \
  -project Revclip.xcodeproj \
  -scheme Revclip \
  test 2>&1 | xcpretty --report junit
```

#### 5.1.7 コード署名（codesign）

```bash
# アプリバンドルへのコード署名（xcodebuildで自動署名される場合は不要）
codesign --force --deep --sign "Developer ID Application: YOUR_NAME (TEAM_ID)" \
  --options runtime \
  --entitlements Revclip/Revclip.entitlements \
  build/Release/Revclip.app

# Sparkle.frameworkの署名確認
codesign --verify --deep --strict build/Release/Revclip.app/Contents/Frameworks/Sparkle.framework

# 署名の検証
codesign --verify --verbose=4 build/Release/Revclip.app
spctl --assess --type execute --verbose build/Release/Revclip.app
```

### [Rev.3 修正] 5.2 プロジェクト設定

> **注記**: 以下の設定はすべて .xcodeproj の project.pbxproj（テキストファイル）または
> xcodegen の project.yml で定義する。Xcode.app を開く必要はない。

| 項目 | 値 | 設定場所 |
|------|-----|---------|
| Bundle Identifier | `com.revclip.Revclip` | project.yml / Info.plist |
| Deployment Target | macOS 14.0 | project.yml (MACOSX_DEPLOYMENT_TARGET) |
| Architectures | arm64, x86_64 (Universal) | project.yml (ARCHS) |
| Build Active Architecture Only | Release: NO, Debug: YES | project.yml (ONLY_ACTIVE_ARCH) |
| Hardened Runtime | YES | project.yml (ENABLE_HARDENED_RUNTIME) |
| Code Signing | Developer ID Application | project.yml (CODE_SIGN_IDENTITY) |
| LSUIElement | YES | Info.plist |
| NSMainNibFile | MainMenu | Info.plist |
| ARC (Automatic Reference Counting) | YES | project.yml (CLANG_ENABLE_OBJC_ARC) |
| Framework Search Paths | `$(PROJECT_DIR)/Revclip/Vendor` | project.yml |
| Runpath Search Paths | `@executable_path/../Frameworks` | project.yml (LD_RUNPATH_SEARCH_PATHS) |

### [Rev.2 修正] 5.3 Entitlements (m-6対応)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Hardened Runtime: Apple Events送信のために必要 -->
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
```

**[Rev.2 追加] Entitlements に関する補足事項**:

- **App Sandboxは有効にしない**: クリップボード監視・CGEventポスト・Accessibility API使用のため、Sandboxとは非互換。Hardened Runtimeのみ有効化する
- **Accessibility API**: TCC (Transparency, Consent, and Control) で制御されるため、Entitlementは不要。`AXIsProcessTrustedWithOptions` でランタイムに権限要求する。ただし、Entitlementではなくシステム環境設定の「プライバシーとセキュリティ > アクセシビリティ」でユーザーが手動許可する必要がある
- **CGEvent.post + Hardened Runtime**: Hardened Runtime環境下で `CGEventPost` を使用する場合、Accessibility権限（TCC）が付与されていれば動作する。追加のEntitlementは不要。ただし、**Hardened Runtime + CGEvent の組み合わせはPhase 1の早い段階で動作検証を行うこと**
- **macOS 16+ Pasteboard Privacy**: 新しいプライバシー保護に対して特定のEntitlementは不要だが、`NSPasteboard.accessBehavior` による動作確認が必要

### [Rev.3 修正] 5.4 公証 (Notarization) フロー

> **注記**: 以下のコマンドはすべてターミナルから実行する。Xcode.appの操作は一切不要。

```bash
#!/bin/bash
# =============================================================
# Scripts/notarize.sh - Revclip ビルド・署名・公証・DMG作成
# すべてターミナル（Claude Code）から実行可能
# =============================================================

set -euo pipefail

VERSION="${1:-1.0.0}"
APP_NAME="Revclip"
PROJECT="Revclip.xcodeproj"
SCHEME="Revclip"
APP_PATH="build/Release/${APP_NAME}.app"
DMG_PATH="${APP_NAME}-${VERSION}.dmg"
ZIP_PATH="${APP_NAME}.zip"

# --- 前提条件の確認 ---
echo "=== 前提条件チェック ==="
xcodebuild -version           # Xcode Command Line Tools の確認
xcrun --find notarytool        # notarytool の存在確認
xcrun --find stapler           # stapler の存在確認

# --- Step 1: クリーンビルド (Universal Binary) ---
echo "=== Step 1: Release ビルド (Universal Binary) ==="
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -arch arm64 -arch x86_64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="Developer ID Application: YOUR_NAME (TEAM_ID)" \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  OTHER_CODE_SIGN_FLAGS="--options=runtime" \
  clean build

# --- Step 2: 署名の検証 ---
echo "=== Step 2: コード署名の検証 ==="
codesign --verify --verbose=4 "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH"

# --- Step 3: ZIP化 (公証提出用) ---
echo "=== Step 3: ZIP作成 ==="
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# --- Step 4: 公証提出 (xcrun notarytool) ---
echo "=== Step 4: Apple公証提出 ==="
# [Rev.4 修正] notarytool では --keychain-profile を使用（旧altoolの --password "@keychain:..." は不可）
SUBMIT_OUTPUT=$(xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile "AC_PASSWORD" \
  --wait 2>&1)
echo "$SUBMIT_OUTPUT"

# --- Step 5: 公証ログの確認（エラー時のデバッグ用） ---
echo "=== Step 5: 公証ログ確認 ==="
# [Rev.4 修正] submit の出力から submission ID を抽出
# notarytool submit --wait の出力例:
#   Successfully uploaded file (略)
#     id: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#   (略)
SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | grep -m1 '  id:' | awk '{print $2}')
echo "Submission ID: $SUBMISSION_ID"

# [Rev.4 修正] --keychain-profile を使用してログ取得
xcrun notarytool log "$SUBMISSION_ID" \
  --keychain-profile "AC_PASSWORD"

# --- Step 6: ステープル (公証結果をアプリに埋込) ---
echo "=== Step 6: Staple ==="
xcrun stapler staple "$APP_PATH"

# --- Step 7: DMG作成 ---
echo "=== Step 7: DMG作成 ==="
# create-dmg がインストールされていない場合: brew install create-dmg
create-dmg \
  --volname "$APP_NAME" \
  --volicon "Distribution/AppIcon.icns" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "${APP_NAME}.app" 150 200 \
  --app-drop-link 450 200 \
  --background "Distribution/dmg_background.png" \
  "$DMG_PATH" \
  "$APP_PATH"

# --- Step 8: DMGにもステープル ---
echo "=== Step 8: DMGにステープル ==="
xcrun stapler staple "$DMG_PATH"

# --- Step 9: 最終検証 ---
echo "=== Step 9: 最終検証 ==="
xcrun stapler validate "$APP_PATH"
xcrun stapler validate "$DMG_PATH"
echo "=== 完了: $DMG_PATH ==="
```

### [Rev.2 修正] 5.5 自動アップデート (Sparkle) (m-4対応)

- **Sparkle 2.x** (Objective-C版) を使用
  - Clipyで使用されていた **Sparkle 1.x (1.26.0)** からの移行となる
  - Sparkle 1.x と 2.x の主な差異:
    - **署名方式**: DSA (1.x) → **EdDSA (ed25519)** (2.x) — `generate_keys` ツールで鍵ペアを生成
    - **アーキテクチャ**: インプロセス (1.x) → **XPC Service経由** (2.x) でセキュリティが向上
    - **Info.plist**: `SUPublicDSAKeyFile` (1.x) → `SUPublicEDKey` (2.x) に変更
    - **feedURL設定**: `SUFeedURL` は同じだが、appcast.xmlの署名フォーマットが異なる
    - **Hardened Runtime**: Sparkle 2.xはHardened Runtime完全対応
- EdDSA (ed25519) 署名鍵を生成
- appcast.xml をWebサーバ/GitHub Releases等でホスティング
- `SUFeedURL` を Info.plist に設定

### [Rev.3 追加] 5.6 開発フロー（ターミナル完結）

> **重要**: Revclipの開発はすべて **Claude Code（ターミナル）** から実行する。
> Xcode.app（IDE）の手動操作は **一切不要** である。

#### 5.6.1 開発環境の前提

[Rev.4 修正] `ibtool`、`actool`、`xcodebuild` は **Xcode Command Line Tools 単体では動作しない**。これらのツールは Xcode.app のインストールが前提となる。ただし、Xcode.app を IDE として手動操作する必要は一切なく、App Store からインストールするだけでよい（Xcode.app を開く必要もない）。

| 項目 | ツール | インストール方法 |
|------|--------|-----------------|
| **Xcode.app** [Rev.4 修正] | Xcode.app (必須。ibtool/actool/xcodebuild の動作に必要) | App Storeからインストール（IDEとしての手動操作は不要） |
| コンパイラ | clang (Xcode.app同梱) | Xcode.appインストール時に同梱 |
| ビルドツール | xcodebuild | Xcode.app同梱（Command Line Tools単体では不可） |
| XIBコンパイラ | ibtool | Xcode.app同梱（Command Line Tools単体では不可） |
| Asset Catalogコンパイラ | actool (xcrun actool) | Xcode.app同梱（Command Line Tools単体では不可） |
| コード署名 | codesign | macOS標準 |
| 公証 | xcrun notarytool | Xcode.app同梱 |
| プロジェクト生成 | xcodegen (オプション) | `brew install xcodegen` |
| DMG作成 | create-dmg | `brew install create-dmg` |
| テスト整形 | xcpretty (オプション) | `gem install xcpretty` |

```bash
# 開発環境セットアップ（初回のみ）

# [Rev.4 修正] Step 1: Xcode.appのインストール（App Storeから）
# App Store で "Xcode" を検索してインストールする。
# インストール後、Xcode.appを開く必要はない。

# [Rev.4 修正] Step 2: xcode-select でXcode.appのDeveloperディレクトリを指定
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

# Step 3: ライセンス承諾（初回のみ）
sudo xcodebuild -license accept

# Step 4: オプションツールのインストール
brew install xcodegen create-dmg          # オプションツール
```

#### 5.6.2 日常の開発コマンド

```bash
# --- プロジェクト生成（project.ymlを変更した場合） ---
cd /path/to/Revclip
xcodegen generate

# --- Debugビルド（開発中） ---
xcodebuild \
  -project Revclip.xcodeproj \
  -scheme Revclip \
  -configuration Debug \
  build

# --- ビルド＆実行（ターミナルから直接起動） ---
xcodebuild \
  -project Revclip.xcodeproj \
  -scheme Revclip \
  -configuration Debug \
  build && \
open build/Debug/Revclip.app

# --- ビルドエラーの確認 ---
xcodebuild \
  -project Revclip.xcodeproj \
  -scheme Revclip \
  -configuration Debug \
  build 2>&1 | grep -E "error:|warning:"

# --- ユニットテスト実行 ---
xcodebuild \
  -project Revclip.xcodeproj \
  -scheme Revclip \
  -configuration Debug \
  test

# --- 特定テストクラスのみ実行 ---
xcodebuild \
  -project Revclip.xcodeproj \
  -scheme Revclip \
  -only-testing:RevclipTests/RCClipboardServiceTests \
  test

# --- クリーン ---
xcodebuild \
  -project Revclip.xcodeproj \
  -scheme Revclip \
  clean

# --- XIBの個別コンパイル（デバッグ用） ---
ibtool --warnings --errors Revclip/Resources/MainMenu.xib

# --- ビルド設定の一覧表示 ---
xcodebuild \
  -project Revclip.xcodeproj \
  -scheme Revclip \
  -showBuildSettings
```

#### 5.6.3 リリースビルド・署名・公証

```bash
# --- Releaseビルド (Universal Binary) ---
xcodebuild \
  -project Revclip.xcodeproj \
  -scheme Revclip \
  -configuration Release \
  -arch arm64 -arch x86_64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="Developer ID Application: YOUR_NAME (TEAM_ID)" \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  OTHER_CODE_SIGN_FLAGS="--options=runtime" \
  clean build

# --- 署名検証 ---
codesign --verify --verbose=4 build/Release/Revclip.app
spctl --assess --type execute --verbose build/Release/Revclip.app

# --- 公証 ---
ditto -c -k --keepParent build/Release/Revclip.app Revclip.zip
# [Rev.4 修正] notarytool では --keychain-profile を使用
xcrun notarytool submit Revclip.zip \
  --keychain-profile "AC_PASSWORD" \
  --wait
xcrun stapler staple build/Release/Revclip.app

# --- DMG作成・ステープル ---
create-dmg \
  --volname "Revclip" \
  --icon "Revclip.app" 150 200 \
  --app-drop-link 450 200 \
  "Revclip-1.0.0.dmg" \
  build/Release/Revclip.app
xcrun stapler staple "Revclip-1.0.0.dmg"
```

#### 5.6.4 Apple公証パスワードのキーチェーン登録

```bash
# [Rev.4 修正] App Store Connect の App-Specific Password をキーチェーンプロファイルとして保存
# （初回のみ。以降は --keychain-profile "AC_PASSWORD" で参照可能）
# store-credentials は対話的にApple ID、Team ID、App-Specific Passwordを入力する
xcrun notarytool store-credentials "AC_PASSWORD" \
  --apple-id "your@email.com" \
  --team-id "TEAM_ID" \
  --password "xxxx-xxxx-xxxx-xxxx"
# 注: --password オプションを省略すると対話的にパスワード入力が求められる（推奨）
```

#### 5.6.5 Xcode.app を使わないことの確認事項

| 操作 | Xcode.appでの操作 | ターミナルでの代替 |
|------|-------------------|-------------------|
| プロジェクト作成 | File > New Project | `xcodegen generate`（project.ymlから生成） |
| ソースファイル追加 | File > Add Files | project.yml の `sources:` を編集 → `xcodegen generate` |
| XIB編集 | Interface Builder (GUI) | XIBファイルをテキストエディタで直接編集（XML形式）、またはコードでUI構築 |
| ビルド | Cmd+B | `xcodebuild build` |
| 実行 | Cmd+R | `xcodebuild build && open build/Debug/Revclip.app` |
| テスト | Cmd+U | `xcodebuild test` |
| 署名設定 | Signing & Capabilities GUI | project.yml の `CODE_SIGN_IDENTITY` 等を設定 |
| スキーム設定 | Scheme Editor GUI | `.xcscheme` ファイルを直接編集（XML形式） |

**XIBファイルの編集について**: XIBファイルはXML形式のテキストファイルであるため、テキストエディタで直接編集可能。ただし、複雑なレイアウト変更が必要な場合は、XIBの代わりにコードベースのUI構築（`NSView`/`NSWindow`のプログラム的構築）も選択肢として検討する。初期実装ではClipyのXIBレイアウトを参考にXMLとして再構築し、ibtoolでコンパイル検証する。

#### 5.6.6 Makefile ラッパー（便利コマンド）

プロジェクトルートに以下の `Makefile` を配置し、頻繁に使うコマンドを短縮する:

```makefile
# Revclip Makefile - すべてターミナルから実行
.PHONY: setup build debug release test clean run sign notarize dmg

PROJECT = Revclip.xcodeproj
SCHEME  = Revclip
APP_DEBUG   = build/Debug/Revclip.app
APP_RELEASE = build/Release/Revclip.app

# プロジェクト生成 (project.yml → .xcodeproj)
setup:
	xcodegen generate

# Debug ビルド
build: debug
debug:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug build

# Release ビルド (Universal Binary)
release:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-arch arm64 -arch x86_64 ONLY_ACTIVE_ARCH=NO \
		CODE_SIGN_IDENTITY="Developer ID Application: YOUR_NAME (TEAM_ID)" \
		DEVELOPMENT_TEAM=YOUR_TEAM_ID \
		OTHER_CODE_SIGN_FLAGS="--options=runtime" build

# テスト実行
test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug test

# クリーン
clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
	rm -rf build/

# Debug ビルド & 実行
run: debug
	open $(APP_DEBUG)

# 署名検証
sign:
	codesign --verify --verbose=4 $(APP_RELEASE)
	spctl --assess --type execute --verbose $(APP_RELEASE)

# 公証 (Scripts/notarize.sh を呼び出し)
notarize:
	bash Scripts/notarize.sh

# DMG作成
dmg:
	bash Scripts/create_dmg.sh
```

使用例:
```bash
make setup    # プロジェクト生成
make build    # Debugビルド
make run      # ビルド＆実行
make test     # テスト
make release  # Releaseビルド
make sign     # 署名検証
make clean    # クリーン
```

### 5.7 CI/CD (将来)

GitHub Actions で以下を自動化検討:
- ビルド + テスト (PR時)
- リリースビルド + 公証 + DMG作成 (タグプッシュ時)
- appcast.xml自動更新

---

## 6. リスクと対策

### [Rev.2 修正] 6.1 技術的リスク

| リスク | 影響度 | 発生確率 | 対策 |
|--------|--------|---------|------|
| **[Rev.2 追加] macOS 16 クリップボードプライバシー保護 (C-1)** | **最高** | **確定** (macOS 15.4プレビュー済み、macOS 16正式導入) | 下記セクション 6.5 で詳細対応設計を記載 |
| **[Rev.2 修正] Carbon API (RegisterEventHotKey) の制限** | **高** | **一部確定** (macOS Sequoia 15で既にOption系修飾キー制限あり) | 下記セクション 6.6 で詳細対応設計を記載 |
| **Accessibility API制限強化** — macOS Sequoiaでの権限管理厳格化 | 中 | 中 | Accessibility権限の丁寧なガイダンスUI。TCC (Transparency, Consent, and Control) 変更への迅速対応体制 |
| **NSPasteboardポーリングの非効率性** — Clipyと同じ750usポーリング | 低 | 確定 | CPU負荷は極めて低い（changeCount比較のみ）。より効率的な方法は現状macOSに存在しない。dispatch_sourceタイマーでGCD最適化 |
| **Realm→SQLiteデータ移行不要** — 新規アプリのため既存データなし | - | - | Clipyからの移行ツールは初期スコープ外。将来的にインポート機能として検討可能 |
| **Objective-Cの開発者人材** — Swift全盛の中でObj-C人材の確保 | 中 | 中 | Obj-Cは成熟した言語であり学習コストは低い。macOS APIドキュメントはObj-C例が豊富。AI支援開発で補完可能 |

### 6.2 互換性リスク

| リスク | 対策 |
|--------|------|
| macOS 15.x (Sequoia) の新しいプライバシー制限 | Sequoia最新ベータでの継続的テスト。WWDC資料の追従 |
| Apple Silicon + Rosetta2環境の差異 | Universal Binary (arm64 + x86_64) でビルド。両アーキテクチャでテスト |
| Sparkle 2.xとHardened Runtimeの互換性 | Sparkle 2.x は Hardened Runtime対応済み。XPC Service経由のアップデート |
| Xcode 16以降のビルドツールチェーン変更 | 最新Xcodeでの定期ビルド確認 |

### 6.3 UXリスク

| リスク | 対策 |
|--------|------|
| Clipyユーザーの移行体験 | スニペットXMLインポート機能でClipyスニペットを移行可能に。[Rev.2 追加] 初回起動時のClipy設定移行検討 (セクション6.7) |
| ホットキーレコーダーUIのKeyHolderとの差異 | KeyHolderのUIを忠実に再現。同じキーコンボ表現を使用 |
| 設定画面の見た目差異 | Clipyと同一のXIBレイアウトを再現。スクリーンショット比較テスト |

### 6.4 配布リスク

| リスク | 対策 |
|--------|------|
| 公証の失敗 | Hardened Runtime + 正しいEntitlements + コード署名の確認。`xcrun notarytool log` で詳細ログ確認 |
| App Sandboxを使わないことによるApp Store配布不可 | App Storeではなく、Webサイト直接配布 + DMG形式。公証でGatekeeperはパス |
| 自動アップデートの信頼性 | Sparkle 2.x のEdDSA署名で改ざん防止。HTTPSホスティング必須 |

### [Rev.2 追加] 6.5 macOS 16 クリップボードプライバシー保護への対応設計 (C-1)

#### 概要

macOS 15.4で開発者プレビュー、macOS 16 (2025秋) で正式導入される「Paste from Other Apps」プライバシー機能により、ユーザー操作（Cmd+V等）を伴わないプログラムによるペーストボード読み取りに対して、システムがアラートを表示するようになる。

Revclipのコア機能である「クリップボード監視（750usポーリング）」は、NSPasteboardの内容をプログラムから読み取る動作であり、macOS 16以降ではこのプライバシー保護の対象となる。

#### 影響度: 最高

- changeCountの比較自体はアラートなしで可能だが、ペーストボードの**内容読み取り**（`stringForType:`, `dataForType:`, `types` 等）でアラートが発生する
- ユーザーが「Allow」を選択しない限り、クリップボード監視機能が動作しなくなる

#### 対応設計

**1. `NSPasteboard.accessBehavior` による事前チェック (macOS 16+)**

```objc
// RCClipboardService.m
- (void)createClipFromPasteboard {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];

    // macOS 16+: ペーストボードアクセス許可状態を確認
    if (@available(macOS 16.0, *)) {
        NSPasteboardAccessBehavior behavior = pasteboard.accessBehavior;
        if (behavior == NSPasteboardAccessBehaviorDenied) {
            // アクセス拒否 — ユーザーに再許可を案内
            [self notifyPasteboardAccessDenied];
            return;
        }
    }

    // 通常のクリップボード読み取り処理
    // ...
}
```

**2. `detect` メソッドによるアラート回避戦略 (macOS 16+)**

```objc
// macOS 16+: detectでアラートなしにデータ型を確認可能
if (@available(macOS 16.0, *)) {
    [pasteboard detectValuesForPatterns:@[NSPasteboardDetectionPatternProbableWebURL,
                                          NSPasteboardDetectionPatternProbableWebSearch]
                      completionHandler:^(NSDictionary *values, NSError *error) {
        // アラートなしでペーストボード上のデータパターンを検出
    }];
}
```

**3. 初回起動時のユーザーガイダンスUX**

```
┌─────────────────────────────────────────────┐
│  Revclip はクリップボードの内容を           │
│  監視するためにペーストボードへの            │
│  アクセス許可が必要です。                    │
│                                             │
│  macOSからアクセス許可を求めるダイアログが   │
│  表示された場合は「Allow」を選択してください。│
│                                             │
│  [設定を開く]  [後で]                        │
└─────────────────────────────────────────────┘
```

- 初回起動時（macOS 16以降）に上記ガイダンスアラートを表示
- `accessBehavior` が `denied` の場合、メニューバーアイコンにバッジを表示し再許可を案内
- システム環境設定の「プライバシーとセキュリティ > ペーストボードアクセス」への誘導

**4. Deployment Targetとの関係**

- macOS 14.0 をDeployment Targetとしているため、macOS 16 APIは `@available(macOS 16.0, *)` で条件分岐
- macOS 14/15 では従来通りのポーリング動作
- macOS 16以降ではプライバシー対応ロジックを有効化

### [Rev.2 追加] 6.6 macOS Sequoia ホットキー制限への対応設計 (C-2)

#### 概要

macOS Sequoia 15 で、`RegisterEventHotKey` においてOption単独またはOption+Shiftのみの修飾キー組み合わせが**機能しなくなった**。これはセキュリティ上の変更（パスワード入力時のキーロギング防止）であり、Appleが意図的に行った制限である。

#### 影響度: 高 / 発生確率: 確定（既に発生している事実）

- Clipyのデフォルトホットキー（Cmd+Shift+V / Cmd+Ctrl+V / Cmd+Shift+B）は**影響を受けない**（Cmd修飾キーを含むため）
- ユーザーがOption単独（例: Option+V）やOption+Shift（例: Option+Shift+V）のカスタムホットキーを設定した場合に**動作しない**
- この制限はmacOS Sequoia 15以降で恒久的であり、将来のmacOSでも維持される見込み

#### 対応設計

**1. ホットキーレコーダーUI (`RCHotKeyRecorderView`) での警告表示**

```objc
// RCHotKeyRecorderView.m
- (BOOL)validateKeyCombo:(UInt32)keyCode modifiers:(UInt32)modifiers {
    // Option単独 or Option+Shift のみの修飾キー組み合わせを検出
    BOOL hasOption = (modifiers & optionKey) != 0;
    BOOL hasCommand = (modifiers & cmdKey) != 0;
    BOOL hasControl = (modifiers & controlKey) != 0;

    if (hasOption && !hasCommand && !hasControl) {
        // 警告表示: macOS Sequoia以降ではこの組み合わせは動作しません
        [self showWarning:@"macOS 15 (Sequoia) 以降では、Option単独またはOption+Shiftのみの\n修飾キー組み合わせはシステム制限により動作しません。\nCommand または Control を含む組み合わせを使用してください。"];
        return NO;
    }
    return YES;
}
```

**2. リスク評価の更新**

| 修飾キー組み合わせ | macOS 14以前 | macOS 15+ (Sequoia) |
|-------------------|-------------|---------------------|
| Cmd + 任意キー | 動作する | 動作する |
| Cmd + Shift + 任意キー | 動作する | 動作する |
| Cmd + Ctrl + 任意キー | 動作する | 動作する |
| Cmd + Option + 任意キー | 動作する | 動作する |
| **Option + 任意キー** | 動作する | **動作しない** |
| **Option + Shift + 任意キー** | 動作する | **動作しない** |
| Ctrl + 任意キー | 動作する | 動作する |
| Shift + 任意キー | 動作する | 動作する |

**3. 将来的なプランB: `CGEvent.tapCreate` ベースの実装**

Carbon APIが完全廃止された場合の代替として、以下の設計を準備:

```objc
// プランB: CGEvent tap ベースのグローバルホットキー
CFMachPortRef eventTap = CGEventTapCreate(
    kCGSessionEventTap,
    kCGHeadInsertEventTap,
    kCGEventTapOptionDefault,  // or kCGEventTapOptionListenOnly
    CGEventMaskBit(kCGEventKeyDown),
    hotKeyCallback,
    (__bridge void *)self
);
```

- CGEvent tapはAccessibility権限（TCC）が必要だが、Revclipは既にAccessibility権限を要求している
- Carbon APIと比較してより細かいキーイベント制御が可能
- ただし、CGEvent tapはシステム全体のキーイベントを傍受するため、パフォーマンスとプライバシーの考慮が必要

### [Rev.2 追加] 6.7 Clipyからの設定移行 (m-3対応)

将来的な改善として、初回起動時にClipyの設定ファイルを検出し、設定の移行を提案する機能を検討する。

```objc
// RCAppDelegate.m - 初回起動時のClipy設定検出
- (void)checkClipyMigration {
    NSString *clipyPlistPath = [@"~/Library/Preferences/com.clipy-app.Clipy.plist"
                                stringByExpandingTildeInPath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:clipyPlistPath]) {
        // Clipyの設定ファイルが存在 → 移行を提案するアラートを表示
        // kCPY* プレフィックスのキーを kRC* プレフィックスに変換して読み込み
    }
}
```

**注意**: この機能はPhase 1のスコープ外とし、将来的な拡張として計画する。スニペットXMLインポートは既にサポートするため、スニペットデータの移行は初期リリースから可能。

---

## 7. ブランディングチェックリスト

Clipyから完全にRevclipへのブランド変更を保証するためのチェックリスト:

- [ ] Bundle Identifier: `com.revclip.Revclip`
- [ ] アプリ名: `Revclip` (Info.plist CFBundleName)
- [ ] 実行ファイル名: `Revclip`
- [ ] アプリアイコン: Revclipオリジナル (AppIcon.appiconset)
- [ ] ステータスバーアイコン: Revclipオリジナル
- [ ] ソースコードコメント: 全ファイルのヘッダーを「Revclip」に
- [ ] クラスプレフィックス: `RC` (Clipyの`CPY`から変更)
- [ ] UserDefaultsキー: `kRC` プレフィックス
- [ ] Application Supportフォルダ: `~/Library/Application Support/Revclip/`
- [ ] ローカライズ文字列: 「Quit Clipy」→「Quit Revclip」等
- [ ] About画面: Revclipの著作権表示
- [ ] Sparkle feedURL: Revclip独自のappcast URL
- [ ] コード署名: Revclip用Developer ID
- [ ] README / LICENSE: Revclipとしての表記
- [ ] GitHub リポジトリ名: Revclip

---

## 8. 実装上の重要な技術詳細

### 8.1 グローバルホットキー (Carbon API) の実装パターン

```objc
// RCHotKeyService.m
#import <Carbon/Carbon.h>

static OSStatus hotKeyHandler(EventHandlerCallRef nextHandler,
                               EventRef event, void *userData) {
    EventHotKeyID hotKeyID;
    GetEventParameter(event, kEventParamDirectObject,
                      typeEventHotKeyID, NULL,
                      sizeof(hotKeyID), NULL, &hotKeyID);
    // hotKeyID.id で登録時のIDを判別し、対応メニューをポップアップ
    RCHotKeyService *service = (__bridge RCHotKeyService *)userData;
    [service handleHotKeyWithID:hotKeyID.id];
    return noErr;
}

- (void)registerHotKey:(UInt32)keyCode
             modifiers:(UInt32)modifiers
            identifier:(UInt32)identifier {
    // [Rev.2 追加] macOS Sequoia以降のOption系修飾キー制限チェック
    BOOL hasOption = (modifiers & optionKey) != 0;
    BOOL hasCommand = (modifiers & cmdKey) != 0;
    BOOL hasControl = (modifiers & controlKey) != 0;
    if (hasOption && !hasCommand && !hasControl) {
        NSLog(@"Warning: Option-only modifier combos are not supported on macOS 15+");
        // 登録は試みるが、動作しない可能性がある旨をログに記録
    }

    EventHotKeyID hotKeyID = { 'RCKY', identifier };
    EventHotKeyRef hotKeyRef;
    RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                        GetApplicationEventTarget(),
                        0, &hotKeyRef);
    // hotKeyRefを保持して後でUnregister可能にする
}
```

### [Rev.2 修正] 8.2 クリップボード監視の実装パターン (m-1対応: QOSクラス選定)

```objc
// RCClipboardService.m
- (void)startMonitoring {
    dispatch_source_t timer = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
        dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0));
        // [Rev.2 修正] QOS_CLASS_USER_INTERACTIVE → QOS_CLASS_USER_INITIATED に変更
        // 理由: 750usの高頻度ポーリング（秒間約1,333回）を USER_INTERACTIVE で実行すると
        // UI操作のレスポンスに影響する可能性がある。changeCountの整数比較は非常に軽量な
        // 処理であるため、USER_INITIATED で十分な応答性を確保できる。
        // Clipyでは SerialDispatchQueueScheduler(qos: .userInteractive) を使用しているが、
        // Revclipではより保守的な QOS_CLASS_USER_INITIATED を採用する。

    // 750マイクロ秒間隔 (Clipyと同一)
    dispatch_source_set_timer(timer,
        dispatch_time(DISPATCH_TIME_NOW, 0),
        750 * NSEC_PER_USEC, 100 * NSEC_PER_USEC);
    dispatch_source_set_event_handler(timer, ^{
        NSInteger currentCount = [NSPasteboard generalPasteboard].changeCount;
        if (currentCount != self.cachedChangeCount) {
            self.cachedChangeCount = currentCount;
            [self createClipFromPasteboard];
        }
    });
    dispatch_resume(timer);
    self.monitorTimer = timer;
}
```

### 8.3 ペースト実行 (CGEvent) の実装パターン

```objc
// RCPasteService.m
- (void)simulatePaste {
    CGEventSourceRef source = CGEventSourceCreate(
        kCGEventSourceStateCombinedSessionState);
    // Cmd+V Down
    CGEventRef keyDown = CGEventCreateKeyboardEvent(source, kVK_ANSI_V, true);
    CGEventSetFlags(keyDown, kCGEventFlagMaskCommand);
    // Cmd+V Up
    CGEventRef keyUp = CGEventCreateKeyboardEvent(source, kVK_ANSI_V, false);
    CGEventSetFlags(keyUp, kCGEventFlagMaskCommand);
    // Post
    CGEventPost(kCGAnnotatedSessionEventTap, keyDown);
    CGEventPost(kCGAnnotatedSessionEventTap, keyUp);
    CFRelease(keyDown);
    CFRelease(keyUp);
    CFRelease(source);
}
```

### 8.4 SQLite スキーマ

```sql
-- clip_items: クリップボード履歴
CREATE TABLE IF NOT EXISTS clip_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    data_path TEXT NOT NULL,
    title TEXT DEFAULT '',
    data_hash TEXT UNIQUE NOT NULL,
    primary_type TEXT DEFAULT '',
    update_time INTEGER NOT NULL,
    thumbnail_path TEXT DEFAULT '',
    is_color_code INTEGER DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_clip_update_time ON clip_items(update_time DESC);
CREATE INDEX IF NOT EXISTS idx_clip_data_hash ON clip_items(data_hash);

-- snippet_folders: スニペットフォルダ
CREATE TABLE IF NOT EXISTS snippet_folders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    identifier TEXT UNIQUE NOT NULL,
    folder_index INTEGER DEFAULT 0,
    enabled INTEGER DEFAULT 1,
    title TEXT DEFAULT 'untitled folder'
);
CREATE INDEX IF NOT EXISTS idx_folder_index ON snippet_folders(folder_index);

-- snippets: スニペット
CREATE TABLE IF NOT EXISTS snippets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    identifier TEXT UNIQUE NOT NULL,
    folder_id TEXT NOT NULL REFERENCES snippet_folders(identifier)
        ON DELETE CASCADE,
    snippet_index INTEGER DEFAULT 0,
    enabled INTEGER DEFAULT 1,
    title TEXT DEFAULT 'untitled snippet',
    content TEXT DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_snippet_folder ON snippets(folder_id);
CREATE INDEX IF NOT EXISTS idx_snippet_index ON snippets(snippet_index);

-- schema_version: マイグレーション管理
CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER NOT NULL
);
INSERT INTO schema_version (version) VALUES (1);
```

### [Rev.2 追加] 8.5 NSPasteboard.PasteboardType の対応方針 (M-6対応)

#### 背景

Clipyは `NSPasteboard+Deprecated.swift` で、Swift 4以降で変更されたPasteboardTypeをSwift 3互換のレガシー文字列（`NSStringPboardType` 等）で使用している。これは既存のNSKeyedArchiverでアーカイブされたデータとの互換性のためである。

#### Objective-Cでの対応方針

Objective-Cでは、以下のレガシー定数がそのまま使用可能:

| Clipy (Swift deprecated拡張) | Objective-C での定数 | UTI (最新形式) | 状態 |
|------------------------------|---------------------|----------------|------|
| `.deprecatedString` (`NSStringPboardType`) | `NSPasteboardTypeString` | `public.utf8-plain-text` | 使用可能 |
| `.deprecatedRTF` (`NSRTFPboardType`) | `NSPasteboardTypeRTF` | `public.rtf` | 使用可能 |
| `.deprecatedRTFD` (`NSRTFDPboardType`) | `NSPasteboardTypeRTFD` | `com.apple.flat-rtfd` | 使用可能 |
| `.deprecatedPDF` (`NSPDFPboardType`) | `NSPasteboardTypePDF` | `com.adobe.pdf` | 使用可能 |
| `.deprecatedFilenames` (`NSFilenamesPboardType`) | `NSFilenamesPboardType` | — | **macOS 14で非推奨、`NSPasteboardTypeFileURL` を併用** |
| `.deprecatedURL` (`NSURLPboardType`) | `NSURLPboardType` | `public.url` | 使用可能 |
| `.deprecatedTIFF` (`NSTIFFPboardType`) | `NSPasteboardTypeTIFF` | `public.tiff` | 使用可能 |

**方針**:
1. Revclipでは `NSPasteboardTypeString`、`NSPasteboardTypeRTF` 等の**Objective-C標準定数**を使用する（Swift deprecated拡張は不要）
2. `NSFilenamesPboardType` はmacOS 14で正式に非推奨となったため、`NSPasteboardTypeFileURL` (`public.file-url`) も併せてサポートする
3. NSKeyedArchiverでのアーカイブ時には、Clipyとの互換性のためにレガシー文字列 (`NSStringPboardType` 等) をrawValueとして保存し、読み取り時に新旧両方の形式を受け入れる

```objc
// RCClipData.m - PasteboardType の互換性対応
+ (NSArray<NSPasteboardType> *)availableTypes {
    return @[
        NSPasteboardTypeString,
        NSPasteboardTypeRTF,
        NSPasteboardTypeRTFD,
        NSPasteboardTypePDF,
        NSFilenamesPboardType,    // レガシー (互換用)
        NSPasteboardTypeFileURL,  // [Rev.2 追加] macOS 14+ 推奨
        NSURLPboardType,
        NSPasteboardTypeTIFF
    ];
}
```

---

## [Rev.2 追加] 9. テスト戦略 (m-5対応)

### 9.1 テストカバレッジ計画

全Serviceクラスおよび全Managerクラスのユニットテストを網羅する。

| テストファイル | テスト対象 | テスト内容 |
|--------------|-----------|-----------|
| `RCClipboardServiceTests.m` | RCClipboardService | changeCount検出、データ型フィルタ、除外アプリ連携、同一履歴の上書き/コピー動作 |
| `RCDatabaseManagerTests.m` | RCDatabaseManager | CRUD操作、スキーマ作成、マイグレーション、data_hash検索、インデックス動作 |
| `RCSnippetTests.m` | RCSnippetFolder / RCSnippet | フォルダ・スニペットのCRUD、ドラッグ&ドロップ並替え、XMLインポート/エクスポート |
| `RCHotKeyServiceTests.m` | RCHotKeyService | ホットキー登録/解除、フォルダ個別ホットキー、Option系修飾キー警告 |
| `RCPasteServiceTests.m` [Rev.2 追加] | RCPasteService | ペーストボードへの書き戻し、PasteboardType別の処理、Beta修飾キー判定ロジック |
| `RCExcludeAppServiceTests.m` [Rev.2 追加] | RCExcludeAppService | 除外アプリ追加/削除、フロントアプリ判定、特殊アプリ(1Password等)検出 |
| `RCMenuManagerTests.m` [Rev.2 追加] | RCMenuManager | メニュー構築、data_hashベースのクリップ選択、ステータスアイコン切替、フォルダ分割表示 |
| `RCDataCleanServiceTests.m` [Rev.2 追加] | RCDataCleanService | 上限超過履歴削除、孤立ファイル削除 |
| `RCAccessibilityServiceTests.m` [Rev.2 追加] | RCAccessibilityService | 権限チェック、アラート表示 |
| `RCUtilitiesTests.m` [Rev.2 追加] | RCUtilities / NSColor+HexString | UserDefaults登録、HEXカラー変換、ファイル操作 |

### 9.2 手動テスト項目

- 全設定項目の反映テスト（セクション3.4の全項目）
- ホットキーのカスタム設定・動作確認（Option系組み合わせの警告テスト含む）
- スニペットのインポート/エクスポート (Clipy XML互換)
- ドラッグ&ドロップ並替え
- macOS 14 / 15 / 16 での動作差異確認
- Apple Silicon (arm64) + Intel (x86_64) 両アーキテクチャでの検証
- Hardened Runtime + CGEvent.post の動作検証
- Sparkle 2.x による自動アップデートフロー検証

---

## 10. 工数見積もり

| フェーズ | 期間 | 主要タスク |
|---------|------|----------|
| Phase 1: 基盤構築 | 2-3週間 | プロジェクト設定、DB層、クリップボード監視、メニュー表示、ペースト、macOS 16プライバシー基盤 |
| Phase 2: UI/UX完成 | 2-3週間 | ホットキー（フォルダ個別含む）、設定画面7タブ（全設定項目）、スニペットエディタ、除外アプリ、DesignableView/Button |
| Phase 3: 配布準備 | 1-2週間 | ブランディング、5言語ローカライズ、Sparkle 2.x統合、公証、DMG、テスト（全Service/Manager） |
| **合計** | **5-8週間** | |

---

## 11. 今後の拡張可能性 (スコープ外だが検討に値する)

- Clipyからの履歴データ移行ツール (Realm → SQLite変換)
- [Rev.2 追加] Clipyからの設定移行 (`com.clipy-app.Clipy.plist` の `kCPY*` → `kRC*` 変換)
- iCloud同期によるデバイス間クリップボード共有
- プラグイン/スクリプト拡張機能
- 履歴の検索機能 (Spotlight連携)
- リッチテキストプレビュー
- クリップボード履歴の暗号化保存
- [Rev.2 追加] macOS 16+でのペーストボードアクセス許可の自動検出・ユーザーガイダンス
