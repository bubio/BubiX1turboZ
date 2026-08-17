## The application's string catalog, and the language it is read in.
##
## Every string the user can read - menu titles, dialog wording, button
## labels - is looked up here rather than written at its use site, so a
## second language is a column in the tables below and nothing else. The
## catalog deliberately lives in Nim rather than in a platform localization
## format (macOS `.strings`, GNU gettext): the AppKit files under this
## directory are one platform's backend and are meant to be joined by GTK
## and Win32 equivalents, and a catalog only one of them can read would have
## to be written three times. The backends therefore take every label they
## draw as a parameter - see filedialog.m and statepicker.m.
##
## Strings carry positional placeholders (`$1`, `$2`) rather than being
## concatenated from fragments, because the order of the pieces is part of
## what differs between languages.
##
## Two rules keep the tables honest:
##
## * The tables are complete arrays indexed by `MsgId`, so a message added
##   without a translation is a compile error rather than a silent fallback.
## * Product names, device names and medium names (PSG, CZ-8BS1, 2HD, FD0)
##   are not in here. They are the same words in every language, and the
##   sound device captions in particular come from the emulation core.

import std/strutils
when not (defined(macosx) or defined(windows)):
  import std/os # only the POSIX branch of systemLanguage reads the environment

type
  Lang* = enum
    ## Languages the UI is written in. `langEn` is also the fallback for a
    ## host whose language is neither.
    langEn, langJa

  MsgId* = enum
    # --- Control menu ---
    msgMenuControl, msgReset, msgNmi, msgCpuPower, msgFullSpeed,
    msgDriveVmInOpecode, msgPaste, msgStopPaste, msgRomajiToKana,
    msgQuickSave, msgQuickLoad, msgSaveStateDots, msgLoadStateDots,
    # --- Disk menu ---
    msgMenuDisk, msgInsertDots, msgEject, msgInsertBlankDisk,
    msgWriteProtected, msgCorrectTiming, msgIgnoreCrcErrors,
    msgRecentFiles, msgRecentNone, msgClearRecentFiles,
    # --- Device menu ---
    msgMenuDevice, msgKeyboard, msgKeyboardModeA, msgKeyboardModeB,
    msgSound, msgPlayFddNoise, msgDisplay, msgHighResolution, msgStandard,
    msgScanline,
    # --- Host menu ---
    msgMenuHost, msgRecSound, msgRecStop, msgCaptureScreen, msgScreen,
    msgWindowScale, msgFullscreen, msgWindowAspect, msgFullscreenDotByDot,
    msgFullscreenStretchAspect, msgFullscreenStretchFill,
    msgRealtimeMix, msgLightWeightMix, msgVolume, msgShowStatusBar,
    msgLanguage, msgLanguageAuto, msgLanguageEnglish, msgLanguageJapanese,
    msgLanguageChangedTitle, msgLanguageChangedBody,
    # --- Volume panel ---
    msgVolumeMaster, msgVolumeLinkLR,
    # --- Buttons shared by the native dialogs ---
    msgButtonOk, msgButtonCancel, msgButtonInsert, msgButtonOpenRomFolder,
    msgButtonQuit,
    # --- The macOS application menu ---
    # macOS expects these six by name, and every platform draws its own
    # equivalent, so they are translated here like any other label rather
    # than left to the toolkit. `$1` is the application's name, which macOS
    # puts in three of them.
    msgAppMenuAbout, msgAppMenuServices, msgAppMenuHide, msgAppMenuHideOthers,
    msgAppMenuShowAll, msgAppMenuQuit,
    # --- About ---
    msgAboutBody,
    # --- Startup ---
    msgBiosMissingTitle, msgBiosMissingBody,
    # --- Disk chooser ---
    msgSelectDiskTitle,
    # --- Save states ---
    msgSaveStateTitle, msgLoadStateTitle, msgSlotCaption, msgSlotEmpty,
    msgStateDateFormat, msgStateCaption,
    msgStateCaptureFailed, msgStateCoreMismatch, msgStateMachineMismatch,
    msgStateIplMismatch, msgStateApplyFailed,
    msgStateSettingMismatch, msgStateSoundBoardMismatch,
    msgSettingPrinter, msgSettingSerial, msgSettingSoundFrequency,
    msgSettingSoundLatency,
    msgStateRestoredWithIssues, msgDiskMissing, msgDiskNotMounted,
    msgDiskChanged,
    # --- What a `.bx1s` file can be rejected for (savestate.nim) ---
    msgStateCannotWrite, msgStateCannotRead, msgStateNotOurs,
    msgStateNewerVersion, msgStateUnknownCompression, msgStateDamagedTable,
    msgStateTruncated, msgStateNoMetadata, msgStateNoMachineState,
    # --- Device settings that need a reset ---
    msgSoundBoardTitle, msgSoundBoardBody,
    # --- Recording and screenshots ---
    msgRecSoundFailed, msgCaptureScreenFailed

