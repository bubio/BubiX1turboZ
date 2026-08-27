# BubiX1turboZ User Manual

*[日本語版](UserManual.md)*

A guide to using BubiX1turboZ, a multi-platform emulator for the Sharp X1 turbo Z. Covers installation, common first-run snags, what each menu item does, and supported formats.

## Installation

Download the file matching your platform from the [releases page](https://github.com/bubio/BubiX1turboZ/releases/latest).

| Platform | Executable |
| --- | --- |
| macOS (Apple Silicon) | DMG |
| Linux (amd64 / arm64) | AppImage / `.deb` / `.rpm` |
| Windows (x86_64) | ZIP |

### Reading archives (7z / zip) on Linux

To open `.7z` / `.zip` disk images or archives, either `bsdtar` (the `libarchive-tools` package) or `7-Zip` (the `p7zip-full` package) must be installed on the system. Without one of these, opening such a file shows an alert and fails. macOS and Windows need no extra install - the required library ships with the app.

```shell
sudo apt install libarchive-tools
# or
sudo apt install p7zip-full
```

## ROM files

Booting requires BIOS ROM files from an actual Sharp X1 turbo Z (not included with this app - you must provide your own).

- `IPLROM.X1T` (required - without it, an alert appears at startup and the app quits)
- `FNT0808.X1`
- `FNT0816.X1`
- `FNT1616.X1`

Without the font ROMs, the app falls back to a built-in substitute font, which looks different from the real hardware's font. Without `SUBROM` / `KBDROM`, the app keeps running in a pseudo sub-CPU mode.

### Where to put them

The folder is created automatically the first time you launch the app. Nothing is ever placed next to the executable itself.

| Platform | ROM folder |
| --- | --- |
| macOS | `~/Library/Application Support/BubiX1turboZ/roms/` |
| Linux | `~/.local/share/BubiX1turboZ/roms/` |
| Windows | `%LOCALAPPDATA%\BubiX1turboZ\roms\` |

The same base directory also holds:

- `states/` - quick-save and save-state files
- `extracted/` - disk images extracted from `.7z` / `.zip` archives

When the ROM-missing alert appears, its "Open ROM Folder" button opens this `roms/` folder directly.

## Inserting disk images

Use the `Disk -> FD0 / FD1` menu, or drag and drop onto the window, to insert any of the following:

- Disk images: `d88` / `d77` / `d8e` / `1dd` / `2d`
- Archives: `7z` / `zip`
- Playlists: `m3u` / `m3u8` (registers multiple disks together and switches between them as the game requests a disk change)

Inserting by drag and drop automatically triggers a reset and boots straight in.

### About extracting 7z / zip archives

`.7z` / `.zip` archives are extracted into the `extracted/` folder on insertion, and the extracted files are reused after that (extraction happens only once). **Any save data a game writes to that disk ends up inside this `extracted/` folder - i.e. in storage private to the app.** You can delete or move the original archive file and still play the game, but be careful if you want to take just the save data elsewhere.

The `Disk` menu's "Export Extracted Disks…" writes out every disk extracted so far to a folder of your choice. Use it before tidying up your archives, or when you want to move save data to another machine.

## Keyboard shortcuts

| Key | Action |
| --- | --- |
| `Cmd+R` / `Ctrl+R` | Reset |
| `Cmd+V` / `Ctrl+V` | Paste text (auto-key: feeds the clipboard's contents in as keystrokes) |
| `Cmd+S` / `Ctrl+S` | Quick Save |
| `Cmd+L` / `Ctrl+L` | Quick Load |
| `Cmd+1` / `Ctrl+1` | Insert a disk into FD0 (opens a file picker) |
| `Cmd+2` / `Ctrl+2` | Insert a disk into FD1 |
| `Cmd+3` / `Ctrl+3` | Insert the same disk into both FD0 and FD1 |
| `Cmd+Ctrl+F` | Toggle fullscreen |

Other menu items may have shortcuts assigned too - opening the menu always shows the current assignment.

## Settings

The main settings available from the `Device` / `Host` menus:

- **Display resolution** (High Resolution / Standard): affects the machine's display mode, including the X1turboZ-specific 4096-color mode
- **Sound board**: the menu reflects your change immediately, but it is only actually built into the machine on the next reset (`Control > Reset`). If sound is wrong right after switching, reset once
- **Scanline / Filter (Nearest Neighbor, Bilinear)**: how the display is scaled up
- **Volume**: adjust master volume and the L/R link from `Host > Sound > Volume`
- **Language**: choose System / Japanese / English. Switching takes effect on next launch
- **Keyboard**: toggle whether the arrow keys or the number row act as a numeric ten-key

## Save states

`Control > Save State…` / `Load State…` let you save to and restore from multiple slots. Quick Save / Quick Load (`Cmd/Ctrl+S` / `Cmd/Ctrl+L`) are a shortcut that uses one dedicated slot.

State files use this app's own format and are not compatible with other emulators or other BubiX1turboZ versions. Since a state does not include the ROM data itself, loading it against a different ROM than the one used to save it can corrupt the machine's state. If a problem is detected on load, a message summarizing the issue is shown.

## Sound recording and screenshots

The `Host` menu's "Rec Sound" and "Capture Screen" write to the OS's standard Music and Pictures folders respectively (separate from app-private folders like `roms/`).

## Building from source

See the repository's `README.md` if you want to build from source.
