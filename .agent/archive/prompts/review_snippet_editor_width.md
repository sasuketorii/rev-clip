# レビュー依頼: スニペットエディタの内容テキストエリア幅修正

## AGENT_ROLE=reviewer

あなたはコードレビュワーです。以下の変更をレビューしてください。

## 変更概要
スニペットエディタの「内容」テキストエリア（NSTextView）が横幅いっぱいに広がらず、左端に狭く詰められるバグの修正。

## 変更ファイル
`src/Revclip/Revclip/UI/SnippetEditor/RCSnippetEditorWindowController.m`

## 変更内容（diff）

```diff
@@ -276,6 +276,7 @@
     self.contentTextView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
     self.contentTextView.verticallyResizable = YES;
     self.contentTextView.horizontallyResizable = NO;
+    self.contentTextView.autoresizingMask = NSViewWidthSizable;
     self.contentTextView.usesFindBar = YES;
     self.contentTextView.richText = NO;
     self.contentTextView.allowsUndo = YES;
@@ -285,7 +286,7 @@
     self.contentScrollView.hasVerticalScroller = YES;
     self.contentScrollView.hasHorizontalScroller = NO;
     self.contentScrollView.borderType = NSBezelBorder;
-    self.contentTextView.textContainer.containerSize = NSMakeSize(0.0, CGFLOAT_MAX);
+    self.contentTextView.textContainer.containerSize = NSMakeSize(FLT_MAX, CGFLOAT_MAX);
     self.contentTextView.textContainer.widthTracksTextView = YES;
     self.contentScrollView.documentView = self.contentTextView;
     [rightPane addSubview:self.contentScrollView];
```

## レビュー観点
1. **正確性**: NSTextView + NSScrollView + Auto Layout の組み合わせで `autoresizingMask = NSViewWidthSizable` は正しいか？
2. **安全性**: `FLT_MAX` を初期コンテナ幅に使うことに問題はないか？`widthTracksTextView = YES` との組み合わせで期待どおり動作するか？
3. **副作用**: この変更が他のUI要素（タイトルフィールド、ショートカット設定など）に影響を与えないか？
4. **Appleのベストプラクティス**: NSTextView を NSScrollView 内で使う場合の標準パターンに準拠しているか？

## レビューのフォーマット
- 問題があれば具体的に指摘してください
- 問題がなければ「LGTM」と明記してください
- 各観点について簡潔に判定を記載してください

## レビューに必要なコンテキスト
変更箇所周辺のコードを実際のファイルから読み取って確認してください:
`src/Revclip/Revclip/UI/SnippetEditor/RCSnippetEditorWindowController.m` の `buildEditorInRightPane:` メソッド全体（256行〜337行）
