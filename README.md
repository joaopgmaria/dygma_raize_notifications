# Dygma Raise LED Notifications

Keyboard LED control for the [Dygma Raise](https://dygma.com/products/dygma-raise) via its Focus serial protocol — no OpenRGB, no extra software. Includes a persistent HTTP service, a CLI, shell hooks, an RSpec formatter, and Claude Code integration.

## How it works

The Dygma Raise exposes a serial port (`/dev/cu.usbmodem*`) using the Focus protocol — the same one Bazecor uses. Commands are plain text over serial, terminated with `\n`, and responses end with a lone `.`. LED changes go to RAM only and are lost on unplug, so the keyboard always reboots to its saved Bazecor profile.

## Requirements

- macOS
- Dygma Raise keyboard
- Ruby (via rbenv)
- Xcode Command Line Tools (for the Swift lock watcher)

## Installation

```sh
git clone https://github.com/joaopgmaria/dygma_raize_notifications ~/playground/keyboard
cd ~/playground/keyboard

# Map your keyboard layout (keyboard must be plugged in)
ruby bin/map_layout.rb

# Run setup: installs gems, compiles Swift binary, installs lock-watch
# LaunchAgent, installs DygmaAutostart Login Item, patches .zshrc/.zshenv/.rspec
bin/setup

# Reload shell and start the service for this session
source ~/.zshrc
dygma start
```

The service auto-starts on subsequent logins via the `DygmaAutostart` Login Item. The first time, start it manually with `dygma start`.

### Claude Code hooks

Merge the hooks from `docs/claude-hooks.json` into `~/.claude/settings.json` to get LED feedback while Claude Code is running.

## CLI

```sh
dygma start                              # start the service
dygma stop                               # stop the service
dygma restart                            # restart the service
dygma status                             # service status and active notifications

dygma flash   <section> <color> [count]  # flash N times then restore
dygma solid   <section> <color> [secs]   # hold color until cancelled or timeout
dygma breathe <section> <color> [secs]   # slow fade in/out
dygma alternate <color> [count]          # alternate left/right halves
dygma chase   <section> <color> [sweeps] # KITT-style scanner
dygma matrix  <section> <color> [secs]   # Matrix digital rain
dygma rainbow <section> [secs]           # rainbow wave scrolling left to right

dygma text  <string> [color]             # light up keys matching each character
dygma text  clear

dygma progress <0-100>                   # progress bar on digit keys
dygma progress clear

dygma cancel <id>                        # cancel notification by id
dygma cancel-section <section>           # cancel active notification on a section
dygma clear                              # cancel everything and restore saved scheme

dygma save                               # save current LED state to ~/.keyboard/scheme
dygma restore                            # restore LED state from ~/.keyboard/scheme
```

### Sections

| Section | Keys |
|---|---|
| `all` | All keys + space bar (no underglow) |
| `top_row` | esc → backspace |
| `space_bar` | space1–4, thumb1–4 (thumb cluster) |
| `left` / `right` | Left / right key halves |
| `underglow` | All underglow LEDs |
| `underglow_left` / `underglow_right` | Half underglow |
| `neuron` | Centre neuron LED |

### Colors

`red` `green` `blue` `yellow` `cyan` `magenta` `white` `orange` `pink` `purple` `off`

## Animations

### `chase` — KITT scanner
A bright column sweeps left and right with a fading trail. On `all`, each step lights an entire physical column of keys simultaneously.

### `matrix` — Digital rain
Independent raindrops fall down each keyboard column with randomised speeds and delays. The underglow is set to a solid background color while the rain runs on the keys.

### `rainbow` — Rainbow wave
The full color spectrum is spread evenly across all columns and scrolls continuously left to right. No color argument needed — colors are generated from HSV hue rotation.

## Shell hooks

The shell hooks in `shell/keyboard_hooks.zsh` (sourced from `.zshrc`) give LED feedback for CLI commands:

- **Short command** — no feedback
- **Long command (≥ 3s), success** — yellow breathe during the wait, green flash on finish
- **Any command, failure** — immediate red flash × 5

The threshold is configurable: `export KEYBOARD_CMD_THRESHOLD=5`

## RSpec integration

The `ruby/keyboard_progress.rb` formatter is auto-loaded by `~/.rspec` for any RSpec run:

- **Suite start** — yellow breathe on underglow, progress bar starts
- **Per-test** — progress bar advances on digit keys (red → orange → yellow → green)
- **Suite pass** — green flash × 5
- **Suite fail** — red flash × 5

## Screen lock

A compiled Swift watcher (`bin/lock-watch-bin`) listens for macOS screen lock/unlock events via `NSDistributedNotificationCenter` and switches the keyboard to Matrix mode while locked.

It runs as a launchd agent (`com.keyboard.lock-watch`) and starts automatically on login.

## Service management

The keyboard service runs as a background process started by `dygma start`. It uses `fork + setsid` to detach from the terminal session — closing the terminal does not stop it. It inherits the interactive Mach bootstrap context from the calling process, which gives accurate timer resolution for animations (launchd agents coalesce timers to ~75ms, making animations 2× slower).

```
dygma start    # start (idempotent)
dygma stop     # stop
dygma restart  # restart
```

Logs: `/tmp/keyboard-service.log`
PID file: `~/.keyboard/service.pid`
