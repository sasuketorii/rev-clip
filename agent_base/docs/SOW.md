# Revclip 作業範囲記述書 (SOW: Statement of Work)

> **文書バージョン**: 1.0
> **作成日**: 2026-02-13
> **根拠文書**: `revclip_plan.md` Rev.4 (確定版) + `revclip_plan_review.md` (LGTM済み)
> **ステータス**: 実装開始可能

---

## 1. プロジェクト概要

### 1.1 プロジェクト名

**Revclip**

### 1.2 目的・背景

Revclipは、macOS向けオープンソースクリップボードマネージャー「Clipy」の完全リブランド・再実装プロジェクトである。

Clipyは長年macOSユーザーに愛用されてきたクリップボード管理ツールであるが、以下の課題を抱えている。

| 課題 | 詳細 |
|------|------|
| **依存ライブラリの肥大化** | CocoaPods経由で15以上のライブラリ（RealmSwift, RxSwift/RxCocoa, Magnet, KeyHolder, Sauce, Sparkle, PINCache, LoginServiceKit, AEXML, LetsMove, SwiftHEXColors, Screeen/RxScreeen等）に依存しており、バイナリサイズが大きく、ビルド・メンテナンスのコストが高い |
| **Realm依存** | データ永続化にRealm（重量級ORM）を使用しており、ライブラリ更新やmacOSアップデートでの互換性問題が発生しやすい |
| **RxSwift依存** | リアクティブプログラミングフレームワークRxSwiftに全面的に依存しており、コードの複雑性が高い |
| **macOS最新バージョンへの未対応** | macOS 16で導入されるクリップボードプライバシー保護、macOS Sequoiaのホットキー制限などへの対応が必要 |
| **メンテナンス停滞** | オリジナルのClipyリポジトリの更新が停滞している |

Revclipは、Clipyの優れたUX（クリップボード履歴管理、スニペット機能、グローバルホットキー等）を完全に継承しつつ、以下の方針で再実装する。

- **Objective-C + AppKit** によるネイティブ実装（Swiftは使用しない）
- **外部依存の最小化**（Sparkle 2.x + FMDB程度に削減）
- **SQLite**（macOS標準搭載）によるRealmの置き換え
- **NSNotificationCenter + KVO + GCD** によるRxSwiftの置き換え
- **Carbon API直接利用** によるMagnet/KeyHolder/Sauceの置き換え
- **macOS 14.0以降** を対象とした最新プライバシー保護への対応

### 1.3 最終成果物の定義

Apple Developer IDで署名・公証済みの **Revclip.app** を含むDMGインストーラー。Clipyの全機能を再現し、Clipyのブランド痕跡を一切含まない、独立したmacOSクリップボードマネージャーアプリケーション。

---

## 2. スコープ（作業範囲）

### 2.1 スコープ内（In Scope）

#### コア機能

| # | 機能 | 説明 |
|---|------|------|
| 1 | クリップボード監視 | `dispatch_source` タイマーで750usポーリング。`NSPasteboard.general.changeCount` による変更検出 |
| 2 | 履歴データ保存 | NSKeyedArchiverによるファイル保存 + SQLite (FMDB) でのメタデータ管理 |
| 3 | ペースト実行 | CGEventによるCmd+Vキーイベントシミュレーション |
| 4 | メニューバー常駐 | NSStatusItemによるステータスバーアイコン（黒/白/非表示の3状態） |
| 5 | ポップアップメニュー | NSMenu.popUpによる履歴・スニペット表示 |
| 6 | グローバルホットキー | Carbon API (RegisterEventHotKey) によるシステム全体のショートカットキー登録 |
| 7 | スニペット管理 | フォルダ/スニペットのCRUD、ドラッグ&ドロップ並べ替え |
| 8 | スニペットインポート/エクスポート | XML形式（Clipyフォーマット互換） |
| 9 | 設定画面 | 7タブ（General/Menu/Type/Exclude/Shortcuts/Updates/Beta）の設定ウィンドウ |
| 10 | 除外アプリ管理 | フロントアプリ監視 + 特殊アプリ（1Password等）対応 |
| 11 | データクリーンアップ | 30分間隔タイマーによる上限超過履歴削除 + 孤立ファイル削除 |
| 12 | Accessibility権限管理 | AXIsProcessTrustedWithOptions による権限チェック・要求 |
| 13 | ログイン時自動起動 | SMAppService (macOS 13+) によるログインアイテム登録 |
| 14 | 自動アップデート | Sparkle 2.x (Objective-C版、EdDSA署名、XPC Service経由) |
| 15 | カラーコードプレビュー | HEXカラー文字列のメニュー内色プレビュー |
| 16 | 多言語対応 (i18n) | 英語/日本語/ドイツ語/中国語(簡体字)/イタリア語の5言語 |
| 17 | ホットキーレコーダーUI | KeyHolderと同等のカスタムNSViewによるショートカット記録UI |
| 18 | スクリーンショット監視 | NSMetadataQueryによるスクリーンショットフォルダ監視（Beta機能） |
| 19 | "Applicationsフォルダへ移動"機能 | LetsMove (Obj-C版) 組込 or 自前実装 |
| 20 | macOS 16クリップボードプライバシー対応 | NSPasteboard.accessBehavior チェック + detect メソッド + ユーザーガイダンスUI |
| 21 | macOS Sequoiaホットキー制限対応 | Option系修飾キー制限の警告表示 |
| 22 | フォルダ個別ホットキー | スニペットフォルダごとのホットキー登録・管理 |
| 23 | Beta機能の修飾キー判定 | プレーンテキスト貼付 / 履歴削除 / ペースト&削除の修飾キーアクション |

#### ビルド・配布基盤

| # | 項目 | 説明 |
|---|------|------|
| 1 | xcodebuild CLIビルドシステム | xcodegen + xcodebuild によるターミナル完結ビルド |
| 2 | コード署名 | Developer ID Applicationによる署名 + Hardened Runtime |
| 3 | Apple公証 (Notarization) | xcrun notarytoolによる公証取得 + staple |
| 4 | DMGインストーラー | create-dmgによるインストーラーDMG作成 |
| 5 | Makefileラッパー | 頻用コマンドの短縮用Makefile |
| 6 | ユニットテスト | 全Service / 全Managerクラスのテスト（10テストファイル） |

#### ブランディング

| # | 項目 | 説明 |
|---|------|------|
| 1 | アプリアイコン | Revclipオリジナルアイコン（AppIcon + StatusBarIcon、全サイズ） |
| 2 | クラスプレフィックス変更 | `CPY` → `RC` |
| 3 | UserDefaultsキー変更 | `kCPY` → `kRC` |
| 4 | Bundle Identifier | `com.revclip.Revclip` |
| 5 | ローカライズ文字列置換 | 全文字列で「Clipy」→「Revclip」 |
| 6 | Application Supportパス | `~/Library/Application Support/Revclip/` |
| 7 | Sparkle feedURL | Revclip独自のappcast URL |

### 2.2 スコープ外（Out of Scope）

| # | 項目 | 理由・備考 |
|---|------|-----------|
| 1 | Clipyからの履歴データ移行ツール（Realm → SQLite変換） | 新規アプリのため既存データ移行は不要。将来的な拡張として検討 |
| 2 | Clipyからの設定自動移行 | 初期リリースではスコープ外。スニペットXMLインポートのみ対応 |
| 3 | iCloud同期によるデバイス間クリップボード共有 | 将来的な拡張候補 |
| 4 | プラグイン/スクリプト拡張機能 | 将来的な拡張候補 |
| 5 | 履歴の全文検索機能（Spotlight連携） | 将来的な拡張候補 |
| 6 | リッチテキストプレビュー | 将来的な拡張候補 |
| 7 | クリップボード履歴の暗号化保存 | 将来的な拡張候補 |
| 8 | App Store配布 | App Sandbox非互換のため不可。Web直接配布 + DMG形式 |
| 9 | CI/CD（GitHub Actions等） | 将来的に自動化検討。初期リリースではローカルビルド |
| 10 | クラッシュレポート（Sentry等） | 初期リリースではオプション。将来的に導入検討 |
| 11 | macOS 13以前のサポート | Deployment Target: macOS 14.0 |
| 12 | iOS / iPadOS対応 | macOS専用アプリ |

