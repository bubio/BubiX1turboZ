# BubiX1turboZ

<p align="center">
  <img src="docs/AppIcon.png" alt="BubiX1turboZ" width="128" height="128">
</p>

BubiX1turboZ は、[Common Source Code Project](https://takeda-toshiya.my.coocan.jp/common/index.html) の `eX1turboZ` をベースにした Sharp X1 turbo Z エミュレーターのマルチプラットフォーム移植版です。

<p align="center">
  <a href="https://github.com/bubio/BubiX1turboZ/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/bubio/BubiX1turboZ" alt="License">
  </a>
  <a href="https://github.com/bubio/BubiX1turboZ/actions/workflows/build-macos.yml">
    <img src="https://github.com/bubio/BubiX1turboZ/actions/workflows/build-macos.yml/badge.svg" alt="macOS">
  </a>
  <a href="https://github.com/bubio/BubiX1turboZ/actions/workflows/check-portability.yml">
    <img src="https://github.com/bubio/BubiX1turboZ/actions/workflows/check-portability.yml/badge.svg" alt="Portability">
  </a>
</p>

エミュレーションコアは C++ のまま手を入れず、その上のアプリケーション層を [Nim](https://nim-lang.org/) で書き起こしています。

## About

- **C++ コア + Nim アプリケーション層の二層構成**
  eX1turboZ のコアはそのまま使い、OS 依存の処理はすべて上位層で吸収しています。
- **GUI はプラットフォームのネイティブ API**
  メニューバー・ダイアログ・設定パネルは macOS では AppKit を直接使います。クロスプラットフォームの GUI ツールキットは使いません。
- **メディア操作が速い**
  `D88` などのディスクイメージを、メニュー・ドラッグ&ドロップのどちらからでも読み込めます。ドロップした場合は自動でリセットして起動します。
- **アーカイブをそのまま開ける**
  `7z` / `zip` / `m3u` / `m3u8` を、生のディスクイメージと同じ操作で開けます。書庫は一度だけ展開され、以後は展開済みのものが使われます。
- **D88 の複数イメージ管理に対応**
  1 つの `D88` に複数バンクが入っている場合はピッカーで一覧し、FD0 / FD1 に割り当てできます。
- **ステートセーブ**
  クイックセーブ / クイックロードと、サムネイル付きのスロット選択に対応しています。
- **ファイル配置は OS の流儀どおり**
  ROM・設定・ステートは `Application Support`（Linux は XDG、Windows は `%LOCALAPPDATA%`）に置き、録音は `~/Music`、スクリーンショットは `~/Pictures` に保存します。実行ファイルと同じ場所には何も書き込みません。
- **日本語 / 英語表示**
  既定ではシステムの言語設定に従い、`Host -> Language` で明示的に選ぶこともできます。

## Features

- ディスクイメージ（`d88` / `d77` / `d8e` / `1dd` / `2d`）の挿入・イジェクト
- アーカイブ・プレイリスト（`7z` / `zip` / `m3u` / `m3u8`）の読み込み
- メディアファイルのドラッグ&ドロップと自動リセット
- ブランクディスクの作成、ライトプロテクト、展開済みディスクの書き出し
- `Recent Files`
- クイックセーブ / クイックロード、スロット指定のステートセーブ
- CPU クロック倍率、`Full Speed`、`NMI`、リセット
- テキストの貼り付け（オートキー）、ローマ字かな変換
- キーボードモード、音源ボード、FDD ノイズ、走査線などのデバイス設定
- 画面倍率、アスペクト比、フルスクリーンのストレッチ方法、フィルタの切り替え
- `Rec Sound`（WAV 録音）、`Capture Screen`（PNG 保存）
- 音量パネル、ステータスバー
- 日本語 / 英語の UI

## System Requirements

### macOS

- macOS 13.5 (Ventura) 以降
- Apple シリコン (arm64)

Linux (Ubuntu 22.04 以降 / amd64・arm64) と Windows 11 (x86_64) は移植先として設計に織り込んであり、CI でも `nim check` によるコンパイル検査を行っていますが、**現時点でバイナリを提供しているのは macOS の Apple シリコン版のみ**です。Intel Mac 向けとユニバーサルバイナリも今後の対応です。

## Install

[Releases](https://github.com/bubio/BubiX1turboZ/releases) ページから dmg をダウンロードし、`BubiX1turboZ.app` を `Applications` にドラッグしてください。

### CI 生成物一覧

| OS | CI Artifact 名 | Release Asset 名 |
|---|---|---|
| macOS (arm64) | `bubix1turboz-macos-arm64.zip` | `bubix1turboz-{version}-macos-arm64.dmg` |

> **macOS での注意**: このアプリは Apple Developer ID による署名・公証（notarization）を受けていないため、初回起動時に Gatekeeper によってブロックされます。以下のいずれかの方法で回避できます：
>
> **方法1: ターミナルで隔離フラグを削除**
> ```bash
> xattr -dr com.apple.quarantine /Applications/BubiX1turboZ.app
> ```
>
> **方法2: システム設定から許可**
> 1. アプリを開こうとしてブロックされた後
> 2. 「システム設定」→「プライバシーとセキュリティ」を開く
> 3. 「"BubiX1turboZ"は開発元を確認できないため、使用がブロックされました」の横にある「このまま開く」をクリック
>
> いずれも初回のみの操作です。

## 使い始める前に

`BubiX1turboZ` には ROM イメージは含まれていません。ROM 一式を次の場所に置いてください（フォルダは初回起動時に作成されます）。

| OS | ROM 配置先 |
|---|---|
| macOS | `~/Library/Application Support/BubiX1turboZ/roms/` |
| Windows | `%LOCALAPPDATA%\BubiX1turboZ\roms\` |
| Linux | `~/.local/share/BubiX1turboZ/roms/` |

必要なファイル名:

- `IPLROM.X1T`
- `FNT0808.X1`
- `FNT0816.X1`
- `FNT1616.X1`

ROM が入っていない状態で起動すると、置き場所を知らせるダイアログが表示されます。「ROM フォルダを開く」を押すとそのフォルダが Finder で開きます。

設定ファイルとステートセーブも同じフォルダ以下に保存されます。

## 基本操作

- `Disk -> FD0 / FD1 -> Insert...` でディスクを開けます。
- ディスクイメージやアーカイブをウィンドウへドラッグ&ドロップしても読み込めます（自動でリセットがかかります）。
- `Disk -> FD0 & FD1 -> Insert...` で 2 ドライブ分をまとめて挿入できます。
- `Device` メニューからキーボードモード、音源ボード、画面設定を変更できます。
- `Host -> Screen` でウィンドウ倍率・アスペクト比・フルスクリーンの表示方法を切り替えられます。
- `Host -> Volume` で各音源のバランスを調整できます。

よく使うショートカット:

- `Cmd+R`: リセット
- `Cmd+V`: テキストの貼り付け（オートキー）
- `Cmd+S` / `Cmd+L`: クイックセーブ / クイックロード
- `Cmd+3`: FD0 & FD1 にまとめて挿入
- `Cmd+Ctrl+F`: フルスクリーン切り替え

## ソースからビルドする

### 必要なもの

- macOS 13.5 以降
- Xcode Command Line Tools
- [mise](https://mise.jdx.dev/)（Nim ツールチェーンのバージョン固定に使用）

SDL2 は公式配布の `SDL2.framework` をビルド時に自動取得するため、Homebrew の SDL は不要です。Xcode 本体があればアプリ独自のアクセントカラーも埋め込まれます（`actool` を使うため。無い場合はシステムのアクセントカラーになります）。

### macOS

```sh
# Nim ツールチェーン（バージョンは mise.toml で固定）
mise plugins install nim https://github.com/asdf-community/asdf-nim
mise install
mise exec -- nimble install -d -y

# .app バンドルと dmg
./scripts/build_macos.sh --dmg
```

`build/BubiX1turboZ.app` と `build/bubix1turboz-<version>-macos-arm64.dmg` が生成されます。

アプリ本体だけを繰り返しビルドする場合は、C++ コアをビルドしたあとに開発用スクリプトを使うほうが高速です。

```sh
./scripts/build_core.sh all
./scripts/build_app_macos_dev.sh
```

## 現在の注意点

- ROM イメージは同梱していません。
- 提供しているビルドは macOS (Apple シリコン) 版のみです。Linux / Windows 版は未提供です。
- CMT（テープ）には対応していません。UI からの到達経路を塞いでいます。
- 市販ゲームの実行に不要な機能は意図的に実装していません（FDD は 2 基、HDD 非対応など）。
- 実ゲームによる動作検証と、ユーザー向け操作マニュアル（`docs/UserManual.md`）は作業中です。
- オリジナルの eX1turboZ と完全に同一の挙動を保証するものではありません。

## クレジット

- Original eX1turboZ by Takeda, Toshiya ([Common Source Code Project](https://takeda-toshiya.my.coocan.jp/common/index.html))
- macOS / Nim + SDL2 port maintained by bubio

## ライセンス

エミュレーションコアの由来である eX1turboZ と同じ [GNU General Public License v2 (or later)](LICENSE) です。

### サードパーティ

本プロジェクトは以下のサードパーティソフトウェアを利用しています。

| ライブラリ | ライセンス | 用途 |
|---|---|---|
| [eX1turboZ (Common Source Code Project)](https://takeda-toshiya.my.coocan.jp/common/index.html) | GPL-2.0-or-later | エミュレーションコア |
| [SDL2](https://github.com/libsdl-org/SDL) | zlib License | ウィンドウ、入力、オーディオ、レンダリング |
| zlib | zlib License | ステートセーブの圧縮と PNG 出力（OS 同梱の libz を使用） |
| bsdtar (libarchive) | 3-clause BSD License | `7z` / `zip` の展開（OS 同梱の `/usr/bin/tar` を使用） |

`SDL2.framework` はビルド時に公式配布物を取得し、`.app` バンドルへ同梱します。zlib と bsdtar は OS が提供するものをそのまま利用しており、再配布は行っていません。
