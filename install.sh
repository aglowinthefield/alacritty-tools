#!/bin/sh
# install.sh — link the tools into ~/.local/bin and put their assets where the
# rest of the setup expects them. Idempotent; safe to re-run after a git pull.
#
#   ./install.sh              link tools + assets, seed theme.toml/font.toml
#   ./install.sh --no-agent   skip the macOS appearance-following launchd agent
#   ./install.sh --uninstall  remove the symlinks and the agent
#
# Nothing here edits alacritty.toml. The tools work by generating files that
# alacritty.toml *imports*, so your config stays yours — install.sh only checks
# the imports are present and tells you what to add if they aren't.

set -eu

REPO=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/alacritty"
TMUX_DIR="$HOME/.tmux"
AGENT_LABEL="com.tauty.alacritty-theme"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"

want_agent=true
uninstall=false
for arg in "$@"; do
	case $arg in
	--no-agent) want_agent=false ;;
	--uninstall) uninstall=true ;;
	-h | --help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	*) printf 'install.sh: unknown option %s\n' "$arg" >&2; exit 1 ;;
	esac
done

link() {
	src=$1 dest=$2
	mkdir -p "$(dirname "$dest")"
	# Replace our own symlink silently; never clobber a real file someone put there.
	if [ -L "$dest" ]; then
		rm -f "$dest"
	elif [ -e "$dest" ]; then
		printf 'install.sh: %s exists and is not a symlink — leaving it alone\n' "$dest" >&2
		return 0
	fi
	ln -s "$src" "$dest"
	printf '  %s -> %s\n' "$dest" "$src"
}

unlink_ours() {
	dest=$1
	if [ -L "$dest" ] && [ "$(readlink "$dest" | sed "s|^$REPO||")" != "$(readlink "$dest")" ]; then
		rm -f "$dest"
		printf '  removed %s\n' "$dest"
	fi
}

if [ "$uninstall" = true ]; then
	echo "removing symlinks:"
	for t in alacritty-theme alacritty-font; do unlink_ours "$BIN_DIR/$t"; done
	for v in dark light; do unlink_ours "$TMUX_DIR/dotbar-$v.conf"; done
	for f in "$REPO"/share/colors/*.toml; do unlink_ours "$CONFIG_DIR/colors/$(basename "$f")"; done
	if [ -f "$AGENT_PLIST" ]; then
		launchctl bootout "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null || true
		rm -f "$AGENT_PLIST"
		printf '  removed %s\n' "$AGENT_PLIST"
	fi
	echo "done. theme.toml, font.toml and overrides.conf were left in place."
	exit 0
fi

echo "linking tools:"
link "$REPO/bin/alacritty-theme" "$BIN_DIR/alacritty-theme"
link "$REPO/bin/alacritty-font" "$BIN_DIR/alacritty-font"

# .tmux.conf sources ~/.tmux/dotbar-dark.conf as its fallback palette, so the
# curated palettes have to be reachable at a fixed path as well as from share/.
echo "linking tmux palettes:"
for v in dark light; do
	link "$REPO/share/tmux/dotbar-$v.conf" "$TMUX_DIR/dotbar-$v.conf"
done

# The palettes are read from share/ directly, but linking them into the config
# dir keeps `import` lines and notes that reference colors/ working.
echo "linking palettes:"
for f in "$REPO"/share/colors/*.toml; do
	link "$f" "$CONFIG_DIR/colors/$(basename "$f")"
done

# Alacritty fails a missing import *silently* — you get the built-in defaults and
# no error — so say plainly what's missing rather than editing the config.
missing=""
for f in theme.toml font.toml; do
	grep -q "alacritty/$f" "$CONFIG_DIR/alacritty.toml" 2>/dev/null || missing="$missing $f"
done
if [ -n "$missing" ]; then
	printf '\nalacritty.toml does not import:%s\n' "$missing"
	printf 'Add to your import list, then re-run this script:\n\n'
	printf 'import = [\n'
	printf '  "~/.config/alacritty/theme.toml",\n'
	printf '  "~/.config/alacritty/font.toml",\n'
	printf ']\n\n'
	printf 'Also remove any `family`/`size` under [font]: the main config beats\n'
	printf 'its imports, so those would silently override font.toml.\n'
fi

echo
echo "seeding generated files:"
PATH="$BIN_DIR:$PATH"
export PATH
alacritty-theme auto 2>/dev/null || alacritty-theme dark
alacritty-font apply
printf '  theme: %s\n' "$(alacritty-theme | head -1)"
printf '  font:  %s\n' "$(alacritty-font | head -1)"

# macOS only: dark-notify watches the system appearance and runs the command with
# "light" or "dark" as its only argument, which is exactly what alacritty-theme
# takes. Everything else switches manually.
if [ "$want_agent" = true ] && [ "$(uname -s)" = Darwin ]; then
	if ! command -v dark-notify >/dev/null 2>&1; then
		echo
		echo "dark-notify not installed — skipping the appearance agent."
		echo "  brew install cormacrelf/tap/dark-notify && ./install.sh"
	else
		mkdir -p "$(dirname "$AGENT_PLIST")"
		cat >"$AGENT_PLIST" <<-PLIST
			<?xml version="1.0" encoding="UTF-8"?>
			<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
			<plist version="1.0">
			<dict>
				<key>Label</key>
				<string>$AGENT_LABEL</string>
				<key>ProgramArguments</key>
				<array>
					<string>$(command -v dark-notify)</string>
					<string>-c</string>
					<string>$BIN_DIR/alacritty-theme</string>
				</array>
				<key>RunAtLoad</key>
				<true/>
				<key>KeepAlive</key>
				<true/>
				<key>ThrottleInterval</key>
				<integer>10</integer>
				<key>StandardOutPath</key>
				<string>$HOME/Library/Logs/alacritty-theme.log</string>
				<key>StandardErrorPath</key>
				<string>$HOME/Library/Logs/alacritty-theme.log</string>
			</dict>
			</plist>
		PLIST
		launchctl bootout "gui/$(id -u)/$AGENT_LABEL" 2>/dev/null || true
		# bootout is asynchronous. Bootstrapping while the old job is still
		# tearing down fails with "Input/output error", so wait for it to go.
		n=0
		while launchctl print "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1 && [ "$n" -lt 25 ]; do
			sleep 0.2
			n=$((n + 1))
		done
		echo
		if launchctl bootstrap "gui/$(id -u)" "$AGENT_PLIST" 2>/dev/null; then
			printf 'appearance agent loaded (%s)\n' "$AGENT_LABEL"
		else
			printf 'could not load the appearance agent. Load it by hand:\n'
			printf '  launchctl bootstrap gui/$(id -u) %s\n' "$AGENT_PLIST"
		fi
	fi
fi
