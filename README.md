# SpritePacker

画像をcocos2d-x用のテクスチャアトラス（TextureAtlas）にまとめ、ASTCテクスチャに変換するCLIツール。
スプライトフレーム（SpriteFrame）を簡単に生成できます。

## Requirements

- macOS 26
- Swift 6.3
- astcenc
    - https://github.com/ARM-software/astc-encoder/releases からダウンロードしてPATHを通しておく。

## 設定

入力ディレクトリ直下に`sprite.json`を置きます。
`atlases`のキーは1つのアトラスにまとめる画像群のサブディレクトリ名、
`images`のキーは単体変換する画像ファイル名です。
値は`astcenc`のブロックサイズです。

例えば以下のようなリソースディレクトリを作成した場合。

```
Resources
├─ ui
│  ├─ menu.png
│  ├─ close.png
│  └─ ...
├─ characters
│  ├─ player-motion1.png
│  ├─ player-motion2.png
│  └─ ...
├─ background.png
├─ logo.png
└─ sprite.json
```

設定ファイルはこのようになります。

```json
{
  "atlases": {
    "ui": "4x4",
    "characters": "6x6"
  },
  "images": {
    "background.png": "8x8",
    "logo.png": "4x4"
  }
}
```

設定にないディレクトリや画像は処理されません。
アトラスが対応する画像ソースは`NSImage`が読み込めるフォーマットに準拠します。
フレーム名は拡張子を含む元のファイル名です。
単体画像は元ファイルをそのまま `astcenc` に渡します。

## ビルドと実行

```sh
swift build -c release
.build/release/SpritePacker ./sprites
.build/release/SpritePacker -o ./generated ./sprites
.build/release/SpritePacker --mode preview ./sprites
.build/release/SpritePacker --filter characters ./sprites
```

出力先を省略すると `<input>/output` を使います。
アトラスごとにテクスチャとcocos2d-xフォーマットの`.plist` を生成します。

`--mode`（短縮形 `-m`）を省略すると `release` になります。

`--filter`を指定すると、`sprite.json`の`atlases`または`images`のキーに
指定文字列を含むリソースだけを変換します。判定では大文字と小文字を区別します。

| モード | `astcenc` 品質設定 | 出力 | 用途 |
| --- | --- | --- | --- |
| `preview` | `-fast` | `.astc` | 開発中の高速な確認 |
| `release` | `-exhaustive` | `.astc.ccz` | リリース用の高品質圧縮 |

releaseモードではASTC生成後、cocos2d-x専用フォーマットであるCCZに圧縮します。

## 細かい仕様

アトラス画像は各スプライト外周の完全透明ピクセルを自動的に取り除いてからパッキングします。

線形フィルタリングやASTCブロック圧縮による黒い縁を防ぐため、各スプライトの
端ピクセルをフレーム外へ1px複製します。このedge extrusion領域はplistの
`frame` には含まれず、既存の2px画像間隔内に描画されます。

アトラス解像度は2の累乗に制限しません。最初に収容可能なサイズを求めたあと、
段階的に幅・高さと縦横比を再探索し、最後に配置が使用している境界までキャンバスを
切り詰めます。

ASTCはcocos2d-xのテクスチャ座標系に合わせるため、`astcenc`の`-yflip`オプションを付けて生成します。
plistの各フレームY座標も反転後の位置へ変換するため、利用側でスプライトを上下反転する必要はありません。
