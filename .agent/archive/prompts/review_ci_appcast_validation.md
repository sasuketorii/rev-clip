# レビュー依頼: CI appcast 署名バリデーション追加

## AGENT_ROLE=reviewer

あなたはコードレビュワーです。以下の変更をレビューしてください。

## 変更概要
Sparkle アップデートの署名エラー（appcast.xml に EdDSA 署名が含まれない問題）の再発防止。
CI ワークフローに appcast.xml のバリデーションステップを追加。

## 変更ファイル
`.github/workflows/release.yml`

## 変更内容（diff）

```diff
@@ -268,6 +268,24 @@ jobs:

           echo "APPCAST_PATH=${APPCAST_PATH}" >> "${GITHUB_ENV}"

+      - name: Validate appcast.xml contains EdDSA signature
+        run: |
+          set -euo pipefail
+          if [[ ! -f "${APPCAST_PATH}" ]]; then
+            echo "appcast.xml not found: ${APPCAST_PATH}"
+            exit 1
+          fi
+
+          if ! grep -q 'sparkle:edSignature' "${APPCAST_PATH}"; then
+            echo "ERROR: appcast.xml does not contain sparkle:edSignature."
+            echo "This means the Sparkle EdDSA signing failed silently."
+            echo "Check that SPARKLE_PRIVATE_KEY matches the SUPublicEDKey in the app."
+            cat "${APPCAST_PATH}"
+            exit 1
+          fi
+
+          echo "appcast.xml validation passed: EdDSA signature found."
+
       - name: Publish GitHub Release with assets
```

## レビュー観点
1. **正確性**: `grep -q 'sparkle:edSignature'` で署名の有無を正しく検出できるか？
2. **位置**: "Generate appcast.xml" と "Publish GitHub Release" の間の配置は正しいか？
3. **エラーメッセージ**: デバッグに十分な情報を出力しているか？
4. **堅牢性**: edge case（空ファイル、不完全な XML 等）に対応しているか？

## レビューのフォーマット
- 問題があれば具体的に指摘してください
- 問題がなければ「LGTM」と明記してください
