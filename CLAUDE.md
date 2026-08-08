# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## リポジトリの現状

**フェーズ 7（アーカイブ・ドラッグ＆ドロップ対応）まで完了。次はフェーズ 8（実ゲームによる検証）。** `src/`・`.nimble` とも存在し、ビルドは以下のスクリプトで行う:

- `scripts/build_core.sh [vm|app|osd|bridge|all]` — 静的ライブラリ `build/libbubix1core.a`（vendored C++ コア + OSD + bridge）をビルド
- `scripts/build_app_macos_dev.sh` — `build/libbubix1core.a` を前提に Nim アプリを `build/BubiX1turboZ` としてビルド（開発用。フェーズ 9 の `.app`/`.dmg` パッケージングはまだ無い）

現時点の構成:

| パス | 追跡 | 内容 |
|---|---|---|
| `CLAUDE.md`, `mise.toml`, `.gitignore`, `LICENSE`/`license/`, `README.md`, `*.nimble`, `src/`, `scripts/`, `docs/`（`docs/dev/` を除く） | ✅ | |
| `docs/dev/` | ❌ | `BluePrint.md`（仕様）と `DevelopmentPlan.md`（計画・進捗・調査結果の一次資料） |
| `spike/` | ❌ | フェーズ 1 の検証コードと成果物（`src/` へ移設済みのものも含め、参照用にそのまま残置） |

各フェーズで確定した設計判断・不具合と対処・申し送り事項は `docs/dev/DevelopmentPlan.md` に集約されている。**作業前に必ずこれを読み、同じ調査や設計判断をやり直さないこと。**

作業前に必ず以下の 2 つを読んでください。

1. **`docs/dev/BluePrint.md`** — 唯一の仕様の源泉。
2. **`docs/dev/DevelopmentPlan.md`** — 実装計画とフェーズ別チェックリスト。オリジナルコードの調査結果（レイヤーごとの OS 依存度、実装必須の OSD API 一覧、既知の移植ブロッカー）が確定事項として記録済みです。**同じ調査を繰り返さないでください。**

以下はその要点と、外部リポジトリを読まないと分からない補足です。

## プロジェクト概要

Sharp X1 turbo Z のマルチプラットフォーム対応エミュレーター。

- **エミュレーションコア**: Common Source Code Project の eX1turboZ のコードをそのまま使用（C++）
- **アプリケーション層**: Nim
- **マルチメディア**: SDL2
- **GUI**: uing (https://github.com/neroist/uing)
- **ライセンス**: eX1turboZ と同じ

つまり構造は「C++ のエミュレーションコア + Nim のアプリケーション層」の二層で、両者を FFI で接続する形になります。コアには手を入れず、上位層で吸収するのが基本方針です。

対応プラットフォーム（優先順）:

1. macOS Intel / Apple シリコン — macOS 13.5 以降
2. Linux amd64 / arm64 — Ubuntu 22.04 以降
3. Windows x86_64 — Windows 11 以降

## 参照先

- eX1turboZ のオリジナルコード: `~/dev/_Emu/Original/common_source_project`
- BIOS・市販ゲーム: `/Volumes/CrucialX6/roms/Sharp X1`
- アーカイブ展開仕様の参考実装: `~/dev/_Emu/Bubilator88`
- CI/CD の参考実装: `~/dev/_Emu/M88M`

## 設計上の判断基準

- **eX1turboZ 準拠だが、機能は削る**。eX1turboZ は他エミュレーターとの共通化のため過剰な部分がある。市販ゲームの実行に不要な機能（FDD 4 基、HDD など）は実装しない。移植時は「これは市販ゲームに必要か」で取捨選択する。
- **ファイル配置はプラットフォームの流儀に従う**。BIOS・ステートファイル・設定ファイルを実行ファイルと同じ場所に置くのは NG。macOS なら `~/Library/Application Support/...`、Linux なら XDG、Windows なら `%APPDATA%` 相当。
- **UI もプラットフォームの体験を壊さない**こと。
- **アーカイブ対応**: 7z / zip / m3u / m3u8 を読み込める。7z・zip は設定ファイルと同じフォルダに展開し、以後は展開済みのものを使う（Bubilator88 と同じ仕様）。
- **ドラッグ＆ドロップ**でも対応フォーマットをマウントし、自動リセットで起動する。

## コーディング規約

- **コメントは英語で、丁寧かつ簡潔に**書く。日本語コメントは不可。
- コメントのフォーマットは **`nim doc` でドキュメント生成可能な形式**にする。
- ドキュメントにもコードにも**実ユーザー名を書かない**。ユーザーフォルダは `~` で表現する（このファイル自身も含む）。

## バージョニング

セマンティックバージョニング。ビルド番号を別に持つ場合は 1 からの連番。

## Git 運用

- **コミット・プッシュは指示があるまで行わない。**
- `docs/dev/` 配下の開発途中の技術ドキュメント（`BluePrint.md` を含む）は **Git の追跡対象外**にする。
- ユーザー向けの操作マニュアルは `docs/` 直下に作成し、追跡対象にする。

## CI/CD

M88M (`~/dev/_Emu/M88M/.github/workflows/`) の構成に倣う。確認済みの規約:

- ワークフローは**プラットフォーム／アーキテクチャ単位でファイルを分ける** (`build-macos.yml`, `build-linux.yml`, `build-windows.yml`)。
- 各ワークフローは `push` / `pull_request` の両方に `paths:` フィルタを付け、**他プラットフォームの yml 変更やドキュメント変更では起動しないようにする**。フィルタにはソース、ビルドスクリプト、自身の yml、共通の publish 用 yml のみを列挙する。
- `concurrency` で `${{ github.workflow }}-${{ github.ref }}` をグループ化し、`cancel-in-progress` は release イベント以外で有効にする。
- リリース資産のアップロードは共通の再利用可能ワークフロー `publish-release-assets.yml` に `workflow_call` で委譲し、`asset-patterns` に拡張子グロブ（`*.dmg`, `*.deb`, `*.AppImage` など）を渡す。
- アーティファクト名は小文字ケバブケースで `<product>-<platform>-<arch>-<format>` 形式（例: `m88m-linux-arm64-deb`）。
- バージョンはビルド設定ファイルから抽出して release 名に使う。

## 開発の進め方

まだ何も無い状態なので、最初の作業は「何を実行するか」ではなく「何を作るか」になります。スキャフォールドを行う際は、上記の制約（ファイル配置、機能の削減方針、コメント規約、CI の分割方針）を最初から満たす形で作ってください。後付けが効きにくい制約です。
