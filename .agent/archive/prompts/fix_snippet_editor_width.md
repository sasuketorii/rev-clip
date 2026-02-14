# タスク: スニペットエディタの内容テキストエリア幅修正

## 許可事項
ユーザーからの明示的許可: メインブランチで作業してOKです。Worktree/ブランチを切る必要はありません。

## バグ概要
スニペットエディタ（`RCSnippetEditorWindow`）の「内容」テキストエリア（NSTextView）が、スクロールビューの幅いっぱいに広がらず、左端に狭く詰められている。テキストが非常に狭い幅で折り返されてしまう。

## 対象ファイル
`src/Revclip/Revclip/UI/SnippetEditor/RCSnippetEditorWindowController.m`

## 根本原因
`buildEditorInRightPane:` メソッド（256行目〜）で、NSTextView の設定に問題がある:

1. **288行目**: `self.contentTextView.textContainer.containerSize = NSMakeSize(0.0, CGFLOAT_MAX);`
   - テキストコンテナの幅が **0.0** に設定されている
2. **289行目**: `self.contentTextView.textContainer.widthTracksTextView = YES;` は設定されているが、テキストビュー自体がスクロールビューに追従してリサイズされない
3. **欠落**: `self.contentTextView.autoresizingMask = NSViewWidthSizable;` が設定されていない。これがないと NSTextView は NSScrollView のリサイズに追従しない

## 修正内容

以下の2点を修正すること:

1. **273行目付近**（NSTextView作成直後、278行目の `horizontallyResizable` 設定の後あたり）に以下を追加:
```objc
self.contentTextView.autoresizingMask = NSViewWidthSizable;
```

2. **288行目**のコンテナサイズ幅を `0.0` から `FLT_MAX` に変更:
```objc
self.contentTextView.textContainer.containerSize = NSMakeSize(FLT_MAX, CGFLOAT_MAX);
```

これにより:
- `autoresizingMask = NSViewWidthSizable` で、NSTextView が NSScrollView のコンテンツ領域幅に追従してリサイズされる
- `widthTracksTextView = YES` で、テキストコンテナがテキストビューの幅に追従する
- テキストコンテナの初期幅が十分に大きいため、レイアウト完了前でもテキストが狭く折り返されない

## 制約
- このファイル（`RCSnippetEditorWindowController.m`）のみを編集すること
- `buildEditorInRightPane:` メソッド内の修正のみ
- 他のメソッドや機能に影響を与えないこと
- コメントの追加は不要