const
  EnglishCatalog: array[MsgId, string] = [
    msgMenuControl: "Control",
    msgReset: "Reset",
    msgNmi: "NMI",
    msgCpuPower: "CPU x$1",
    msgFullSpeed: "Full Speed",
    msgDriveVmInOpecode: "Drive VM in M1/R/W Cycle",
    msgPaste: "Paste",
    msgStopPaste: "Stop",
    msgRomajiToKana: "Romaji to Kana",
    msgQuickSave: "Quick Save",
    msgQuickLoad: "Quick Load",
    msgSaveStateDots: "Save State…",
    msgLoadStateDots: "Load State…",

    msgMenuDisk: "Disk",
    msgInsertDots: "Insert…",
    msgEject: "Eject",
    msgInsertBlankDisk: "Insert Blank $1 Disk…",
    msgWriteProtected: "Write Protected",
    msgCorrectTiming: "Correct Timing",
    msgIgnoreCrcErrors: "Ignore CRC Errors",
    msgRecentFiles: "Recent Files",
    msgRecentNone: "None",
    msgClearRecentFiles: "Clear Recent Files",

    msgMenuDevice: "Device",
    msgKeyboard: "Keyboard",
    msgKeyboardModeA: "Keyboard Mode A",
    msgKeyboardModeB: "Keyboard Mode B",
    msgSound: "Sound",
    msgPlayFddNoise: "Play FDD Noise",
    msgDisplay: "Display",
    msgHighResolution: "High Resolution",
    msgStandard: "Standard",
    msgScanline: "Scanline",

    msgMenuHost: "Host",
    msgRecSound: "Rec Sound",
    msgRecStop: "Stop",
    msgCaptureScreen: "Capture Screen",
    msgScreen: "Screen",
    msgWindowScale: "Window x$1",
    msgFullscreen: "Fullscreen",
    msgWindowAspect: "Window: Aspect Ratio $1:$2",
    msgFullscreenDotByDot: "Fullscreen: Dot By Dot",
    msgFullscreenStretchAspect: "Fullscreen: Stretch (Aspect Ratio $1:$2)",
    msgFullscreenStretchFill: "Fullscreen: Stretch (Fill)",
    msgRealtimeMix: "Realtime Mix",
    msgLightWeightMix: "Light Weight Mix",
    msgVolume: "Volume",
    msgShowStatusBar: "Show Status Bar",
    msgLanguage: "Language",
    msgLanguageAuto: "Same as System",
    msgLanguageEnglish: "English",
    msgLanguageJapanese: "日本語",
    msgLanguageChangedTitle: "Language",
    msgLanguageChangedBody:
      "The new language takes effect the next time BubiX1turboZ is opened.",

    msgVolumeMaster: "Master",
    msgVolumeLinkLR: "Link L/R",

    msgButtonOk: "OK",
    msgButtonCancel: "Cancel",
    msgButtonInsert: "Insert",
    msgButtonOpenRomFolder: "Open ROM Folder",
    msgButtonQuit: "Quit",

    msgAppMenuAbout: "About $1",
    msgAppMenuServices: "Services",
    msgAppMenuHide: "Hide $1",
    msgAppMenuHideOthers: "Hide Others",
    msgAppMenuShowAll: "Show All",
    msgAppMenuQuit: "Quit $1",

    msgAboutBody:
      "Multi-platform Sharp X1 turbo Z emulator.\n" &
      "Emulation core: Common Source Code Project's eX1turboZ " &
      "(GPL-2.0-or-later).",

    msgBiosMissingTitle: "BIOS ROM not found",
    msgBiosMissingBody:
      "BubiX1turboZ needs the X1 turbo Z BIOS ROM to start.\n\n" &
      "Put $1 - and the font ROMs FNT0808.X1, FNT0816.X1 and FNT1616.X1 - " &
      "into this folder, then open BubiX1turboZ again:\n\n$2",

    msgSelectDiskTitle: "Select a disk to insert",

    msgSaveStateTitle: "Save State",
    msgLoadStateTitle: "Load State",
    msgSlotCaption: "Slot $1",
    msgSlotEmpty: "Empty",
    # Month and day rather than a full date: a save state is normally
    # recent, and the cell it goes in is one line high.
    msgStateDateFormat: "MM/dd HH:mm",
    msgStateCaption: "$1 — $2", # when it was taken, then what was in it
    msgStateCaptureFailed: "The machine state could not be captured.",
    msgStateCoreMismatch:
      "This save state was written against a different build of the " &
      "emulation core and can no longer be read.",
    msgStateMachineMismatch: "This save state is for a different machine.",
    msgStateIplMismatch:
      "This save state was made with a different IPL ROM. States carry no " &
      "ROM data, so restoring one against another ROM would leave the " &
      "machine in an inconsistent state.",
    msgStateApplyFailed:
      "This save state could not be applied. The machine kept running from " &
      "where it was, but the drives now hold the state's disks.",
    msgStateSettingMismatch:
      "This save state was made with a different $1 setting, which cannot " &
      "be changed while the machine is running.",
    msgStateSoundBoardMismatch:
      "This save state was made with a different sound board, which this " &
      "machine is not running. Pick it again in Device > Sound, reset the " &
      "machine (Control > Reset), then load the state.",
    msgSettingPrinter: "printer",
    msgSettingSerial: "serial",
    msgSettingSoundFrequency: "sound frequency",
    msgSettingSoundLatency: "sound latency",
    msgStateRestoredWithIssues: "The state was restored, but:",
    msgDiskMissing: "$1 is missing.",
    msgDiskNotMounted: "$1 could not be mounted.",
    msgDiskChanged: "$1 has changed on disk.",

    msgStateCannotWrite: "Cannot write $1.",
    msgStateCannotRead: "Cannot read $1.",
    msgStateNotOurs: "$1 is not a BubiX1turboZ save state.",
    msgStateNewerVersion:
      "This save state was written by a newer version of BubiX1turboZ.",
    msgStateUnknownCompression:
      "This save state uses an unknown compression method.",
    msgStateDamagedTable: "This save state has a damaged section table.",
    msgStateTruncated: "This save state is truncated.",
    msgStateNoMetadata: "This save state has no metadata.",
    msgStateNoMachineState: "This save state has no machine state.",

    msgSoundBoardTitle: "Sound Board",
    msgSoundBoardBody:
      "The sound board is chosen while the machine is being built, so this " &
      "takes effect at the next reset (Control > Reset).",

    msgRecSoundFailed: "Could not start recording in $1.",
    msgCaptureScreenFailed: "Could not write a screenshot to $1.",
  ]

  JapaneseCatalog: array[MsgId, string] = [
    msgMenuControl: "コントロール",
    msgReset: "リセット",
    msgNmi: "NMI",
    msgCpuPower: "CPU x$1",
    msgFullSpeed: "最高速で実行",
    msgDriveVmInOpecode: "M1/R/W サイクルで VM を駆動",
    msgPaste: "ペースト",
    msgStopPaste: "ペーストを中止",
    msgRomajiToKana: "ローマ字かな変換",
    msgQuickSave: "クイックセーブ",
    msgQuickLoad: "クイックロード",
    msgSaveStateDots: "ステートを保存…",
    msgLoadStateDots: "ステートを読み込み…",

    msgMenuDisk: "ディスク",
    msgInsertDots: "挿入…",
    msgEject: "取り出し",
    msgInsertBlankDisk: "新規 $1 ディスクを挿入…",
    msgWriteProtected: "書き込み禁止",
    msgCorrectTiming: "アクセスタイミングを補正",
    msgIgnoreCrcErrors: "CRC エラーを無視",
    msgRecentFiles: "最近使った項目",
    msgRecentNone: "なし",
    msgClearRecentFiles: "最近使った項目を消去",

    msgMenuDevice: "デバイス",
    msgKeyboard: "キーボード",
    msgKeyboardModeA: "キーボード モード A",
    msgKeyboardModeB: "キーボード モード B",
    msgSound: "サウンド",
    msgPlayFddNoise: "FDD のシーク音を鳴らす",
    msgDisplay: "ディスプレイ",
    msgHighResolution: "高解像度",
    msgStandard: "標準",
    msgScanline: "走査線",

    msgMenuHost: "ホスト",
    msgRecSound: "サウンドを録音",
    msgRecStop: "録音を停止",
    msgCaptureScreen: "画面を保存",
    msgScreen: "画面",
    msgWindowScale: "ウインドウ x$1",
    msgFullscreen: "フルスクリーン",
    msgWindowAspect: "ウインドウ: アスペクト比 $1:$2",
    msgFullscreenDotByDot: "フルスクリーン: ドットバイドット",
    msgFullscreenStretchAspect: "フルスクリーン: 拡大 (アスペクト比 $1:$2)",
    msgFullscreenStretchFill: "フルスクリーン: 拡大 (画面全体)",
    msgRealtimeMix: "リアルタイムミキシング",
    msgLightWeightMix: "軽量ミキシング",
    msgVolume: "音量",
    msgShowStatusBar: "ステータスバーを表示",
    msgLanguage: "言語",
    msgLanguageAuto: "システムに従う",
    msgLanguageEnglish: "English",
    msgLanguageJapanese: "日本語",
    msgLanguageChangedTitle: "言語",
    msgLanguageChangedBody: "次回 BubiX1turboZ を起動したときに反映されます。",

    msgVolumeMaster: "マスター",
    msgVolumeLinkLR: "L/R を連動",

    msgButtonOk: "OK",
    msgButtonCancel: "キャンセル",
    msgButtonInsert: "挿入",
    msgButtonOpenRomFolder: "ROM フォルダを開く",
    msgButtonQuit: "終了",

    msgAppMenuAbout: "$1 について",
    msgAppMenuServices: "サービス",
    msgAppMenuHide: "$1 を隠す",
    msgAppMenuHideOthers: "ほかを隠す",
    msgAppMenuShowAll: "すべてを表示",
    msgAppMenuQuit: "$1 を終了",

    msgAboutBody:
      "マルチプラットフォーム対応の Sharp X1 turbo Z エミュレーターです。\n" &
      "エミュレーションコア: Common Source Code Project の eX1turboZ " &
      "(GPL-2.0-or-later)。",

    msgBiosMissingTitle: "BIOS ROM が見つかりません",
    msgBiosMissingBody:
      "BubiX1turboZ の起動には X1 turbo Z の BIOS ROM が必要です。\n\n" &
      "$1 とフォント ROM (FNT0808.X1、FNT0816.X1、FNT1616.X1) を次の" &
      "フォルダに入れてから、もう一度 BubiX1turboZ を開いてください:\n\n$2",

    msgSelectDiskTitle: "挿入するディスクを選んでください",

    msgSaveStateTitle: "ステートを保存",
    msgLoadStateTitle: "ステートを読み込み",
    msgSlotCaption: "スロット $1",
    msgSlotEmpty: "空き",
    msgStateDateFormat: "MM/dd HH:mm",
    msgStateCaption: "$1 — $2",
    msgStateCaptureFailed: "マシンの状態を取得できませんでした。",
    msgStateCoreMismatch:
      "このステートは別のビルドのエミュレーションコアで保存されているため、" &
      "読み込むことができません。",
    msgStateMachineMismatch: "このステートは別の機種のものです。",
    msgStateIplMismatch:
      "このステートは別の IPL ROM で保存されています。ステートには ROM の" &
      "データが含まれないため、別の ROM に対して復元するとマシンの状態が" &
      "壊れてしまいます。",
    msgStateApplyFailed:
      "このステートを適用できませんでした。マシンは元の状態のまま動作して" &
      "いますが、ドライブにはステートのディスクが入っています。",
    msgStateSettingMismatch:
      "このステートは $1 の設定が異なる状態で保存されています。この設定は" &
      "マシンの動作中には変更できません。",
    msgStateSoundBoardMismatch:
      "このステートは、このマシンに搭載されていないサウンドボードで保存され" &
      "ています。デバイス > サウンドで選び直し、マシンをリセット " &
      "(コントロール > リセット) してから読み込んでください。",
    msgSettingPrinter: "プリンター",
    msgSettingSerial: "シリアル",
    msgSettingSoundFrequency: "サンプリングレート",
    msgSettingSoundLatency: "サウンドレイテンシー",
    msgStateRestoredWithIssues: "ステートを復元しましたが、次の問題があります:",
    msgDiskMissing: "$1 が見つかりません。",
    msgDiskNotMounted: "$1 をマウントできませんでした。",
    msgDiskChanged: "$1 の内容が変更されています。",

    msgStateCannotWrite: "$1 に書き込めません。",
    msgStateCannotRead: "$1 を読み込めません。",
    msgStateNotOurs: "$1 は BubiX1turboZ のステートファイルではありません。",
    msgStateNewerVersion:
      "このステートは新しいバージョンの BubiX1turboZ で保存されています。",
    msgStateUnknownCompression: "このステートは未知の圧縮形式を使っています。",
    msgStateDamagedTable: "このステートのセクションテーブルが壊れています。",
    msgStateTruncated: "このステートは途中で切れています。",
    msgStateNoMetadata: "このステートにメタデータが含まれていません。",
    msgStateNoMachineState: "このステートにマシンの状態が含まれていません。",

    msgSoundBoardTitle: "サウンドボード",
    msgSoundBoardBody:
      "サウンドボードはマシンの構築時に決まるため、この変更は次回のリセット " &
      "(コントロール > リセット) で反映されます。",

    msgRecSoundFailed: "$1 に録音を開始できませんでした。",
    msgCaptureScreenFailed: "$1 にスクリーンショットを書き出せませんでした。",
  ]

  Catalog: array[Lang, array[MsgId, string]] = [EnglishCatalog, JapaneseCatalog]

