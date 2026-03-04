# msnap

Screenshot and Screencast util that aims to provide a better experience with mangowm.


https://github.com/user-attachments/assets/53a4c616-3a6f-4400-ae9c-a15e277e710f


---

## Project Status

> ⚠️ **Early stage**
> Most of the things are functional but not guaranteed!!
> All dependencies are chosen to work well with **mangowm (wlroots)**.
> A potential new mango ipc implementation is awaited before proper status.

## Dependencies

  - [`grim`](https://gitlab.freedesktop.org/emersion/grim)
  - [`slurp`](https://github.com/emersion/slurp)
  - [`wl-copy`](https://github.com/bugaevc/wl-clipboard)
  - [`notify-send`](https://gitlab.gnome.org/GNOME/libnotify)
  - [`wayfreeze`](https://github.com/Jappie3/wayfreeze) (for freezing screen)
  - [`satty`](https://github.com/gabm/Satty) (for annotations)
  - [`gpu-screen-recorder`](https://git.dec05eba.com/gpu-screen-recorder/) (for recording)
  - [`quickshell` (qs)](https://github.com/quickshell-mirror/quickshell) (for **gui**)
  - [`ffmpeg`](https://git.ffmpeg.org/ffmpeg.git) (for thumbnail generation in cast notify)

> **Note:** `wayfreeze` must be in your global PATH.

## Installation

Run the following command to clone the repository, install binaries to `~/.local/bin`, and set up all configurations in `~/.config/msnap`:

```sh
curl -fsSL https://raw.githubusercontent.com/atheeq-rhxn/msnap/main/install.sh | sh

```

*Note: Ensure `~/.local/bin` is in your `PATH`.*

## Usage

```sh
msnap shot [OPTIONS]    # Take a screenshot
msnap cast [OPTIONS]    # Record screen
```

### Commands and Options

#### `msnap shot`

| Flag | Argument | Description |
| --- | --- | --- |
| *(no flags)* | - | Screenshot full screen |
| `-r`, `--region` | - | Screenshot a selected region |
| `-g`, `--geometry` | `SPEC` | Capture region with direct geometry in "x,y wxh" format |
| `-w`, `--window` | - | Capture the active window via `mmsg` |
| `-p`, `--pointer` | - | Include mouse pointer in capture |
| `-a`, `--annotate` | - | Open in `satty` for annotation |
| `-o`, `--output` | `DIRECTORY` | Set the output directory |
| `-f`, `--filename` | `NAME` | Set the output filename/pattern |
| `--no-copy` | - | Skip copying to clipboard |
| `-F`, `--freeze` | - | Freeze the screen before capturing (requires `wayfreeze`) |

#### `msnap cast`

| Flag | Argument | Description |
| --- | --- | --- |
| *(no flags)* | - | Record full screen |
| `-r`, `--region` | - | Record a selected screen region |
| `-g`, `--geometry` | `SPEC` | Record region with direct geometry in "x,y wxh" format |
| `-t`, `--toggle` | - | Toggle recording on/off |
| `-o`, `--output` | `DIRECTORY` | Set the output directory |
| `-f`, `--filename` | `NAME` | Set the output filename/pattern |
| `-a`, `--audio` | - | Record system audio |
| `-m`, `--mic` | - | Record microphone |
| `-A`, `--audio-device` | `DEVICE` | System audio device (default: default_output) |
| `-M`, `--mic-device` | `DEVICE` | Microphone device (default: default_input) |

### `gui`

Launch the GUI:

```sh
qs -p ~/.config/msnap/gui
```

**Keyboard Shortcuts:**

| Key | Action |
|-----|--------|
| `H` / `L` | Navigate capture modes (left/right) |
| `J` / `K` | Switch mode (Screenshot/Record) |
| `Tab` | Toggle mode |
| `Enter` / `Space` | Execute action |
| `P` | Toggle pointer (screenshot only) |
| `E` | Toggle annotation (screenshot only) |
| `A` | Toggle system audio (recording only) |
| `M` | Toggle microphone (recording only) |
| `Escape` | Close / Stop recording |

When recording, a red indicator appears in the top-right corner; hover and click it to stop.

## mango Configuration

Example keybinds:
```ini
# gui 
bind=none,Print,spawn,qs -p ~/.config/msnap/gui

# Screenshot: Selected region
bind=SHIFT,Print,spawn_shell,msnap shot --region

# Screencast: Toggle region recording
bind=SHIFT,ALT,spawn_shell,msnap cast --toggle --region
```

**Note:** Add the following rule to prevent the `gui` layer from being animated or blurred:

```ini
layerrule=layer_name:msnap,noanim:1,noblur:1
```

## Configuration

Default settings are stored in `~/.config/msnap/`:

* **`msnap.conf`**: Sets screenshot and recording defaults:
  - `shot_output_dir` (default: `~/Pictures/Screenshots`)
  - `shot_filename_pattern` (default: `%Y%m%d%H%M%S.png`)
  - `shot_pointer_default` (default: `false`)
  - `cast_output_dir` (default: `~/Videos/Screencasts`)
  - `cast_filename_pattern` (default: `%Y%m%d%H%M%S_screencast.mp4`)
* **`gui.conf`**: Theme (colors, accents, alphas) and behaviour (quick_capture).

### Configuration Precedence

Values are resolved in the following order (highest to lowest priority):

1. CLI arguments (e.g., `--output`, `--filename`)
2. Configuration file values (in `~/.config/msnap/msnap.conf`)
3. XDG environment variables (e.g., `XDG_PICTURES_DIR`, `XDG_VIDEOS_DIR`)
4. Hardcoded defaults in source code

## Development

- cli is built using **[bashly](https://bashly.dev/)**.
- gui is built using **[quickshell](https://github.com/quickshell-mirror/quickshell)** 

The project structure is:

```
msnap/
├── cli/
│   ├── src/
│   │   ├── shot_command.sh      # Screenshot command
│   │   ├── cast_command.sh      # Recording command
│   │   ├── initialize.sh
│   │   ├── bashly.yml
│   │   └── lib/
│   │       ├── ini.sh
│   │       ├── notify.sh
│   │       └── validate_geometry_format.sh
│   └── msnap                    # Generated executable
└── gui/
    ├── shell.qml
    ├── Config.qml
    ├── RegionSelector.qml
    ├── Icon.qml
    ├── gui.conf
    └── icons/
```

To regenerate after modifying cli files:

```sh
cd cli
bashly generate
```