---

## 3. 技術要件

### 3.1 技術スタック（確定版）

| 項目 | 選定技術 | 選定理由 |
|------|---------|---------|
| **言語** | Objective-C | ユーザー承認済み。Swiftを使わない制約。macOS APIとの親和性が最高。Apple Silicon完全対応 |
| **UIフレームワーク** | AppKit (Cocoa) | ClipyのUXをそのまま再現。NSMenu / NSStatusItem / NSWindowController等 |
| **データ永続化** | SQLite3 (FMDB) | Realmより軽量。依存が少ない。Objective-Cとの相性が良い |
| **ホットキー** | Carbon API (RegisterEventHotKey) 直接利用 | Magnetの内部実装と同等。追加依存なし |
| **自動アップデート** | Sparkle 2.x (Obj-C版) | Hardened Runtime完全対応。EdDSA署名。XPC Service経由 |
| **XML処理** | NSXMLParser / NSXMLDocument | macOS標準API。追加依存なし |
| **画像キャッシュ** | NSCache + ファイルキャッシュ | PINCache不要。シンプルで軽量 |
| **ログイン起動** | SMAppService (macOS 13+) | Apple推奨の最新API |
| **リアクティブ** | NSNotificationCenter + KVO + GCD | RxSwift不要。macOS標準メカニズム |
| **ビルドシステム** | xcodebuild (CLI) + .xcodeproj (xcodegen生成) | ターミナル完結。IDE手動操作不要 |
| **コードフォーマット** | clang-format | SwiftLintの代替 |

### 3.2 対応環境

| 項目 | 値 |
|------|-----|
| **Deployment Target** | macOS 14.0 (Sonoma) |
| **ターゲットOS** | macOS 15.0 (Sequoia) |
| **将来対応** | macOS 16（クリップボードプライバシー保護対応設計済み） |
| **アーキテクチャ** | Universal Binary (arm64 + x86_64) |
| **Apple Silicon** | ネイティブ対応 (arm64) |
| **Intel** | Rosetta2不要 (x86_64ネイティブ) |

### 3.3 ビルド・配布要件

| 項目 | 値 |
|------|-----|
| **ビルド方式** | xcodebuild + .xcodeproj（xcodegen生成） |
| **プロジェクト生成** | xcodegen (`project.yml` → `.xcodeproj`) |
| **署名** | Developer ID Application 証明書 |
| **Hardened Runtime** | 有効 |
| **公証** | xcrun notarytool submit + staple |
| **配布形式** | 署名・公証済みDMGインストーラー |
| **バイナリ形式** | Universal Binary (arm64 + x86_64) |
| **ARC** | 有効 (CLANG_ENABLE_OBJC_ARC = YES) |
| **Entitlements** | `com.apple.security.automation.apple-events` のみ（App Sandboxは無効） |
| **LSUIElement** | YES（Dockに表示しないエージェントアプリ） |

---

## 4. 機能要件

### 4.1 クリップボード監視・履歴管理

| 機能ID | 機能 | 詳細仕様 | 受け入れ基準 |
|--------|------|---------|-------------|
| F-001 | クリップボード変更検出 | `dispatch_source` タイマーで750usポーリング。`NSPasteboard.general.changeCount` の変化を検出 | 他アプリでのコピー操作後、750us以内に変更が検出されること |
| F-002 | クリップデータ保存 | NSKeyedArchiverでクリップデータをファイル保存。メタデータをSQLiteに記録。data_hashをUNIQUEキーとして管理 | コピーしたテキスト/画像/RTF/ファイルパスが正しく保存され、再起動後も保持されること |
| F-003 | 履歴上限管理 | UserDefaultsの最大履歴数設定（デフォルト: 30）に基づき、古い履歴を自動削除 | 設定した上限数を超えた場合、最も古い履歴が自動削除されること |
| F-004 | 同一履歴の上書き | 同一内容のコピー時、既存履歴を最新位置に移動（設定で有効/無効切替可能） | 設定ONの場合、同じ内容をコピーしても重複履歴が作成されず、既存エントリが最上位に移動すること |
| F-005 | 同一履歴のコピー | 同一内容のコピーを許可/禁止する設定 | 設定に応じて同一内容の重複保存を制御できること |
| F-006 | 保存対象タイプフィルタ | String/RTF/RTFD/PDF/Filenames/URL/TIFF の各タイプを個別に有効/無効設定 | 設定でOFFにしたタイプのクリップボードデータが保存されないこと |
| F-007 | データクリーンアップ | 30分間隔タイマーで上限超過履歴削除 + 孤立ファイル削除 | 30分ごとに上限超過分が自動削除され、対応するファイルも削除されること |
| F-008 | macOS 16プライバシー対応 | `NSPasteboard.accessBehavior` チェック + `detect` メソッドによるアラート回避 + ユーザーガイダンスUI | macOS 16環境で、アクセス拒否時にユーザーへ再許可案内が表示されること。macOS 14/15では従来通り動作すること |

### 4.2 ペースト機能

| 機能ID | 機能 | 詳細仕様 | 受け入れ基準 |
|--------|------|---------|-------------|
| F-009 | 基本ペースト | 選択した履歴/スニペットをNSPasteboardに書き戻し、CGEventでCmd+Vをシミュレーション | メニューから履歴を選択すると、アクティブなアプリケーションにペーストされること |
| F-010 | ペースト後に履歴並べ替え | ペーストした項目を履歴の最上位に移動（設定で有効/無効切替可能） | 設定ONの場合、ペースト実行後にその項目が履歴の先頭に移動すること |
| F-011 | プレーンテキスト貼付（Beta） | 修飾キー押下時にリッチテキストをプレーンテキストとして貼付（修飾キー選択可能: Cmd/Shift/Ctrl/Option） | 設定した修飾キーを押しながらメニュー項目を選択すると、プレーンテキストとしてペーストされること |
| F-012 | 履歴削除（Beta） | 修飾キー押下時に選択した履歴を削除（修飾キー選択可能） | 設定した修飾キーを押しながらメニュー項目を選択すると、その履歴が削除されること |
| F-013 | ペースト&削除（Beta） | 修飾キー押下時にペースト後に履歴から削除（修飾キー選択可能） | 設定した修飾キーを押しながらメニュー項目を選択すると、ペースト後にその履歴が削除されること |

### 4.3 メニュー・UI