when defined(macosx):
  {.compile: "hostlocale.m".}
  {.passL: "-framework Foundation".}
  proc bx1PreferredLanguage(): cstring
    {.importc: "bx1_preferred_language", cdecl.}
    ## The first of the user's preferred languages, as a BCP 47 tag
    ## ("ja-JP"). Read from NSLocale rather than from the environment: a
    ## bundle launched from the Finder inherits no LANG at all, so an
    ## environment-based guess works from a terminal and fails on a
    ## double-click.
elif defined(windows):
  proc getUserDefaultUILanguage(): uint16
    {.importc: "GetUserDefaultUILanguage", stdcall, dynlib: "kernel32".}
  const LangJapanese = 0x11'u16 ## LANG_JAPANESE, the low 10 bits of an LCID.

var current = langEn

proc fromTag(tag: string): Lang =
  ## Maps a language tag ("ja", "ja-JP", "ja_JP.UTF-8") to a catalog. Only
  ## the primary subtag is examined: this app does not distinguish regions.
  let primary = tag.split({'-', '_', '.'})[0].toLowerAscii()
  if primary == "ja": langJa else: langEn

proc systemLanguage(): Lang =
  ## What the host says the user reads. Everything that is not a language
  ## this app has a catalog for reads as English.
  when defined(macosx):
    let tag = bx1PreferredLanguage()
    if tag == nil: langEn else: fromTag($tag)
  elif defined(windows):
    if (getUserDefaultUILanguage() and 0x3ff'u16) == LangJapanese: langJa
    else: langEn
  else:
    # POSIX: the first of these that is set and is not the C locale wins,
    # which is the order gettext itself consults them in.
    for name in ["LC_ALL", "LC_MESSAGES", "LANG"]:
      let value = getEnv(name)
      if value.len > 0 and value != "C" and value != "POSIX":
        return fromTag(value)
    langEn

proc setLanguage*(preference: string) =
  ## Selects the catalog from a stored preference: "en" or "ja" to force
  ## one, anything else (including the default "auto") to follow the host.
  ## Called once at startup - the menu bar is built from the catalog and is
  ## not rebuilt, so switching later would leave the UI half translated.
  current =
    case preference.toLowerAscii()
    of "en": langEn
    of "ja": langJa
    else: systemLanguage()

proc language*(): Lang = current

proc tr*(id: MsgId): string =
  ## The message in the selected language.
  Catalog[current][id]

proc trf*(id: MsgId, args: varargs[string, `$`]): string =
  ## The message with its `$1`/`$2` placeholders filled in, in the order the
  ## selected language puts them.
  Catalog[current][id] % @args
