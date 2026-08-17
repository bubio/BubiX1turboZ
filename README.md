# BubiX1turboZ

Sharp X1 turbo Z のマルチプラットフォーム対応エミュレーターです。

- エミュレーションコアには [Common Source Code Project](https://takeda-toshiya.my.coocan.jp/common/index.html) の eX1turboZ をそのまま使用しています。
- アプリケーション層は [Nim](https://nim-lang.org/) で実装しています。
- マルチメディアには SDL2 を使用しています。GUI（メニューバー・ダイアログ・設定パネル）は各プラットフォームのネイティブ API で実装しています。

## 対応プラットフォーム

優先順位順:

1. macOS Intel / Apple シリコン — macOS 13.5 以降
2. Linux amd64 / arm64 — Ubuntu 22.04 以降
3. Windows x86_64 — Windows 11 以降

現在提供しているビルドは macOS（Apple シリコン / arm64）のみです。Intel 版・ユニバーサルバイナリは今後の対応です。

## ステータス

開発中です。操作方法や設定項目は `docs/UserManual.md` に記載予定です。

## インストール

1. リリースページから `bubix1turboz-<バージョン>-macos-arm64.dmg` をダウンロードして開きます。
2. `BubiX1turboZ.app` を `Applications` にドラッグします。

### 初回起動

配布物には Apple Developer ID による署名・公証（notarization）を行っていません。そのため初回起動時に「開発元を検証できないため開けません」と表示されます。次のいずれかの方法で許可してください。

- **Finder から**: アプリを一度ダブルクリックして拒否されたあと、「システム設定」→「プライバシーとセキュリティ」を開き、下部に表示される `BubiX1turboZ` の「このまま開く」を選びます。
- **ターミナルから**: 隔離属性を取り除きます。

  ```sh
  xattr -dr com.apple.quarantine /Applications/BubiX1turboZ.app
  ```

いずれも初回のみの操作です。

### ROM の配置

BIOS・フォント ROM は次の場所に置いてください（初回起動時に作成されます）。

```
~/Library/Application Support/BubiX1turboZ/roms/
```

設定・ステートセーブも同じフォルダ以下に保存されます。実行ファイルと同じ場所には何も書き込みません。

ROM が入っていない状態で起動すると、置き場所を知らせるダイアログが表示されます。「ROM フォルダを開く」を押すとそのフォルダが Finder で開きます。

### 表示言語

日本語と英語に対応しています。既定ではシステムの言語設定に従います。「ホスト」→「言語」で明示的に選ぶこともできます（メニューは起動時に組み立てられるため、変更は次回起動時に反映されます）。

## ソースからのビルド（macOS）

必要なもの: Xcode Command Line Tools、[mise](https://mise.jdx.dev/)。SDL2 は公式配布の framework をビルド時に自動取得するため、Homebrew の SDL は不要です。Xcode 本体があればアプリ独自のアクセントカラーも埋め込まれます（`actool` を使うため。無い場合はシステムのアクセントカラーになります）。

```sh
# Nim ツールチェーン（バージョンは mise.toml で固定）
mise plugins install nim https://github.com/asdf-community/asdf-nim
mise install
mise exec -- nimble install -d -y

# .app バンドルと dmg
./scripts/build_macos.sh --dmg
```

`build/BubiX1turboZ.app` と `build/bubix1turboz-<バージョン>-macos-arm64.dmg` ができます。アプリ本体だけを繰り返しビルドする場合は `./scripts/build_core.sh` の後に `./scripts/build_app_macos_dev.sh` を使うほうが高速です。

## ライセンス

eX1turboZ と同じ [GNU General Public License v2 (or later)](LICENSE) です。