| 機能ID | 機能 | 詳細仕様 | 受け入れ基準 |
|--------|------|---------|-------------|
| F-014 | ステータスバーアイコン | NSStatusItemで常駐。黒/白/非表示の3状態切替 | メニューバーにアイコンが表示され、設定に応じて表示状態が切り替わること |
| F-015 | メインメニュー | 履歴 + スニペット + 操作項目（設定・終了等）を統合表示 | メインメニューに全項目が正しく表示されること |
| F-016 | 履歴メニュー | 履歴のみを独立表示するメニュー | 履歴メニューのホットキーで履歴のみが表示されること |
| F-017 | スニペットメニュー | スニペットのみを独立表示するメニュー | スニペットメニューのホットキーでスニペットのみが表示されること |
| F-018 | メニュー番号表示 | メニュー項目に番号を付加（0始まり/1始まりの切替可能） | 設定に応じてメニュー項目に正しい番号が表示されること |
| F-019 | メニューアイコン表示 | メニュー項目にアイコンを表示（アイコンサイズ設定可能） | 設定に応じてメニュー項目にアイコンが表示され、サイズが変更できること |
| F-020 | ツールチップ | メニュー項目にツールチップを表示（最大長設定可能） | 設定ONの場合、メニュー項目にマウスホバーでツールチップが表示されること |
| F-021 | サムネイル画像表示 | 画像クリップのサムネイルをメニューに表示（幅・高さ設定可能） | 画像をコピーした場合、メニュー項目にサムネイルが表示されること |
| F-022 | カラーコードプレビュー | HEXカラー文字列の色をメニュー内でプレビュー表示 | HEXカラー文字列（例: #FF0000）をコピーした場合、メニューに色見本が表示されること |
| F-023 | 数字キーショートカット | メニュー項目に数字キーEquivalentを付加（設定で有効/無効切替可能） | 設定ONの場合、メニュー表示中に数字キーで項目を選択できること |
| F-024 | フォルダ分割表示 | 履歴をインライン表示数/フォルダ内表示数で分割表示 | 設定した数値に応じてメニューが正しく分割表示されること |
| F-025 | 履歴クリアメニュー項目 | メニューに「履歴クリア」項目を表示（確認アラート設定可能） | 設定ONの場合、メニューに「履歴クリア」が表示され、実行前にアラートが表示されること（設定による） |
| F-026 | data_hashベースのクリップ選択 | メニューアイテムのrepresentedObjectにdata_hashを設定し、SQLiteで検索 | メニュー項目選択時に正しいクリップが特定され、ペーストが実行されること |

### 4.4 グローバルホットキー

| 機能ID | 機能 | 詳細仕様 | 受け入れ基準 |
|--------|------|---------|-------------|
| F-027 | メインメニューホットキー | デフォルト: Cmd+Shift+V。カスタマイズ可能 | 設定したホットキーでメインメニューがポップアップ表示されること |
| F-028 | 履歴メニューホットキー | デフォルト: Cmd+Ctrl+V。カスタマイズ可能 | 設定したホットキーで履歴メニューがポップアップ表示されること |
| F-029 | スニペットメニューホットキー | デフォルト: Cmd+Shift+B。カスタマイズ可能 | 設定したホットキーでスニペットメニューがポップアップ表示されること |
| F-030 | 履歴クリアホットキー | カスタマイズ可能 | 設定したホットキーで履歴クリアが実行されること |
| F-031 | フォルダ個別ホットキー | スニペットフォルダごとに個別のホットキーを設定可能 | フォルダに設定したホットキーで、そのフォルダのスニペットメニューがポップアップ表示されること |
| F-032 | ホットキーレコーダーUI | カスタムNSViewでキー入力を記録・表示。KeyHolderと同等のUI | ショートカットフィールドにフォーカスしてキー入力すると、入力したキーコンボが正しく表示・保存されること |
| F-033 | Option系修飾キー警告 | macOS Sequoia以降でOption単独/Option+Shiftの組み合わせ設定時に警告表示 | 制限のある修飾キー組み合わせを設定しようとすると、警告メッセージが表示されること |

### 4.5 スニペット管理

| 機能ID | 機能 | 詳細仕様 | 受け入れ基準 |
|--------|------|---------|-------------|
| F-034 | スニペットエディタウィンドウ | NSSplitView（左: NSOutlineView / 右: NSTextView）で構成 | スニペットエディタが正しいレイアウトで表示されること |
| F-035 | フォルダ作成・編集・削除 | SQLiteでフォルダのCRUD操作 | フォルダの作成・名前変更・削除が正しく動作すること |
| F-036 | スニペット作成・編集・削除 | SQLiteでスニペットのCRUD操作 | スニペットの作成・テキスト編集・削除が正しく動作すること |
| F-037 | ドラッグ&ドロップ並べ替え | NSOutlineView上でフォルダ・スニペットの順序変更 | ドラッグ&ドロップでフォルダ・スニペットの並び順を変更できること |
| F-038 | XMLインポート | NSXMLDocumentでClipy形式のスニペットXMLを読み込み | ClipyでエクスポートしたXMLファイルをインポートして、スニペットが正しく復元されること |
| F-039 | XMLエクスポート | NSXMLDocumentでスニペットをClipy互換XML形式で出力 | エクスポートしたXMLファイルがClipy互換のフォーマットであること |

### 4.6 設定画面

| 機能ID | 機能 | 詳細仕様 | 受け入れ基準 |
|--------|------|---------|-------------|
| F-040 | 設定ウィンドウ | RCPreferencesWindowController。7タブ切替式。Clipyと同一レイアウト | 設定ウィンドウが7タブで表示され、各タブの切替が正しく動作すること |
| F-041 | Generalタブ | 最大履歴数 / ログイン起動 / ステータスアイコン / ペーストコマンド / ペースト後並べ替え / 同一履歴の上書き・コピー | 全設定項目がUIに反映され、変更が即座にアプリ動作に反映されること |
| F-042 | Menuタブ | インライン数 / フォルダ内数 / タイトル長 / 番号表示 / 番号起点 / ツールチップ / ツールチップ最大長 / 画像表示 / アイコンサイズ / アイコン表示 / 数字キーEquivalent / サムネイルサイズ / 履歴クリアメニュー項目 | 全設定項目がメニュー表示に正しく反映されること |
| F-043 | Typeタブ | 保存対象タイプ（String/RTF/RTFD/PDF/Filenames/URL/TIFF）チェックボックス | チェックボックスの変更がクリップボード監視の保存対象に反映されること |
| F-044 | Excludeタブ | 除外アプリの追加（NSOpenPanel）・削除（NSTableView） | アプリを追加・削除でき、除外アプリでのコピーが監視対象外になること |
| F-045 | Shortcutsタブ | メイン/履歴/スニペット/履歴クリアの4つのショートカット記録 | RCHotKeyRecorderViewで各ホットキーを設定でき、設定したキーで動作すること |
| F-046 | Updatesタブ | Sparkle連携。自動チェック有効/無効。チェック間隔設定。バージョン表示 | Sparkleの自動チェック設定が反映され、手動チェックボタンが動作すること |
| F-047 | Betaタブ | プレーンテキスト貼付 + 修飾キー / 履歴削除 + 修飾キー / ペースト&削除 + 修飾キー / スクリーンショット監視 | 全Beta機能の有効/無効と修飾キー選択が正しく動作すること |

### 4.7 その他機能

| 機能ID | 機能 | 詳細仕様 | 受け入れ基準 |
|--------|------|---------|-------------|
| F-048 | 除外アプリサービス | NSWorkspace通知でフロントアプリ監視。除外リストのアプリがフロントの場合、クリップボード監視を一時停止 | 除外アプリに設定したアプリがフロントの場合、そのアプリでのコピーが履歴に記録されないこと |
| F-049 | 特殊アプリ対応 | 1Password等、パスワードマネージャーからのコピーを除外する特殊処理 | 1Password等の特殊アプリからのコピーが適切に処理されること |
| F-050 | Accessibility権限チェック | AXIsProcessTrustedWithOptions で権限確認。未付与時にガイダンスアラート表示 | 初回起動時にAccessibility権限要求が表示され、許可後にペースト機能が動作すること |
| F-051 | ログインアイテム登録 | SMAppService.mainApp でログイン時自動起動を設定 | 設定ONの場合、macOS再起動後に自動的にRevclipが起動すること |
| F-052 | "Applicationsフォルダへ移動" | アプリがApplicationsフォルダ外にある場合、移動を提案するダイアログ表示 | Applicationsフォルダ外から起動した場合、移動ダイアログが表示されること |
| F-053 | スクリーンショット監視（Beta） | NSMetadataQueryでスクリーンショットフォルダを監視し、新規スクリーンショットを自動クリップ | 設定ONの場合、スクリーンショット撮影後に履歴にスクリーンショットが追加されること |

---

## 5. 非機能要件

### 5.1 パフォーマンス

