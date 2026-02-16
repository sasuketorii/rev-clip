<div align="center">

<img src="revclip.png" alt="Revclip" width="128">

# Revclip

> **「コピーしたものは、あなたの Mac から一歩も出ない。」**

macOS ネイティブのクリップボードマネージャー。Clipy の体験を、現代 macOS 向けにゼロから再構築。

[![Version](https://img.shields.io/badge/version-0.0.15-blue?style=flat)](https://github.com/sasuketorii/rev-clip/releases)
[![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-000000?style=flat&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Free](https://img.shields.io/badge/price-free-2ea043?style=flat)](https://github.com/sasuketorii/rev-clip/releases)
[![Universal Binary](https://img.shields.io/badge/arch-arm64%20%2B%20x86__64-green?style=flat)](https://developer.apple.com/documentation/apple-silicon/)
[![License](https://img.shields.io/badge/license-All%20rights%20reserved-lightgrey?style=flat)](#)

</div>

---

## 4つの柱

| 柱 | 内容 |
|---|---|
| **100% ローカル** | クラウドなし、テレメトリなし、アカウント不要 |
| **Clipy 後継** | スニペットをワンクリックで移行 |
| **依存 2 つ** | Sparkle + FMDB のみ。App 4.9MB / 実行ファイル 1.1MB |
| **無料** | サブスクなし。ダウンロードしてすぐ使える |

---

## なぜ Revclip なのか

### あなたのクリップボードは、あなただけのもの

Apple は macOS 15.4 以降で、**ユーザー操作なしのクリップボード読み取りに対するプライバシー制御**を導入しました。
つまり OS ベンダー自身が、クリップボードを「機密データが集まる場所」として扱っています。

実際にクリップボードには、以下が日常的に入ります。

- パスワード
- クレジットカード番号
- 暗号資産ウォレットアドレス
- API キー / トークン
- 医療情報
- 銀行口座情報

Revclip は、**保存先を Mac ローカルに限定**しています。
データベースは `~/Library/Application Support/Revclip/revclip.db`、クリップ実体は `~/Library/Application Support/Revclip/ClipsData/` に保存されます。

- iCloud 同期系アプリはクリップボードデータを Apple サーバーに複製します。法執行機関からの開示請求対象にもなり得ます
- Revclip は**ネットワーク通信なし・クラウドなし**。外部サーバーに履歴が残らない設計です
- ネットワーク利用はソフトウェア更新チェックのみ
- テレメトリ・分析用の送信コードは存在しません（ソースコードで検証可能）
- `ConcealedType` / `TransientType` を自動スキップし、パスワードマネージャー由来の機密データを履歴に残しません
- 強化されたランタイム保護を有効化、Apple 公証済み配布、macOS 15.4+ のクリップボードプライバシー API に対応

たとえ Mac 端末が侵害された場合でも、少なくとも「過去のクリップボード履歴がクラウド側に保存済み」という状態は発生しません。

### Clipy ユーザーの方へ

Clipy は歴史ある優れたクリップボードマネージャーですが、現行 macOS との互換維持は厳しくなっています。

- 最終リリースは 2018 年（v1.2.1）、未解決の Issue は 235 件超（2026-02-16 時点）
- macOS Sequoia 関連の主要報告:
  - [Issue #559](https://github.com/Clipy/Clipy/issues/559): スニペット編集でクラッシュ
  - [Issue #567](https://github.com/Clipy/Clipy/issues/567): macOS 15.3.1 で起動しない
- データ基盤の Realm は、フレームワーク単体で 422MB 規模になる事例があり、既知の破損報告（[realm-swift #4302](https://github.com/realm/realm-swift/issues/4302)）もあります
- ログイン項目の実装に使われていた LoginServiceKit は 2025年12月にアーカイブ済みで、非推奨の `LSSharedFileList` に依存
- バイナリは x86_64 のみで、Apple Silicon では Rosetta が必要

Revclip は同じメニューバー体験を、現代 macOS 向けにゼロから作り直しました。

- スニペットはワンクリックで移行可能（Clipy データフォルダを自動提案）
- 依存ライブラリは 15+ から 2 へ
- ネイティブ Objective-C / AppKit で保守しやすい構成

### サブスクリプション？不要です

長期利用で見ると、料金差ははっきりします。

| アプリ / プラン | 1年あたり | 5年総額 |
|---|---:|---:|
| Paste（月額 `$3.99`） | `$47.88` | `$239.40` |
| Paste（年額 `$29.99`） | `$29.99` | `$149.95` |
| Maccy（App Store） | `$9.99`（買い切り） | `$9.99`（※スニペットなし） |
| **Revclip** | **`$0`** | **`$0`** |

Revclip は **無料**、**アカウント不要**、**ライセンスキー不要**です。

---

## 主な機能

- **カラーコードプレビュー** — `#007FFF` のような HEX をコピーすると、履歴メニューに**カラースウォッチが並んで表示**され、文字列だけでは分かりにくい色を一目で判別
- **クリップボード履歴** — テキスト、画像、RTF/RTFD、PDF、ファイル、カラーコードなど主要形式に対応
- **テンプレートエディタ** — フォルダベースのスニペット管理、インポート/エクスポート対応
- **グローバルホットキー** — Carbon API によるシステム全体のショートカット + フォルダごとの個別ホットキー
- **アプリ除外** — Bundle ID ベースで 1Password 等を監視対象から除外
- **スクリーンショット取り込み** — スクリーンショット自動取り込み（Beta）
- **5言語対応** — 英語、日本語、ドイツ語、中国語（簡体字）、イタリア語

---

## 技術へのこだわり

### データの安全性

- SHA256 による重複検出は、ビッグエンディアンの長さプレフィクス付きで実装し、連結由来のハッシュ衝突を回避
- `NSSecureCoding` + クラス許可リストにより、想定外クラスの逆シリアライズを防止
- アトミックなファイル書き込み（`NSDataWritingAtomic`）で、クラッシュ時の中途半端な書き込みを防止
- データベース操作はトランザクションベースで、失敗時は明示的にロールバック制御

### パフォーマンス

- 2本の直列キュー構成で、クリップボード監視とファイル I/O を相互にブロックさせない
- 画像サムネイルは `CGImageSource` を使い、フル画像をメモリ展開せず生成
- GCD タイマーに leeway を設定し、OS の省電力スケジューリングを活用
- SQLite はインデックス設計済みで、履歴検索を即時応答

### 最新の macOS API

- グローバルホットキーは Carbon API を直接使用し、ライブラリラッパーより低レイヤーでイベントを処理
- ログイン項目は `SMAppService` を採用（非推奨の `LSSharedFileList` は不使用）
- macOS 15.4+ ではクリップボードプライバシー API（`NSPasteboard.accessBehavior`）に対応
- 強化されたランタイム保護 + Developer ID 署名 + Apple 公証で配布

### 最小限の依存

- 外部依存は 2 つのみ（Clipy の 15+ と対照的）
- CocoaPods / SPM / Carthage に依存せず、同梱管理でビルドの再現性を担保
- それ以外は macOS 標準フレームワーク（AppKit, Carbon, CommonCrypto, ServiceManagement）のみ

---

## 競合比較

| | **Revclip** | **Paste** | **Maccy** | **Clipy** |
|---|---|---|---|---|
| 価格 | 無料 | $3.99/月（サブスク） | $9.99（App Store）/ 無料（GitHub） | 無料 |
| データ保存先 | 100% ローカル | iCloud 同期 | ローカル | ローカル |
| アプリサイズ | 4.9 MB | 133.6 MB | 約 15 MB | 約 30 MB |
| 外部依存 | 2（Sparkle + FMDB） | 多数 | 少数 | 15+（Realm, RxSwift 等） |
| スニペット | あり + インポート/エクスポート | あり | なし | あり（Sequoia で問題報告） |
| カラープレビュー | あり（メニューにスウォッチ表示） | 不明 | なし | なし |
| パスワード保護 | ConcealedType 自動スキップ | 不明 | 不明 | なし |
| macOS 15.4+ プライバシー API | 対応 | 不明 | 不明 | 非対応 |
| 最終リリース | 2026年（開発中） | 開発中 | 開発中 | 2018年（以降リリースなし） |
| コード署名 | Developer ID + 公証済み | あり | あり | Developer ID + 公証済み |
| Apple Silicon | ネイティブ Universal | 対応 | 対応 | x86_64 のみ（Rosetta 必要） |
| macOS Sequoia | 完全対応 | 対応 | 対応 | クラッシュ報告あり |

*競合情報は 2026年2月16日時点の調査値です。*

---

## インストール

1. [Releases](https://github.com/sasuketorii/rev-clip/releases) から DMG をダウンロード
2. `Revclip.app` を `/Applications` にドラッグ
3. 起動して完了

---

## Clipy からの移行

1. テンプレートエディタを開く
2. インポートを選択
3. 提案される Clipy データフォルダ（`~/Library/Application Support/com.clipy-app.Clipy`）を選び、マージまたは置換を選択

---

<details>
<summary><strong>技術詳細</strong></summary>

### アーキテクチャ

```text
Menu Bar (AppKit / Objective-C)
  -> RCClipboardService (monitor)
  -> RCExcludeAppService (Bundle ID exclusion)
  -> RCPrivacyService (macOS 15.4+ clipboard privacy)
  -> RCDatabaseManager (SQLite via FMDB)
  -> ClipsData/ (file blobs)
  -> RCUpdateService (Sparkle updates)
```

### 依存ライブラリ

| ライブラリ | 目的 |
|---|---|
| Sparkle 2.x | 安全な自動アップデート |
| FMDB | SQLite ラッパー |

### ビルド

```bash
cd src/Revclip
xcodegen generate
xcodebuild -project Revclip.xcodeproj -scheme Revclip -configuration Release build
```

### 仕様

| 項目 | 値 |
|---|---|
| バージョン | 0.0.15 |
| 言語 | Objective-C |
| UI | AppKit |
| 最小 macOS | 14.0 |
| バイナリ | Universal（`arm64`, `x86_64`） |
| DB パス | `~/Library/Application Support/Revclip/revclip.db` |
| クリップデータパス | `~/Library/Application Support/Revclip/ClipsData/` |
| 強化ランタイム | 有効 |
| 公証 | リリースワークフローで有効 |
| 外部依存 | 2 |

### ソースコードの根拠

- ConcealedType スキップ: `src/Revclip/Revclip/Services/RCClipboardService.m:182`
- Bundle ID によるアプリ除外: `src/Revclip/Revclip/Services/RCExcludeAppService.m:43`
- macOS 15.4+ プライバシー API: `src/Revclip/Revclip/Services/RCPrivacyService.m:206`
- Clipy インポートのデフォルトパス: `src/Revclip/Revclip/UI/SnippetEditor/RCSnippetEditorWindowController.m:1390`
- ローカル DB パスの組み立て: `src/Revclip/Revclip/Managers/RCDatabaseManager.m:719`
- ローカルクリップパス定数: `src/Revclip/Revclip/App/RCConstants.m:69`

</details>

---

## FAQ

**Q. クラウド同期はありますか？**  
A. ありません。Revclip は設計として 100% ローカル保存です。

**Q. テレメトリは送信されますか？**
A. 送信されません。テレメトリ・分析・追跡の実装はなく、ネットワーク利用はソフトウェア更新チェックのみです。

**Q. 1Password のパスワードは履歴に入りますか？**
A. 入りません。`ConcealedType` / `TransientType` を自動スキップします。さらに、設定からアプリ単位で除外指定ができるため、自分でセキュリティを強化することも可能です。

**Q. Clipy のスニペットは移行できますか？**
A. はい。テンプレートエディタからワンクリックでインポートできます。

---

<div align="center">

Copyright 2024-2026 Revclip. All rights reserved.

**REV-C Inc.**

</div>
