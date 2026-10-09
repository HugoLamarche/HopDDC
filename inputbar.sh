#!/bin/sh
# Build, install or remove InputBar.
#   ./inputbar.sh build       build build/InputBar.app
#   ./inputbar.sh install     build, copy to ~/Applications, add the CLI and aliases, launch
#   ./inputbar.sh uninstall   quit, remove the login item, app, CLI link and aliases
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
BUILT="$DIR/build/InputBar.app"
DEST="$HOME/Applications/InputBar.app"
EXE="$DEST/Contents/MacOS/InputBar"
LINK="$HOME/.local/bin/inputbar"
ZSHRC="$HOME/.zshrc"
BEGIN='# >>> InputBar >>>'
END='# <<< InputBar <<<'

build() {
    swift build --package-path "$DIR" -c release
    BIN="$(swift build --package-path "$DIR" -c release --show-bin-path)"
    rm -rf "$BUILT"
    mkdir -p "$BUILT/Contents/MacOS"
    cp "$BIN/InputBar" "$BUILT/Contents/MacOS/"
    cp "$DIR/Resources/Info.plist" "$BUILT/Contents/"
    codesign --force --sign - "$BUILT"
}

quit_app() {
    pkill -x InputBar 2>/dev/null || true
    while pgrep -x InputBar >/dev/null; do sleep 0.1; done
}

remove_aliases() {
    [ -f "$ZSHRC" ] && sed -i '' "/^$BEGIN\$/,/^$END\$/d" "$ZSHRC"
    return 0
}

install() {
    build
    quit_app
    mkdir -p "$(dirname "$DEST")" "$(dirname "$LINK")"
    rm -rf "$DEST"
    cp -R "$BUILT" "$DEST"
    ln -sf "$EXE" "$LINK"

    remove_aliases
    cat >> "$ZSHRC" <<EOF
$BEGIN
alias tostudio='inputbar to studio'
alias tomini='inputbar to mini'
alias topc='inputbar to pc'
$END
EOF
    open "$DEST"
    echo "Installed $DEST. Run 'source ~/.zshrc' (or open a new terminal) to get the aliases."
}

uninstall() {
    [ -x "$EXE" ] && "$EXE" login off 2>/dev/null || true
    quit_app
    rm -rf "$DEST"
    rm -f "$LINK"
    defaults delete com.hugolamarche.inputbar didFirstLaunch 2>/dev/null || true  # re-add login item on next install
    remove_aliases
    echo "Uninstalled. Run 'unalias tostudio tomini topc' in terminals that are already open."
}

case "$1" in
    build)     build ;;
    install)   install ;;
    uninstall) uninstall ;;
    *) echo "usage: $0 build|install|uninstall" >&2; exit 2 ;;
esac
