#!/bin/sh
# Build, install or remove HopDDC.
#   ./hopddc.sh build       build build/HopDDC.app
#   ./hopddc.sh install     build, copy to ~/Applications, link the CLI, launch
#   ./hopddc.sh uninstall   quit, remove the login item, the app and the CLI link
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
BUILT="$DIR/build/HopDDC.app"
DEST="$HOME/Applications/HopDDC.app"
EXE="$DEST/Contents/MacOS/HopDDC"
LINK="$HOME/.local/bin/hopddc"
DOMAIN=com.hugolamarche.hopddc

build() {
    swift build --package-path "$DIR" -c release
    BIN="$(swift build --package-path "$DIR" -c release --show-bin-path)"
    rm -rf "$BUILT"
    mkdir -p "$BUILT/Contents/MacOS"
    cp "$BIN/HopDDC" "$BUILT/Contents/MacOS/"
    cp "$DIR/Resources/Info.plist" "$BUILT/Contents/"
    codesign --force --sign - "$BUILT"
}

quit_app() {
    pkill -x HopDDC 2>/dev/null || true
    while pgrep -x HopDDC >/dev/null; do sleep 0.1; done
}

install() {
    build
    quit_app
    mkdir -p "$(dirname "$DEST")" "$(dirname "$LINK")"
    rm -rf "$DEST"
    cp -R "$BUILT" "$DEST"
    ln -sf "$EXE" "$LINK"
    open "$DEST"
    echo "Installed $DEST and linked $LINK."
    case ":$PATH:" in
        *":$(dirname "$LINK"):"*) ;;
        *) echo "Add $(dirname "$LINK") to your PATH to use the hopddc command." ;;
    esac
}

uninstall() {
    [ -x "$EXE" ] && "$EXE" login off 2>/dev/null || true
    quit_app
    rm -rf "$DEST"
    rm -f "$LINK"
    defaults delete "$DOMAIN" didFirstLaunch 2>/dev/null || true  # re-add login item on next install
    echo "Uninstalled. Settings are kept; remove them with: defaults delete $DOMAIN"
}

case "$1" in
    build)     build ;;
    install)   install ;;
    uninstall) uninstall ;;
    *) echo "usage: $0 build|install|uninstall" >&2; exit 2 ;;
esac