| 項目 | 要件 |
|------|------|
| **メモリ使用量** | アイドル時50MB以下を目標（Clipy比で削減） |
| **CPU使用率** | アイドル時0.1%以下（changeCount比較のみの軽量ポーリング） |
| **バイナリサイズ** | Clipy比で大幅に削減（Realm, RxSwift, 多数Podの除去による） |
| **起動時間** | 2秒以内にメニューバーアイコン表示・監視開始 |
| **ペースト遅延** | メニュー項目選択から50ms以内にペースト実行 |
| **QOSクラス** | クリップボード監視タイマーは `QOS_CLASS_USER_INITIATED` で実行（`USER_INTERACTIVE` ではなく、UI応答性への影響を回避） |

### 5.2 セキュリティ

| 項目 | 要件 |
|------|------|
| **Hardened Runtime** | 有効化必須。公証の前提条件 |
| **Apple公証** | xcrun notarytool によるApple公証取得必須。Gatekeeperでの警告なし |
| **Staple** | 公証結果をアプリバンドルおよびDMGにstaple |
| **コード署名** | Developer ID Application 証明書による署名 |
| **Sparkle署名** | EdDSA (ed25519) 署名鍵による自動アップデートの改ざん防止 |
| **HTTPS** | appcast.xml ホスティングはHTTPS必須 |
| **App Sandbox** | 無効（クリップボード監視・CGEvent・Accessibility API使用のため非互換） |
| **Entitlements** | `com.apple.security.automation.apple-events` のみ。最小権限の原則 |
| **TCC** | Accessibility権限はランタイムにユーザー許可を取得。Entitlementは不要 |

### 5.3 互換性

| 項目 | 要件 |
|------|------|
| **macOS 14 (Sonoma)** | Deployment Target。全機能が動作すること |
| **macOS 15 (Sequoia)** | ターゲットOS。ホットキー制限（Option系）への対応済み |
| **macOS 16** | クリップボードプライバシー保護への対応設計済み。`@available(macOS 16.0, *)` で条件分岐 |
| **Apple Silicon (arm64)** | ネイティブ対応。Universal Binary に含む |
| **Intel (x86_64)** | ネイティブ対応。Universal Binary に含む |
| **NSFilenamesPboardType** | macOS 14で非推奨。`NSPasteboardTypeFileURL` を併用サポート |
| **Sparkle 2.x** | Sparkle 1.x (DSA署名) から 2.x (EdDSA署名、XPC Service) へ移行 |
| **Clipyスニペット互換** | ClipyのXMLスニペットフォーマットをインポート可能 |

---

## 6. 成果物一覧（Deliverables）

| # | 成果物 | 説明 | 形式 |
|---|--------|------|------|
| 1 | **ソースコード** | Revclip全ソースコード（Objective-C）。ディレクトリ構成はプラン セクション2.1 に準拠 | .h / .m / .xib / .xcassets / .plist / .entitlements |
| 2 | **xcodegen定義** | `project.yml` - xcodegen によるプロジェクト生成定義ファイル | YAML |
| 3 | **Makefileラッパー** | 頻用ビルドコマンドの短縮Makefile | Makefile |
| 4 | **ビルドスクリプト** | `Scripts/build.sh` - ビルド自動化スクリプト | Shell |
| 5 | **公証スクリプト** | `Scripts/notarize.sh` - ビルド・署名・公証・DMG作成の全自動スクリプト | Shell |
| 6 | **DMG作成スクリプト** | `Scripts/create_dmg.sh` - DMGインストーラー作成スクリプト | Shell |
| 7 | **ローカライズエクスポートスクリプト** | `Scripts/export_strings.sh` - ローカライズ文字列エクスポートスクリプト | Shell |
| 8 | **署名・公証済みDMG** | Revclip.app を含む配布用DMGインストーラー | .dmg |
| 9 | **ユニットテスト** | 全Service・全Managerクラスのテストコード（10テストファイル） | .m (XCTest) |
| 10 | **外部ライブラリ** | FMDB (ソース組込) + Sparkle.framework (2.x) | .m / .framework |
| 11 | **アプリアイコン** | AppIcon (16x16 ~ 1024x1024) + StatusBarIcon | .xcassets |
| 12 | **ローカライズリソース** | 5言語 (en/ja/de/zh-Hans/it) の Localizable.strings | .strings |
| 13 | **DMG背景画像** | `Distribution/dmg_background.png` | .png |
| 14 | **Entitlements** | `Revclip/Revclip.entitlements` | .plist |
| 15 | **Info.plist** | アプリケーション設定 (Bundle ID, LSUIElement, SUFeedURL等) | .plist |

---

## 7. 作業フェーズと各フェーズの成果物

### 7.1 Phase 1: 基盤構築（推定: 2-3週間）

**目標**: アプリの骨格を完成させ、クリップボード監視 → 履歴表示 → ペーストの基本フローを動作させる

#### タスク一覧

| タスクID | タスク名 | 詳細 | 優先度 |
|----------|---------|------|--------|
| 1-1 | プロジェクトセットアップ | ターミナルから .xcodeproj を生成/設定（xcodegen使用）。Bundle ID: `com.revclip.Revclip`。LSUIElement=YES。Deployment Target: macOS 14.0。Architectures: arm64 + x86_64 (Universal)。`project.yml` 作成。Xcode.appの手動操作は不要 | 最高 |
| 1-2 | 定数・環境定義 | `RCConstants.h/.m` - 全UserDefaultsキーの定義（セクション3.4の全項目、`kRC`プレフィックス）。`RCEnvironment.h/.m` - シングルトンDIコンテナ（各Serviceへの参照保持） | 最高 |
| 1-3 | データベース層 | FMDB組込（ソースコード直接組込）。`RCDatabaseManager.h/.m` - スキーマ作成（clip_items / snippet_folders / snippets / schema_version）。マイグレーション機構。インデックス作成 | 最高 |
| 1-4 | クリップボードモデル | `RCClipItem.h/.m` - クリップ履歴モデル（SQLiteレコード対応）。`RCClipData.h/.m` - NSCoding準拠のクリップデータ本体（NSKeyedArchiverでファイル保存） | 最高 |
| 1-5 | クリップボード監視 | `RCClipboardService.h/.m` - dispatch_sourceタイマーで750usポーリング。NSPasteboard変更検出 → RCClipData作成 → ファイル保存 → DB INSERT。除外アプリチェック連携。データ型フィルタ | 最高 |
| 1-6 | メニューマネージャー基盤 | `RCMenuManager.h/.m` - NSStatusItem作成。クリップ履歴からNSMenu構築。基本メニュー項目（設定・終了）。data_hashベースのクリップ選択ロジック | 最高 |
| 1-7 | ペーストサービス | `RCPasteService.h/.m` - NSPasteboardへの書き戻し + CGEventによるCmd+Vシミュレーション + Beta修飾キー判定ロジック（`isPressedModifier:`） | 最高 |
| 1-8 | Accessibility権限 | `RCAccessibilityService.h/.m` - AXIsProcessTrustedWithOptions による権限チェック + 権限要求アラート表示 | 高 |
| 1-9 | UserDefaults初期化 | `RCUtilities.h/.m` - 全デフォルト設定の登録（セクション3.4の全項目のデフォルト値を `registerDefaults:` で設定） | 高 |
| 1-10 | macOS 16プライバシー対応基盤 | `RCClipboardService` に `@available(macOS 16.0, *)` で accessBehavior チェック + detect メソッド対応の条件分岐を組込 | 高 |

#### Phase 1 完了条件

- メニューバーにRevclipアイコンが表示される
- 他アプリでのクリップボードコピーを検出し、履歴としてSQLiteに保存される
- メニューからクリップ履歴一覧が表示される
- メニュー項目クリックでペースト（Cmd+Vシミュレーション）が実行される
- Accessibility権限の要求ダイアログが表示される
- Hardened Runtime + CGEvent.post の動作検証が完了している

#### Phase 1 成果物

- `Revclip.xcodeproj` (xcodegen生成)
- `project.yml`
- `Makefile`
- `Revclip/` ディレクトリ（App/, Services/, Managers/, Models/, Utilities/ の各ソースファイル）
- `Revclip/Vendor/FMDB/` (ソース組込)
- `Revclip/Info.plist`
- `Revclip/Revclip.entitlements`
- `Revclip/Resources/MainMenu.xib`

