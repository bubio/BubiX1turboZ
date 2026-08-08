# BubiX1turboZ

Sharp X1 turbo Z のマルチプラットフォーム対応エミュレーターです。

- エミュレーションコアには [Common Source Code Project](https://takeda-toshiya.my.coocan.jp/common/index.html) の eX1turboZ をそのまま使用しています。
- アプリケーション層は [Nim](https://nim-lang.org/) で実装しています。
- マルチメディアには SDL2、GUI には [uing](https://github.com/neroist/uing) を使用しています。

## 対応プラットフォーム

優先順位順:

1. macOS Intel / Apple シリコン — macOS 13.5 以降
2. Linux amd64 / arm64 — Ubuntu 22.04 以降
3. Windows x86_64 — Windows 11 以降

現在 macOS 版の実装を進めています。

## ステータス

開発中です。ビルド手順は整い次第 `docs/UserManual.md` に記載します。

## ライセンス

eX1turboZ と同じ [GNU General Public License v2 (or later)](LICENSE) です。
