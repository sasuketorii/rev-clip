# Revclip 実装プラン レビュー (Rev.4)

> Reviewer: codex (Claude Opus 4.6)
> Review Date: 2026-02-13
> 対象: `revclip_plan.md` Rev.4
> 検証方法: Rev.3レビューで提示した指摘事項 N-1, N-2, N-3 の修正箇所を全文検索・照合

---

## 総合評価

**LGTM**

前回の条件付きLGTMで提示した3件の指摘事項（N-1: Critical、N-2: Minor、N-3: Minor）はすべて適切に修正されている。旧シンタックスの残存や記載の矛盾も検出されなかった。本プランは実装開始可能である。

---

## 指摘事項の対応確認

### N-1 (Critical): Xcode.appの依存関係が正しく記載されているか

**結果: 解消済み**

以下の全箇所で修正が確認された。

1. **セクション1 技術スタック選定テーブル（行170）**:
   - ビルドシステムの説明が `「Xcode.appのインストールが必要（ただしIDEとしての手動操作は不要）。すべてターミナル(xcodebuild/ibtool/actool等)で完結」` に修正されている。
   - 「IDEとしての手動操作は不要」が明記されている。

2. **セクション5.6.1 開発環境の前提（行1024-1050）**:
   - 冒頭に `「ibtool、actool、xcodebuild は Xcode Command Line Tools 単体では動作しない。これらのツールは Xcode.app のインストールが前提となる。ただし、Xcode.app を IDE として手動操作する必要は一切なく、App Store からインストールするだけでよい（Xcode.app を開く必要もない）」` の注記が追加されている。
   - ツールテーブルの最上位行に `Xcode.app (必須)` が追加され、インストール方法が `「App Storeからインストール（IDEとしての手動操作は不要）」` と記載されている。
   - `xcodebuild`, `ibtool`, `actool` の各行のインストール方法が `「Xcode.app同梱（Command Line Tools単体では不可）」` に修正されている。

3. **開発環境セットアップスクリプト（行1042-1047）**:
   - Step 1 として `Xcode.appのインストール（App Storeから）` が追記されている。
   - Step 2 として `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` が明記されている。
   - `xcode-select -s` の手順が含まれている。

4. **Phase 1タスク1-1（行581）**:
   - `「Xcode.appの手動操作は不要」` が明記されている。

5. **セクション5.6.5（行1165-1178）**:
   - Xcode.appでの各操作とターミナルでの代替コマンドの対応表が維持されており、すべてのビルド操作がターミナルで完結することが明確に示されている。

**判定**: 前回指摘した3つの推奨アクション（インストール方法の修正、注記の追加、セットアップコマンドの修正）がすべて実施されている。

---

### N-2 (Minor): notarytool のシンタックスが --keychain-profile "AC_PASSWORD" に修正されているか

**結果: 解消済み**

`notarytool submit` および `notarytool log` の全箇所を確認した。

1. **セクション5.4 notarize.sh Step 4（行953-956）**:
   - `[Rev.4 修正]` の注記付きで `--keychain-profile "AC_PASSWORD"` に修正済み。
   - 旧シンタックス `--password "@keychain:AC_PASSWORD"` は残存していない（行953のコメントで旧シンタックスが使えない旨の説明として言及されているのみ）。

2. **セクション5.4 notarize.sh Step 5（行969-971）**:
   - `notarytool log` でも `--keychain-profile "AC_PASSWORD"` を使用。修正済み。

3. **セクション5.6.3 リリースビルドコマンド一覧（行1136-1139）**:
   - `[Rev.4 修正]` の注記付きで `--keychain-profile "AC_PASSWORD"` に修正済み。

4. **セクション5.6.4 キーチェーン登録（行1155-1161）**:
   - `store-credentials` コマンドで `--apple-id`, `--team-id`, `--password` を使用しているが、これは `store-credentials` サブコマンドの正しいシンタックスであり、問題ない（`store-credentials` は初回のクレデンシャル保存コマンドであり、`submit`/`log` とは異なる）。

5. **残存チェック**: `@keychain:` のパターンでファイル全体を検索した結果、行953のコメント（旧シンタックスが使えない旨の説明）以外にはヒットなし。実コマンドには旧シンタックスは一切残っていない。

**判定**: 全箇所で一貫して `--keychain-profile "AC_PASSWORD"` に統一されている。

---

### N-3 (Minor): submission ID の抽出ロジックが正しいか

**結果: 解消済み**

1. **セクション5.4 notarize.sh Step 4-5（行954-971）**:
   - Step 4 で `notarytool submit --wait` の出力を変数 `SUBMIT_OUTPUT` にキャプチャする設計に変更されている（行954: `SUBMIT_OUTPUT=$(xcrun notarytool submit ... --wait 2>&1)`）。
   - Step 5 で `SUBMIT_OUTPUT` から `grep -m1 '  id:'` + `awk '{print $2}'` で submission ID を抽出している（行966）。
   - `notarytool submit --wait` の出力フォーマット（`  id: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`）がコメント（行962-965）に明記されており、抽出パターンが出力フォーマットと合致している。
   - 旧ロジック（`notarytool history | head -5` をそのまま `notarytool log` に渡すパイプ）は完全に除去されている。

2. **抽出ロジックの妥当性確認**:
   - `notarytool submit --wait` の実際の出力は `  id: <UUID>` 形式であり、`grep -m1 '  id:'` は最初の `id:` 行にマッチする。先頭2スペースのインデントを含むパターンにしている点も、誤マッチ防止として適切。
   - `awk '{print $2}'` で `id:` の次のフィールド（UUID値）を取得する設計は正しい。
   - 抽出した `SUBMISSION_ID` を `notarytool log` に渡すフロー（行970-971）も正しい。

**判定**: submission ID の抽出ロジックが、前回指摘した推奨アクションに沿って正しく修正されている。

---

## 修正チェックリスト（最終確認）

- [x] **N-1 (Critical)**: Xcode.appのインストールが必須である旨が明記されている。`xcode-select -s` の手順が含まれている。「IDEとしての手動操作は不要」が明記されている。全5箇所で一貫性を確認済み。
- [x] **N-2 (Minor)**: `notarytool` の全コマンド（submit, log）で `--keychain-profile "AC_PASSWORD"` に統一されている。旧 `altool` シンタックスの残存なし。`store-credentials` のシンタックスは正しい。
- [x] **N-3 (Minor)**: `notarytool submit --wait` の出力をキャプチャし、`grep` + `awk` で submission ID を抽出するロジックに修正されている。旧ロジック（`history | head -5`）は除去済み。

---

## 総評

Rev.4で3件の指摘事項がすべて解消された。Rev.1からRev.4までの4回のイテレーションを通じて、以下が達成されている:

- Clipyの全機能・全設定項目・全UIコンポーネントの完全なカバレッジ
- macOS 16クリップボードプライバシー対応、Sequoiaホットキー制限への具体的な設計
- ターミナル完結のビルド・署名・公証フローの正確な記述
- Xcode.app依存関係の正確な記載
- 全15件の指摘事項（C-1, C-2, M-1〜M-6, m-1〜m-7, N-1〜N-3）の解消

**本プランは実装開始可能である。**