---

### 7.2 Phase 2: UI・UX完成（推定: 2-3週間）

**目標**: Clipyと同等のUI/UXを完全再現する

#### タスク一覧

| タスクID | タスク名 | 詳細 | 優先度 |
|----------|---------|------|--------|
| 2-1 | グローバルホットキー | `RCHotKeyService.h/.m` - Carbon API RegisterEventHotKey 直接使用。メイン(Cmd+Shift+V) / 履歴(Cmd+Ctrl+V) / スニペット(Cmd+Shift+B) / 履歴クリアの4つの全体ホットキー登録 | 最高 |
| 2-1a | フォルダ個別ホットキー | `RCHotKeyService` に `registerSnippetHotKeyWithIdentifier:keyCode:modifiers:` / `unregisterSnippetHotKeyWithIdentifier:` 実装。フォルダidentifierベースの辞書管理。setupSnippetHotKeys で起動時一括登録 | 高 |
| 2-2 | ホットキーレコーダーUI | `RCHotKeyRecorderView.h/.m` - カスタムNSView。キー入力受付 → KeyCombo表示。KeyHolderと同等のUI。Option単独/Option+Shift組み合わせの警告表示 | 高 |
| 2-3 | 設定ウィンドウ | `RCPreferencesWindowController.h/.m + .xib` - 7タブ切替式。Clipyと同一レイアウト | 高 |
| 2-3a | General設定パネル | `RCGeneralPreferenceVC.h/.m + .xib` - 最大履歴数 / ログイン起動 / ステータスアイコン / ペーストコマンド / ペースト後並べ替え / 同一履歴の上書き・コピー | 高 |
| 2-3b | Menu設定パネル | `RCMenuPreferenceVC.h/.m + .xib` - インライン数 / フォルダ内数 / タイトル長 / 番号表示 / 番号起点(0/1) / ツールチップ / ツールチップ最大長 / 画像表示 / アイコンサイズ / アイコン表示 / 数字キーEquivalent / サムネイルサイズ / 履歴クリアメニュー項目 | 高 |
| 2-3c | Type設定パネル | `RCTypePreferenceVC.h/.m + .xib` - 保存対象タイプ（String/RTF/RTFD/PDF/Filenames/URL/TIFF）チェックボックス | 高 |
| 2-3d | Exclude設定パネル | `RCExcludeAppPreferenceVC.h/.m + .xib` - 除外アプリ追加(NSOpenPanel) / 削除(NSTableView) | 高 |
| 2-3e | Shortcuts設定パネル | `RCShortcutsPreferenceVC.h/.m + .xib` - メイン/履歴/スニペット/履歴クリアの4つのRCHotKeyRecorderView | 高 |
| 2-3f | Updates設定パネル | `RCUpdatesPreferenceVC.h/.m + .xib` - Sparkle連携。自動チェック間隔。バージョン表示 | 中 |
| 2-3g | Beta設定パネル | `RCBetaPreferenceVC.h/.m + .xib` - プレーンテキスト貼付 + 修飾キーPopUp / 履歴削除 + 修飾キーPopUp / ペースト&削除 + 修飾キーPopUp / スクリーンショット監視チェックボックス | 中 |
| 2-4 | スニペットエディタ | `RCSnippetEditorWindowController.h/.m + .xib` - NSSplitView + NSOutlineView + NSTextView。フォルダ/スニペットのCRUD。ドラッグ&ドロップ並替え。フォルダ個別ホットキーレコーダー。`RCSnippetEditorCell.h/.m`、`RCPlaceholderTextView.h/.m` | 高 |
| 2-5 | スニペットインポート/エクスポート | NSXMLDocument / NSXMLParser でXML処理。Clipyフォーマット互換のインポート/エクスポート | 中 |
| 2-6 | 除外アプリサービス | `RCExcludeAppService.h/.m` - NSWorkspace通知でフロントアプリ監視。除外リスト管理。1Password等特殊アプリ対応 | 高 |
| 2-7 | データクリーンアップ | `RCDataCleanService.h/.m` - 30分間隔タイマー。上限超過履歴削除 + 孤立ファイル削除 | 中 |
| 2-8 | メニュー高度機能 | `RCMenuManager` にサムネイル画像表示 / カラーコードプレビュー / ツールチップ / 数字キーEquivalent / フォルダ分割表示を追加 | 高 |
| 2-9 | UIコンポーネント | `RCDesignableView.h/.m` - IBDesignable NSView（backgroundColor, borderColor, borderWidth, cornerRadius）。`RCDesignableButton.h/.m` - IBDesignable NSButton（textColor）。`RCSplitView.h/.m` | 中 |

#### Phase 2 完了条件

- 設定画面7タブが全て動作し、全設定項目が反映される
- スニペットの作成・編集・削除・ドラッグ並べ替えが動作する
- スニペットのXMLインポート/エクスポートが動作する（Clipy互換）
- グローバルホットキーによるメニューポップアップが動作する（メイン/履歴/スニペット/履歴クリア/フォルダ個別）
- ホットキーレコーダーUIでショートカット設定が可能
- 除外アプリが正しく動作する
- Beta機能（プレーンテキスト貼付/履歴削除/ペースト&削除）の修飾キー動作
- メニューの高度機能（サムネイル/カラーコード/ツールチップ/フォルダ分割）が動作する

#### Phase 2 成果物

- `Revclip/UI/` ディレクトリ（Preferences/, SnippetEditor/, HotKeyRecorder/, Views/ の全ソースファイル + XIBファイル）
- `RCHotKeyService.h/.m`
- `RCExcludeAppService.h/.m`
- `RCDataCleanService.h/.m`
- `RCLoginItemService.h/.m`
- 各UIコンポーネントのXIBファイル群（計10ファイル以上）

---

### 7.3 Phase 3: ブランディング・配布準備（推定: 1-2週間）

**目標**: Revclipとしての完全ブランディングと配布可能な状態にする

#### タスク一覧

| タスクID | タスク名 | 詳細 | 優先度 |
|----------|---------|------|--------|
| 3-1 | アイコン・ブランディング | Revclipオリジナルアイコン作成（AppIcon, StatusBar icon）。全サイズ生成 (16x16 ~ 1024x1024)。ブランディングチェックリスト全項目の確認 | 最高 |
| 3-2 | ローカライズ | en/ja/de/zh-Hans/it の5言語をサポート。Clipyの翻訳を参考に「Clipy」→「Revclip」に全置換。Localizable.strings の作成 | 高 |
| 3-3 | Sparkle統合 | Sparkle 2.x framework組込。EdDSA (ed25519) 署名鍵生成（`generate_keys` ツール使用）。appcast.xml ホスティング設定。SUPublicEDKey / SUFeedURL を Info.plist に設定。XPC Service経由のセキュアなアップデート | 高 |
| 3-4 | ログインアイテム | `RCLoginItemService.h/.m` - SMAppService (macOS 13+) でログイン時自動起動。設定画面のGeneral タブと連携 | 高 |
| 3-5 | "Applicationsフォルダへ移動"機能 | LetsMove (Obj-C版) 組込 or 自前実装。アプリがApplicationsフォルダ外にある場合に移動提案ダイアログを表示 | 中 |
| 3-6 | スクリーンショット監視 | NSMetadataQuery でスクリーンショットフォルダ監視。新規スクリーンショットを自動クリップ（Beta機能） | 低 |
| 3-7 | コード署名 | Apple Developer証明書でコード署名。Hardened Runtime有効化。`codesign --verify` で検証 | 最高 |
| 3-8 | 公証 (Notarization) | `xcrun notarytool submit` でApple公証取得。`xcrun stapler staple` でアプリ・DMGにステープル。`Scripts/notarize.sh` の動作確認 | 最高 |
| 3-9 | DMG作成 | create-dmg でインストーラーDMG作成。背景画像・レイアウト設定。DMGにもステープル | 高 |
| 3-10 | テスト | 全Service / 全Managerクラスのユニットテスト実装・実行（10テストファイル）。全機能の手動テスト。Apple Silicon実機検証。Intel (x86_64) 検証 | 最高 |
| 3-11 | クラッシュレポート | 将来的にSentry等の導入検討（初期リリースではオプション） | 低 |
| 3-12 | macOS 16動作検証 | macOS 16ベータ/正式版でのクリップボードプライバシー動作検証。accessBehavior / detect の動作確認 | 高 |

