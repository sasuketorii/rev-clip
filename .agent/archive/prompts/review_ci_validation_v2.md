# 再レビュー依頼: CI appcast 署名バリデーション（修正版）

## AGENT_ROLE=reviewer

前回のレビューで指摘された grep の強化修正を確認してください。

## 前回の指摘
`grep -q 'sparkle:edSignature'` では空値でもパスする。
non-empty な署名属性を検証するよう `grep -Eq 'sparkle:edSignature="[^"]+"'` に変更を要求。

## 変更ファイル
`.github/workflows/release.yml`

## 修正後の差分

```diff
+      - name: Validate appcast.xml contains EdDSA signature
+        run: |
+          set -euo pipefail
+          if [[ ! -f "${APPCAST_PATH}" ]]; then
+            echo "appcast.xml not found: ${APPCAST_PATH}"
+            exit 1
+          fi
+
+          if ! grep -Eq 'sparkle:edSignature="[^"]+"' "${APPCAST_PATH}"; then
+            echo "ERROR: appcast.xml does not contain a non-empty sparkle:edSignature."
+            echo "This means the Sparkle EdDSA signing failed silently."
+            echo "Check that SPARKLE_PRIVATE_KEY matches the SUPublicEDKey in the app."
+            cat "${APPCAST_PATH}"
+            exit 1
+          fi
+
+          echo "appcast.xml validation passed: EdDSA signature found."
```

## レビュー観点
1. 前回指摘の修正が適切に反映されているか
2. `grep -Eq 'sparkle:edSignature="[^"]+"'` で non-empty 署名を正しく検出できるか

## レビューのフォーマット
- 問題がなければ「LGTM」と明記してください
