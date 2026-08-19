# alacritty-tools

Two small POSIX shell tools that change Alacritty's appearance at runtime,
without ever editing `alacritty.toml`.

| | |
|---|---|
| `alacritty-theme` | light/dark palette across Alacritty, tmux-dotbar and herdr |
| `alacritty-font` | browse and set the font family and size |

Both repaint every open window instantly, because Alacritty live-reloads its
config and both tools write files that config *imports*.

## Install

```sh
git clone git@github.com:aglowinthefield/alacritty-tools.git ~/code/alacritty-tools
cd ~/code/alacritty-tools && ./install.sh
```

`install.sh` symlinks the two tools into `~/.local/bin`, links the palettes
where the config and `.tmux.conf` expect them, seeds the generated files, and —
on macOS, if `dark-notify` is installed — loads a launchd agent that follows the
system appearance. It is idempotent; re-run it after a pull. `--uninstall`
removes the symlinks and the agent.

`alacritty.toml` must import the two generated files:

```toml
import = [
  "~/.config/alacritty/theme.toml",
  "~/.config/alacritty/font.toml",
]
```

and must **not** set `family` or `size` under `[font]` — see below. `install.sh`
checks both and tells you what's missing rather than editing your config.

## Usage

```sh
theme                 # what's on, across all three tools
theme dark | light    # set a variant
theme toggle
theme auto            # follow the macOS system appearance
theme pick [variant]  # browse themes that suit the variant, live

font                  # current family and size
font pick             # browse installed families, live
font set <family>
font size <points>
font reset            # back to this machine's default
```

`pick` needs `fzf`. Font enumeration needs `fontconfig` (`fc-list`); everything
else works without it.

Choices persist to `~/.config/alacritty/overrides.conf`, which both tools share.
Delete a line to fall back to the default.

## How it works

Alacritty has no light/dark mode: it loads one palette and that is that. So:

- `theme.toml` and `font.toml` are **generated**, and `alacritty.toml` imports
  them. Picking a theme or font rewrites a generated file, never your config.
- The tmux status bar rides along via `~/.tmux/theme.conf`, because dotbar's
  background is meant to be the terminal's background. A picked theme that
  isn't one of the two defaults gets its bar colours derived from the theme
  itself, by blending its foreground toward its background.
- herdr is not driven at all: its `[theme] auto_switch` follows the *host
  terminal's* appearance, so repainting Alacritty is enough.

## Things that cost time to find out

Recorded because each one fails silently.

- **A missing import is silent.** Alacritty falls back to its built-in
  `#181818` — one shade off kanagawa dragon's `#181616` — and logs nothing. It
  reads as "the theme didn't change", not "the config is broken".
- **A file that doesn't exist can't be watched.** An Alacritty that starts while
  `theme.toml` is absent never registers a watch on it and ignores every later
  switch, forever. Both tools touch `alacritty.toml` — which *is* watched — the
  first time they create a generated file, to force a re-read.
- **The main config beats its imports.** A `family` left in `alacritty.toml`
  silently overrides the generated `font.toml`, and the font tool looks inert.
  This is why per-machine font defaults live in `font-default.toml`.
- **`fc-list` prints aliases as well as family names.** Splitting its output on
  commas invents families like "BlexMono Nerd Font Light", which is a *style* of
  "BlexMono Nerd Font". On macOS Alacritty resolves through Core Text, which has
  no such family, so it logs `font FontDesc { ... } not found` and keeps the old
  font. Measured against Core Text's own list: 429 of 602 such names did not
  exist. Take only the first comma-separated value.
- **launchd hands out a bare `PATH`** (`/usr/bin:/bin:/usr/sbin:/sbin`), so
  Homebrew's `tmux` and `fc-list` are invisible to the agent. The file on disk
  still updates, so only the live re-source is skipped — silently. Both tools
  put the usual prefixes back.
- **Seeding fzf's `--query` filters the list.** Seeding it with the current font
  collapsed 602 families to that family's 14 weights, which looks exactly like a
  picker that knows one font. Use `start:pos(N)` to place the cursor instead.

## Palettes

`share/colors` holds palettes vendored verbatim from their upstreams — don't
hand-tune them, re-copy after updating the source:

| File | |
|---|---|
| `kanagawa-lotus.toml` | official light kanagawa, `rebelot/kanagawa.nvim` |
| `kanagawa-paper-ink.toml` | dark, `thesimonho/kanagawa-paper.nvim` |
| `kanagawa-paper-canvas.toml` | light, same — but only 3.4:1 contrast, below the 4.5:1 floor |

`theme pick` also lists anything in `~/.config/alacritty/colors` and any
[alacritty-theme](https://github.com/alacritty/alacritty-theme) checkout at
`~/.config/alacritty/themes`.
