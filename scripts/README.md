# scripts/

Revclip プロジェクトで使用するビルド、リリース、ユーティリティスクリプト群。

---

## リリース関連

### `bump-version.sh`

`project.yml` と `Info.plist` のバージョンを一括更新するスクリプト。
二重管理（project.yml / Info.plist）によるバージョン不整合を防止する。

```
./scripts/bump-version.sh <version> [--tag] [--push]
```

| オプション | 説明 |
|-----------|------|
| `<version>` | バージョン番号（`0.0.19` または `v0.0.19`） |
| `--tag` | git commit + tag を作成 |
| `--push` | リモートに push（`--tag` 必須）。CI が起動する |
| `-h, --help` | ヘルプ表示 |

**使用例:**

```bash
./scripts/bump-version.sh 0.0.19              # バージョン更新のみ
./scripts/bump-version.sh 0.0.19 --tag        # + git commit + tag
./scripts/bump-version.sh 0.0.19 --tag --push # + リモート push（CI 起動）
```

**更新対象ファイル:**
- `src/Revclip/project.yml` -- `CFBundleShortVersionString`, `CFBundleVersion`
- `src/Revclip/Revclip/Info.plist` -- 同上

**前提:** macOS 環境（PlistBuddy を使用）

---

### `release.sh`

ローカルリリースビルドの全工程を実行する。バージョン更新から DMG 生成、Sparkle 署名、appcast.xml 生成までを一貫して行う。

```
./scripts/release.sh v0.0.19
./scripts/release.sh 0.0.19
```

**実行フロー:** バージョン更新 → xcodegen → xcodebuild archive → DMG パッケージ → Sparkle EdDSA 署名 → appcast.xml 生成

**環境変数（任意）:**

| 変数 | 説明 |
|-----|------|
| `CODE_SIGNING_IDENTITY` | コード署名 ID（デフォルト: `-` = ad-hoc） |
| `BUILD_NUMBER` | CFBundleVersion の上書き（デフォルト: patch 番号） |
| `DOWNLOAD_URL_PREFIX` | appcast のダウンロード URL プレフィックス |
| `SPARKLE_PRIVATE_KEY` | Sparkle EdDSA 秘密鍵（未設定時は Keychain から読み取り） |

**前提:** macOS 14.0+, xcodegen, Sparkle tools (`sign_update`, `generate_appcast`)

---

## ビルド関連

### `build-dev.sh`

ローカル開発ビルド用スクリプト。署名・公証なしでビルドを確認する。

```
./scripts/build-dev.sh [--platform macos|ios] [--release] [--dry-run]
```

| オプション | 説明 |
|-----------|------|
| `--platform` | 対象プラットフォーム（デフォルト: `macos`） |
| `--release` | リリースビルド（署名は行わない） |
| `--dry-run` | コマンド表示のみ |

> **注意:** Agent Base フレームワーク由来のスクリプト（Tauri 向け）。Revclip (Xcode/Objective-C) のビルドには `release.sh` を使用すること。

---

### `sign-and-build.sh`

リリース用の署名・公証パイプライン。ビルド → コード署名 → 公証 → staple を一貫して実行する。

```
./scripts/sign-and-build.sh [options]
```

| オプション | 説明 |
|-----------|------|
| `--platform macos\|ios` | 対象プラットフォーム（デフォルト: `macos`） |
| `--app-bundle <path>` | 署名対象の `.app` パス（省略時は自動検出） |
| `--entitlements <plist>` | entitlements ファイルパス |
| `--skip-notarize` | 公証をスキップ |
| `--skip-build` | ビルドをスキップし既存バンドルを使用 |
| `--debug` | デバッグビルドを署名対象にする |
| `--dry-run` | コマンド表示のみ |

**必須環境変数（macOS）:** `APPLE_CERT_BASE64`, `APPLE_CERT_PASSWORD`, `APPLE_DEVELOPER_ID`
**公証用（いずれか一方）:**
- API キー方式: `APPLE_NOTARY_ISSUER_ID`, `APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_PRIVATE_KEY`
- Apple ID 方式: `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD`

---

## ユーティリティ

### `generate_icons.py`

AppIcon と StatusBar アイコンを Python で生成する。グラデーション背景にクリップボードのシルエットを描画し、各サイズの PNG と `Contents.json` を出力する。

```bash
pip install Pillow
python scripts/generate_icons.py
```

**出力先:** `src/Revclip/Revclip/Resources/Assets.xcassets/`
- `AppIcon.appiconset/` -- 16px ~ 1024px
- `StatusBarIcon.imageset/` -- 18px, 36px

---

### `init-project.sh`

Agent Base プロジェクトの初期化スクリプト。ディレクトリ構造の作成、テンプレートファイルの生成、`.gitignore` の更新を行う。

```bash
./scripts/init-project.sh [project_name]
```

プロジェクト名を省略した場合、カレントディレクトリ名が使用される。

---

### `quality_gate.sh`

品質ゲートを段階的に実行する（Cargo ツールチェーン向け）。

```bash
./scripts/quality_gate.sh [--level A|B|C]
```

| レベル | 内容 |
|-------|------|
| A (Hotfix) | `cargo fmt` のみ |
| B (通常) | fmt + clippy + test + audit |
| C (リリース候補) | Level B + bench |

コマンドが未インストールの場合はスキップして警告を表示する。

---

## エージェント連携

### Codex ラッパー群

Codex CLI のモデル設定を強制固定するラッパースクリプト。エージェントオーケストレーション（`CLAUDE.md` 参照）で使用する。

| スクリプト | 推論レベル | 用途 |
|-----------|-----------|------|
| `codex-wrapper.sh` | xhigh | 基本ラッパー（モデル強制固定） |
| `codex-wrapper-medium.sh` | medium | 軽量タスク（ドキュメント生成、簡易修正） |
| `codex-wrapper-high.sh` | high | Coder（実装タスク） |
| `codex-wrapper-xhigh.sh` | xhigh | Reviewer（コードレビュー） |

**基本的な使い方:**

```bash
cat prompt.md | ./scripts/codex-wrapper-high.sh --stdin > output.md
```

全ラッパーは `-c model=...` や `-c model_reasoning_effort=...` の上書きを自動的にブロックする。

---

### `hydra`

シェルスクリプト（内部ツール）。