#### Phase 3 完了条件

- ブランディングチェックリスト全15項目がクリアされている（Clipyの痕跡なし）
- 5言語のローカライズが完了し、各言語で正しく表示される
- Sparkle 2.x による自動アップデート検出が動作する
- コード署名が正しく付与され、`codesign --verify` / `spctl --assess` がパスする
- Apple公証が取得され、`xcrun stapler validate` がパスする
- 配布用DMGが作成され、DMGにもステープルが付与されている
- 全10テストファイルのユニットテストがパスする
- Apple Silicon + Intel 両アーキテクチャで動作確認済み
- macOS 14 / 15 での動作確認済み

#### Phase 3 成果物

- Revclipオリジナルアイコン一式（AppIcon.appiconset / StatusBarIcon.imageset）
- 5言語 Localizable.strings
- Sparkle.framework (2.x) + EdDSA鍵ペア
- `Scripts/notarize.sh` (動作確認済み)
- `Scripts/create_dmg.sh` (動作確認済み)
- 署名・公証済み `Revclip.app`
- 署名・公証済み `Revclip-x.x.x.dmg`
- 全10テストファイル（グリーン状態）
- `Distribution/dmg_background.png`
- `Distribution/entitlements.plist`

---

## 8. 前提条件・制約

### 8.1 前提条件

