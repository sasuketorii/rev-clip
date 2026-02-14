# 調査依頼: Sparkle アップデート署名エラーの根本原因調査

## AGENT_ROLE=investigator

あなたはバグ調査担当です。以下の問題の根本原因を特定してください。

## 許可事項
ユーザーからの明示的許可: メインブランチで作業してOKです。Worktree/ブランチを切る必要はありません。
ただし、このタスクは**調査のみ**です。コードの変更は行わないでください。

## バグ概要
Revclip v0.0.7 からアプリ内アップデート（Sparkle 2.x）を実行すると、以下のエラーが表示される:
「アップデートの署名が不適切で認証できませんでした。あとでやり直すかアプリケーション開発者に連絡してください。」

英語では "An update signature was invalid and could not be verified" に相当する Sparkle エラー。

## 技術背景
- Sparkle 2.6.4 を使用
- EdDSA (ed25519) 署名方式
- アプリの `SUPublicEDKey` は `jW5CH5/B8IApRFYiwOGot/VUmo0uqvE1LawgUG1igUk=`
- appcast.xml は GitHub Releases の latest/download から配信
- DMG は CI (GitHub Actions) で作成・署名・公証される

## 調査すべき項目

### 1. appcast.xml の内容確認
- GitHub Releases から appcast.xml をダウンロードして内容を確認
- `sparkle:edSignature` 属性が存在するか
- `enclosure` の `url`, `length`, `sparkle:version`, `sparkle:shortVersionString` が正しいか
- URL: `https://github.com/sasuketorii/rev-clip/releases/latest/download/appcast.xml`

### 2. CI ワークフローの署名順序確認
- `.github/workflows/release.yml` を読んで、以下の順序を確認:
  - DMG 作成
  - Apple 公証 (notarytool + stapler)
  - Sparkle EdDSA 署名 (sign_update)
  - appcast.xml 生成 (generate_appcast)
- **重要**: `xcrun stapler staple` は DMG を変更する。その後に EdDSA 署名しているか？
  それとも署名後に staple して署名が無効化されていないか？

### 3. SUPublicEDKey の一致確認
- `src/Revclip/project.yml` の `SUPublicEDKey`
- `src/Revclip/Revclip/Info.plist` の `SUPublicEDKey`
- CI で使用している `SPARKLE_PRIVATE_KEY` と対応するか（直接確認は不可だが、ロジックを確認）

### 4. appcast.xml の生成方法確認
- `generate_appcast` に渡しているオプション
- `--ed-key-file` で正しいキーを渡しているか
- `--download-url-prefix` が正しいか

### 5. DMG ファイル名の不一致確認
- appcast.xml 内の `enclosure url` と、実際の GitHub Releases のアセット名が一致するか
- 過去のリリース（v0.0.8 等）の appcast エントリも含まれている可能性

### 6. 実際のリリースアセット確認
```bash
gh release view v0.0.9 --repo sasuketorii/rev-clip
```

## 出力フォーマット

### 根本原因
（原因の詳細説明）

### 該当箇所
（問題のあるファイル・設定・CI ステップ）

### 推奨修正方針
（どう修正すべきかの方針）

### 影響範囲
（この修正が他の機能に与える影響の有無）