| # | 前提条件 | 詳細 |
|---|---------|------|
| 1 | **Apple Developer Program契約済み** | Developer ID Application 証明書の発行、Apple公証の実行に必要 |
| 2 | **Xcode.appインストール済み** | App Storeからインストール。`ibtool`、`actool`、`xcodebuild` の動作に必要（ただしIDEとしての手動操作は不要。Xcode.appを開く必要もない） |
| 3 | **xcode-select設定済み** | `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| 4 | **Xcodeライセンス承諾済み** | `sudo xcodebuild -license accept` |
| 5 | **公証用キーチェーンプロファイル登録済み** | `xcrun notarytool store-credentials "AC_PASSWORD"` でApp-Specific Passwordを登録 |
| 6 | **Homebrew利用可能** | xcodegen, create-dmg のインストールに使用 |

### 8.2 制約

| # | 制約 | 理由・詳細 |
|---|------|-----------|
| 1 | **Swiftは使用しない** | ユーザーの明示的な方針。Objective-Cのみで実装する |
| 2 | **Xcode.app (IDE) の手動操作は不要** | すべてのビルド操作はターミナル（Claude Code）から実行。Xcode.appはibtool/actool/xcodebuildのランタイムとしてのみ必要 |
| 3 | **ターミナル（Claude Code）完結** | プロジェクト生成・ビルド・テスト・署名・公証・DMG作成の全工程をターミナルから実行 |
| 4 | **App Sandbox無効** | クリップボード監視（NSPasteboard読み取り）、CGEventポスト（Cmd+Vシミュレーション）、Accessibility API使用のため、App Sandboxとは非互換 |
| 5 | **App Store配布不可** | App Sandbox無効のためApp Store審査基準を満たさない。Web直接配布 + DMG形式 |
| 6 | **CocoaPods不使用** | 外部ライブラリはソース直接組込またはframework直接組込。依存管理ツール不要 |
| 7 | **macOS 14.0以上必須** | Deployment Target。SMAppService (macOS 13+) 等の最新APIを使用するため |

---

## 9. リスクと対策

### 9.1 技術的リスク

| # | リスク | 影響度 | 発生確率 | 対策 |
|---|--------|--------|---------|------|
| R-001 | **macOS 16 クリップボードプライバシー保護** - プログラムによるペーストボード読み取りにシステムアラートが表示される | 最高 | 確定（macOS 15.4プレビュー済み、macOS 16正式導入） | `NSPasteboard.accessBehavior` による事前チェック。`detect` メソッドによるアラート回避戦略。初回起動時のユーザーガイダンスUI。`@available(macOS 16.0, *)` で条件分岐。macOS 14/15では従来通り動作 |
| R-002 | **Carbon API (RegisterEventHotKey) のOption系修飾キー制限** - macOS Sequoia 15でOption単独/Option+Shiftの組み合わせが機能しない | 高 | 確定（既に発生） | ホットキーレコーダーUIでの警告表示。Cmd/Ctrlを含む組み合わせを推奨。デフォルトホットキー（Cmd+Shift+V等）は影響なし。プランBとして `CGEvent.tapCreate` ベースの実装を準備 |
| R-003 | **Accessibility API制限強化** - macOS Sequoiaでの権限管理厳格化 | 中 | 中 | Accessibility権限の丁寧なガイダンスUI。TCC変更への迅速対応体制 |
| R-004 | **NSPasteboardポーリングの非効率性** - 750usポーリングによるCPU負荷 | 低 | 確定 | CPU負荷は極めて低い（changeCount整数比較のみ）。dispatch_sourceタイマーでGCD最適化。QOS_CLASS_USER_INITIATED でUI応答性への影響を回避 |
| R-005 | **Objective-Cの開発者人材確保** - Swift全盛の中でObj-C人材の確保が困難 | 中 | 中 | Obj-Cは成熟した言語であり学習コストは低い。macOS APIドキュメントはObj-C例が豊富。AI支援開発で補完可能 |
| R-006 | **Hardened Runtime + CGEvent.post の互換性** - Hardened Runtime環境下でのCGEventPost動作 | 中 | 低 | Phase 1の早い段階で動作検証を実施。Accessibility権限（TCC）が付与されていれば動作する。追加Entitlementは不要 |

### 9.2 互換性リスク

| # | リスク | 対策 |
|---|--------|------|
| R-007 | macOS 15.x (Sequoia) の新しいプライバシー制限 | Sequoia最新ベータでの継続的テスト。WWDC資料の追従 |
| R-008 | Apple Silicon + Rosetta2環境の差異 | Universal Binary (arm64 + x86_64) でビルド。両アーキテクチャでテスト |
| R-009 | Sparkle 2.xとHardened Runtimeの互換性 | Sparkle 2.x は Hardened Runtime対応済み。XPC Service経由のアップデート |
| R-010 | Xcode 16以降のビルドツールチェーン変更 | 最新Xcodeでの定期ビルド確認 |

### 9.3 UXリスク

| # | リスク | 対策 |
|---|--------|------|
| R-011 | Clipyユーザーの移行体験 | スニペットXMLインポート機能でClipyスニペットを移行可能。将来的にClipy設定自動移行を検討 |
| R-012 | ホットキーレコーダーUIのKeyHolderとの差異 | KeyHolderのUIを忠実に再現。同じキーコンボ表現を使用 |
| R-013 | 設定画面の見た目差異 | Clipyと同一のXIBレイアウトを再現。スクリーンショット比較テスト |

### 9.4 配布リスク

| # | リスク | 対策 |
|---|--------|------|
| R-014 | 公証の失敗 | Hardened Runtime + 正しいEntitlements + コード署名の事前確認。`xcrun notarytool log` で詳細ログ確認 |
| R-015 | App Store配布不可 | Web直接配布 + DMG形式。公証でGatekeeperはパス |
| R-016 | 自動アップデートの信頼性 | Sparkle 2.x のEdDSA署名で改ざん防止。HTTPSホスティング必須 |

---

## 10. 品質基準

### 10.1 コードレビュープロセス

| 項目 | 基準 |
|------|------|
| **レビュー対象** | 全ソースコード（Objective-C .h/.m ファイル） |
| **レビュー方法** | 各フェーズ完了時にレビューを実施 |
| **レビュー観点** | 機能正当性、メモリ管理（ARC下でのretain cycle防止）、スレッドセーフティ（GCDの正しい使用）、エラーハンドリング、コーディング規約準拠 |
| **コーディング規約** | Objective-C標準命名規則。クラスプレフィックス `RC`。clang-format による自動フォーマット |
| **ブランディングレビュー** | Clipyの痕跡（`CPY`, `Clipy`, `clipy-app` 等の文字列）が残っていないことの確認 |

### 10.2 テストカバレッジ要件

#### ユニットテスト（必須: 全10テストファイル）

| テストファイル | テスト対象 | テスト内容 |
|--------------|-----------|-----------|
| `RCClipboardServiceTests.m` | RCClipboardService | changeCount検出、データ型フィルタ、除外アプリ連携、同一履歴の上書き/コピー動作 |
| `RCDatabaseManagerTests.m` | RCDatabaseManager | CRUD操作、スキーマ作成、マイグレーション、data_hash検索、インデックス動作 |
| `RCSnippetTests.m` | RCSnippetFolder / RCSnippet | フォルダ・スニペットのCRUD、ドラッグ&ドロップ並替え、XMLインポート/エクスポート |
| `RCHotKeyServiceTests.m` | RCHotKeyService | ホットキー登録/解除、フォルダ個別ホットキー、Option系修飾キー警告 |
| `RCPasteServiceTests.m` | RCPasteService | ペーストボードへの書き戻し、PasteboardType別の処理、Beta修飾キー判定ロジック |
| `RCExcludeAppServiceTests.m` | RCExcludeAppService | 除外アプリ追加/削除、フロントアプリ判定、特殊アプリ（1Password等）検出 |
| `RCMenuManagerTests.m` | RCMenuManager | メニュー構築、data_hashベースのクリップ選択、ステータスアイコン切替、フォルダ分割表示 |
| `RCDataCleanServiceTests.m` | RCDataCleanService | 上限超過履歴削除、孤立ファイル削除 |
| `RCAccessibilityServiceTests.m` | RCAccessibilityService | 権限チェック、アラート表示 |
| `RCUtilitiesTests.m` | RCUtilities / NSColor+HexString | UserDefaults登録、HEXカラー変換、ファイル操作 |

#### 手動テスト（必須）

| テスト項目 | 検証内容 |
|-----------|---------|
| 全設定項目の反映 | セクション3.4の全UserDefaults設定が正しくUI・動作に反映されること |
| ホットキーのカスタム設定・動作確認 | 全5種（メイン/履歴/スニペット/履歴クリア/フォルダ個別）の登録・動作・解除 |
| Option系修飾キー警告 | macOS Sequoia以降でOption系組み合わせ設定時に警告が表示されること |
| スニペットインポート/エクスポート | Clipy XML互換の検証 |
| ドラッグ&ドロップ並替え | フォルダ・スニペットの順序変更 |
| macOS 14 / 15 / 16 動作差異確認 | 各バージョンでの動作検証 |
| Apple Silicon (arm64) 検証 | arm64ネイティブでの全機能動作確認 |
| Intel (x86_64) 検証 | x86_64ネイティブでの全機能動作確認 |
| Hardened Runtime + CGEvent.post | Accessibility権限付与後のペースト動作検証 |
| Sparkle自動アップデートフロー | アップデート検出・ダウンロード・インストールの全フロー検証 |

### 10.3 ブランディング完全性

Clipyの痕跡が一切残っていないことを保証する。以下のチェックリスト全項目をクリアすること。

| # | チェック項目 | 検証方法 |
|---|------------|---------|
| 1 | Bundle Identifier: `com.revclip.Revclip` | Info.plist の確認 |
| 2 | アプリ名: `Revclip` (CFBundleName) | Info.plist の確認 |
| 3 | 実行ファイル名: `Revclip` | バイナリの確認 |
| 4 | アプリアイコン: Revclipオリジナル | 視覚的確認 |
| 5 | ステータスバーアイコン: Revclipオリジナル | 視覚的確認 |
| 6 | ソースコードコメント: 全ファイルヘッダーが「Revclip」 | `grep -r "Clipy" Revclip/` で検索してヒットなし |
| 7 | クラスプレフィックス: `RC`（`CPY` なし） | `grep -r "CPY" Revclip/` で検索してヒットなし |
| 8 | UserDefaultsキー: `kRC` プレフィックス（`kCPY` なし） | `grep -r "kCPY" Revclip/` で検索してヒットなし |
| 9 | Application Supportフォルダ: `~/Library/Application Support/Revclip/` | 実行時のパス確認 |
| 10 | ローカライズ文字列: 「Clipy」を含まない | 全 .strings ファイルの検索 |
| 11 | About画面: Revclipの著作権表示 | 視覚的確認 |
| 12 | Sparkle feedURL: Revclip独自のappcast URL | Info.plist の確認 |
| 13 | コード署名: Revclip用Developer ID | `codesign -d --verbose` で確認 |
| 14 | README / LICENSE: Revclipとしての表記 | ファイル内容の確認 |
| 15 | GitHubリポジトリ名: Revclip | リポジトリURLの確認 |

---

## 付録A: 設定項目全量マッピング

Clipyの全UserDefaults設定キーとRevclipでの対応キーの全量マッピング。

### General カテゴリ

| 設定項目 | Clipyキー | Revclipキー | デフォルト値 |
|---------|----------|------------|------------|
| 最大履歴数 | kCPYPrefMaxHistorySizeKey | kRCPrefMaxHistorySizeKey | 30 |
| ログイン起動 | loginItem | loginItem | NO |
| ログイン起動アラート抑制 | suppressAlertForLoginItem | suppressAlertForLoginItem | NO |
| ペーストコマンド入力 | kCPYPrefInputPasteCommandKey | kRCPrefInputPasteCommandKey | YES |
| ペースト後に履歴を並べ替え | kCPYPrefReorderClipsAfterPasting | kRCPrefReorderClipsAfterPasting | YES |
| ステータスバー表示タイプ | kCPYPrefShowStatusItemKey | kRCPrefShowStatusItemKey | 1 (black) |
| 保存対象タイプ | kCPYPrefStoreTypesKey | kRCPrefStoreTypesKey | 全タイプYES |
| 同一履歴の上書き | kCPYPrefOverwriteSameHistroy | kRCPrefOverwriteSameHistory | YES |
| 同一履歴のコピー | kCPYPrefCopySameHistroy | kRCPrefCopySameHistory | YES |
| クラッシュレポート収集 | kCPYCollectCrashReport | kRCCollectCrashReport | YES |

### Menu カテゴリ

| 設定項目 | Clipyキー | Revclipキー | デフォルト値 |
|---------|----------|------------|------------|
| インライン表示数 | kCPYPrefNumberOfItemsPlaceInlineKey | kRCPrefNumberOfItemsPlaceInlineKey | 0 |
| フォルダ内表示数 | kCPYPrefNumberOfItemsPlaceInsideFolderKey | kRCPrefNumberOfItemsPlaceInsideFolderKey | 10 |
| 最大タイトル長 | kCPYPrefMaxMenuItemTitleLengthKey | kRCPrefMaxMenuItemTitleLengthKey | 20 |
| メニューアイコンサイズ | kCPYPrefMenuIconSizeKey | kRCPrefMenuIconSizeKey | 16 |
| メニューにアイコン表示 | kCPYPrefShowIconInTheMenuKey | kRCPrefShowIconInTheMenuKey | YES |
| 番号表示 | menuItemsAreMarkedWithNumbers | menuItemsAreMarkedWithNumbers | YES |
| 番号を0から開始 | kCPYPrefMenuItemsTitleStartWithZeroKey | kRCPrefMenuItemsTitleStartWithZeroKey | NO |
| ツールチップ | showToolTipOnMenuItem | showToolTipOnMenuItem | YES |
| ツールチップ最大長 | maxLengthOfToolTipKey | maxLengthOfToolTipKey | 200 |
| 画像表示 | showImageInTheMenu | showImageInTheMenu | YES |
| カラーコードプレビュー | kCPYPrefShowColorPreviewInTheMenu | kRCPrefShowColorPreviewInTheMenu | YES |
| 数字キーショートカット付加 | addNumericKeyEquivalents | addNumericKeyEquivalents | NO |
| サムネイル幅 | thumbnailWidth | thumbnailWidth | 100 |
| サムネイル高さ | thumbnailHeight | thumbnailHeight | 32 |
| 「履歴クリア」メニュー項目表示 | kCPYPrefAddClearHistoryMenuItemKey | kRCPrefAddClearHistoryMenuItemKey | YES |
| 履歴クリア前の確認アラート | kCPYPrefShowAlertBeforeClearHistoryKey | kRCPrefShowAlertBeforeClearHistoryKey | YES |

### Shortcuts カテゴリ

| 設定項目 | Clipyキー | Revclipキー |
|---------|----------|------------|
| メインメニュー | kCPYHotKeyMainKeyCombo | kRCHotKeyMainKeyCombo |
| 履歴メニュー | kCPYHotKeyHistoryKeyCombo | kRCHotKeyHistoryKeyCombo |
| スニペットメニュー | kCPYHotKeySnippetKeyCombo | kRCHotKeySnippetKeyCombo |
| 履歴クリア | kCPYClearHistoryKeyCombo | kRCClearHistoryKeyCombo |
| フォルダ個別ホットキー | kCPYFolderKeyCombos | kRCFolderKeyCombos |
| ホットキーマイグレーションフラグ | kCPYMigrateNewKeyCombo | kRCMigrateNewKeyCombo |
| レガシーホットキー設定 | kCPYPrefHotKeysKey | kRCPrefHotKeysKey |

### Updates カテゴリ

| 設定項目 | Clipyキー | Revclipキー | デフォルト値 |
|---------|----------|------------|------------|
| 自動チェック | kCPYEnableAutomaticCheckKey | kRCEnableAutomaticCheckKey | YES |
| チェック間隔 (秒) | kCPYUpdateCheckIntervalKey | kRCUpdateCheckIntervalKey | 86400 |

### Beta カテゴリ

| 設定項目 | Clipyキー | Revclipキー | デフォルト値 |
|---------|----------|------------|------------|
| プレーンテキスト貼付 | kCPYBetaPastePlainText | kRCBetaPastePlainText | YES |
| プレーンテキスト貼付の修飾キー | kCPYBetaPastePlainTextModifier | kRCBetaPastePlainTextModifier | 0 (Cmd) |
| 履歴削除 | kCPYBetaDeleteHistory | kRCBetaDeleteHistory | NO |
| 履歴削除の修飾キー | kCPYBetaDeleteHistoryModifier | kRCBetaDeleteHistoryModifier | 0 (Cmd) |
| ペースト後に履歴を削除 | kCPYBetaPasteAndDeleteHistory | kRCBetaPasteAndDeleteHistory | NO |
| ペースト&削除の修飾キー | kCPYBetapasteAndDeleteHistoryModifier | kRCBetapasteAndDeleteHistoryModifier | 0 (Cmd) |
| スクリーンショット監視 | kCPYBetaObserveScreenshot | kRCBetaObserveScreenshot | NO |

### Exclude カテゴリ

| 設定項目 | Clipyキー | Revclipキー |
|---------|----------|------------|
| 除外アプリ | kCPYExcludeApplications | kRCExcludeApplications |

### Snippets カテゴリ

| 設定項目 | Clipyキー | Revclipキー |
|---------|----------|------------|
| スニペット削除アラート抑制 | kCPYSuppressAlertForDeleteSnippet | kRCSuppressAlertForDeleteSnippet |

---

## 付録B: SQLiteスキーマ

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

---

## 付録C: ディレクトリ構成

```
Revclip/
├── Revclip.xcodeproj/                     # xcodegen生成
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
│   │   ├── en.lproj/Localizable.strings
│   │   ├── ja.lproj/Localizable.strings
│   │   ├── de.lproj/Localizable.strings
│   │   ├── zh-Hans.lproj/Localizable.strings
│   │   └── it.lproj/Localizable.strings
│   ├── App/
│   │   ├── RCAppDelegate.h / .m
│   │   ├── RCConstants.h / .m
│   │   └── RCEnvironment.h / .m
│   ├── Services/
│   │   ├── RCClipboardService.h / .m
│   │   ├── RCPasteService.h / .m
│   │   ├── RCHotKeyService.h / .m
│   │   ├── RCAccessibilityService.h / .m
│   │   ├── RCExcludeAppService.h / .m
│   │   ├── RCDataCleanService.h / .m
│   │   └── RCLoginItemService.h / .m
│   ├── Managers/
│   │   ├── RCMenuManager.h / .m
│   │   └── RCDatabaseManager.h / .m
│   ├── Models/
│   │   ├── RCClipItem.h / .m
│   │   ├── RCClipData.h / .m
│   │   ├── RCSnippetFolder.h / .m
│   │   ├── RCSnippet.h / .m
│   │   ├── RCAppInfo.h / .m
│   │   └── RCDraggedData.h / .m
│   ├── UI/
│   │   ├── Preferences/
│   │   │   ├── RCPreferencesWindowController.h / .m + .xib
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
│   │   │   └── RCHotKeyRecorderView.h / .m
│   │   └── Views/
│   │       ├── RCSplitView.h / .m
│   │       ├── RCDesignableView.h / .m
│   │       └── RCDesignableButton.h / .m
│   ├── Utilities/
│   │   ├── RCUtilities.h / .m
│   │   ├── NSColor+HexString.h / .m
│   │   ├── NSImage+Resize.h / .m
│   │   └── NSImage+Color.h / .m
│   └── Vendor/
│       ├── FMDB/                          # SQLiteラッパー (ソース組込)
│       └── Sparkle.framework/             # 自動アップデート (2.x)
├── RevclipTests/
│   ├── RCClipboardServiceTests.m
│   ├── RCDatabaseManagerTests.m
│   ├── RCSnippetTests.m
│   ├── RCHotKeyServiceTests.m
│   ├── RCPasteServiceTests.m
│   ├── RCExcludeAppServiceTests.m
│   ├── RCMenuManagerTests.m
│   ├── RCDataCleanServiceTests.m
│   ├── RCAccessibilityServiceTests.m
│   └── RCUtilitiesTests.m
├── project.yml                            # xcodegen プロジェクト定義
├── Makefile                               # 便利コマンドラッパー
├── Scripts/
│   ├── build.sh
│   ├── notarize.sh
│   ├── create_dmg.sh
│   └── export_strings.sh
└── Distribution/
    ├── dmg_background.png
    └── entitlements.plist
```

---

## 付録D: 工数見積もり

| フェーズ | 期間 | 主要タスク |
|---------|------|----------|
| Phase 1: 基盤構築 | 2-3週間 | プロジェクト設定、DB層、クリップボード監視、メニュー表示、ペースト、macOS 16プライバシー基盤 |
| Phase 2: UI/UX完成 | 2-3週間 | ホットキー（フォルダ個別含む）、設定画面7タブ（全設定項目）、スニペットエディタ、除外アプリ、UIコンポーネント |
| Phase 3: 配布準備 | 1-2週間 | ブランディング、5言語ローカライズ、Sparkle 2.x統合、署名・公証、DMG、テスト（全Service/Manager） |
| **合計** | **5-8週間** | |

---

> **本SOWは `revclip_plan.md` Rev.4 確定版および `revclip_plan_review.md` のLGTM判定に基づいて作成された。実装プランで承認された全仕様・全設計を網羅している。**
