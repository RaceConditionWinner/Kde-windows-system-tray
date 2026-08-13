#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────
#  Windows Modern System Tray — uninstaller
#
#  Restores the stock KDE System Tray and your previous icon theme, then
#  removes the Windows Modern plugin and icon theme files.
#
#  Usage:
#      curl -fsSL https://github.com/RaceConditionWinner/Kde-windows-system-tray/releases/latest/download/uninstall.sh | bash
#
#  Safe to run more than once.
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

APP_ID="org.kde.windowsmodern.systemtray"
THEME_NAME="WindowsModern-WhiteSurApps"
STOCK_PLUGIN="org.kde.plasma.systemtray"

STATE_DIR="$HOME/.local/share/windowsmodern-systemtray"
STATE_FILE="$STATE_DIR/state"
ICON_DEST="$HOME/.local/share/icons/${THEME_NAME}"

BOLD="\033[1m"; GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; RESET="\033[0m"
info()  { echo -e "${GREEN}==>${RESET} ${BOLD}$*${RESET}"; }
warn()  { echo -e "${YELLOW}==>${RESET} $*"; }
err()   { echo -e "${RED}==>${RESET} $*"; }
die()   { err "$*"; exit 1; }

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    die "Don't run this as root. It will ask for your password (via pkexec) only for the one step that needs it."
fi
command -v pkexec &>/dev/null || die "pkexec not found (part of polkit). It's required to remove the system-installed plugin."

QDBUS=""
for _c in qdbus6 qdbus; do
    if command -v "$_c" &>/dev/null; then QDBUS="$_c"; break; fi
done
[ -n "$QDBUS" ] || warn "Neither qdbus6 nor qdbus found — the panel can't be restored automatically. Proceeding with a best-effort removal."

# Runs a Plasma Desktop Scripting snippet against the live Plasma Shell via
# org.kde.PlasmaShell.evaluateScript, instead of editing
# plasma-org.kde.plasma.desktop-appletsrc directly while plasmashell has it
# open. print() calls inside the script become this function's stdout.
plasma_eval() {
    "$QDBUS" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$1"
}

PREVIOUS_ICON_THEME=""
if [ -f "$STATE_FILE" ]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
    if [ -n "${APPLETSRC_BACKUP:-}" ] && [ -f "$APPLETSRC_BACKUP" ]; then
        info "A pre-install panel-layout backup is also available at: ${APPLETSRC_BACKUP}"
    fi
else
    warn "No installer state found at ${STATE_FILE}."
    warn "Proceeding with a best-effort removal — your previous icon theme can't be restored automatically."
fi

# ── Detect install paths (same logic as install.sh / dev.sh) ─────────────
if command -v pkg-config &>/dev/null; then
    QT_PLUGIN_DIR="$(pkg-config --variable=plugindir Qt6Core 2>/dev/null || true)"
fi
if [ -z "${QT_PLUGIN_DIR:-}" ]; then
    if [ -d /usr/lib64/qt6/plugins ]; then
        QT_PLUGIN_DIR=/usr/lib64/qt6/plugins
    elif [ -d /usr/lib/qt6/plugins ]; then
        QT_PLUGIN_DIR=/usr/lib/qt6/plugins
    else
        QT_PLUGIN_DIR=/usr/lib64/qt6/plugins
    fi
fi
PLUGIN_DST="$QT_PLUGIN_DIR/plasma/applets/${APP_ID}.so"
KPACKAGE_DIR="/usr/share/plasma/plasmoids/${APP_ID}"

# ── Panel: restore stock System Tray in place, live, via Plasma's own ──
#    scripting API (org.kde.PlasmaShell.evaluateScript) — mirrors
#    install.sh, and does NOT edit plasma-org.kde.plasma.desktop-appletsrc
#    directly. Widget.index preserves panel position.
PANEL_STATUS="unchanged"
if [ -n "$QDBUS" ]; then
    PANEL_SCRIPT=$(cat <<JS
var stockId = "${STOCK_PLUGIN}";
var newId = "${APP_ID}";
var allPanels = panels();
var restored = 0;
for (var i = 0; i < allPanels.length; i++) {
    var panel = allPanels[i];
    var ours = panel.widgets(newId);
    for (var j = 0; j < ours.length; j++) {
        var oldIndex = ours[j].index;
        ours[j].remove();
        var w = panel.addWidget(stockId);
        w.index = oldIndex;
        restored++;
    }
}
if (restored > 0) {
    print("RESTORED:" + restored);
} else {
    var stockPresent = false;
    for (var i = 0; i < allPanels.length; i++) {
        if (allPanels[i].widgets(stockId).length > 0) { stockPresent = true; }
    }
    print(stockPresent ? "ALREADY_STOCK" : "NOT_FOUND");
}
JS
)
    PANEL_RESULT="$(plasma_eval "$PANEL_SCRIPT" 2>&1)" || PANEL_RESULT="EVAL_FAILED:$PANEL_RESULT"

    case "$PANEL_RESULT" in
        RESTORED:*)
            PANEL_STATUS="restored"
            info "Restored the stock System Tray on your panel (same position)." ;;
        ALREADY_STOCK)
            PANEL_STATUS="already-stock"
            info "Stock System Tray is already on your panel." ;;
        NOT_FOUND)
            PANEL_STATUS="not-found"
            warn "Neither System Tray variant was found on any panel — leaving panel layout untouched." ;;
        *)
            PANEL_STATUS="script-failed"
            warn "Plasma scripting call did not complete as expected: ${PANEL_RESULT}"
            warn "Add the stock System Tray to your panel manually if needed." ;;
    esac
else
    warn "Skipping automatic panel restore (no qdbus) — add the stock System Tray manually if needed."
fi

# ── Remove plugin (needs root) ─────────────────────────────────────────
info "Removing plugin (requires your password)..."
TMP_UNINSTALL="$(mktemp /tmp/windowsmodern-systray-uninstall.XXXXXX)"
cat > "$TMP_UNINSTALL" <<EOF
#!/bin/bash
set -e
rm -f "$PLUGIN_DST"
rm -rf "$KPACKAGE_DIR"
EOF
chmod +x "$TMP_UNINSTALL"
pkexec bash "$TMP_UNINSTALL" || warn "Could not remove the system plugin file (continuing)."
rm -f "$TMP_UNINSTALL"

rm -rf "$HOME/.local/share/plasma/plasmoids/${APP_ID}" 2>/dev/null || true
rm -f "$HOME/.local/lib64/qt6/plugins/plasma/applets/${APP_ID}.so" 2>/dev/null || true
rm -f "$HOME/.local/lib/qt6/plugins/plasma/applets/${APP_ID}.so" 2>/dev/null || true
info "Plugin removed."

# ── Icon theme: remove + restore previous theme ────────────────────────
if [ -d "$ICON_DEST" ]; then
    rm -rf "$ICON_DEST"
    info "Removed icon theme at ${ICON_DEST}."
fi

if [ -n "$PREVIOUS_ICON_THEME" ]; then
    if command -v plasma-changeicons &>/dev/null; then
        if plasma-changeicons "$PREVIOUS_ICON_THEME"; then
            info "Restored previous icon theme: ${PREVIOUS_ICON_THEME}."
        else
            warn "Could not restore the previous icon theme automatically. Set it via System Settings → Colors & Themes → Icons."
        fi
    else
        if kwriteconfig6 --file kdeglobals --group Icons --key Theme "$PREVIOUS_ICON_THEME" 2>/dev/null; then
            info "Restored previous icon theme: ${PREVIOUS_ICON_THEME}."
        else
            warn "Could not restore the previous icon theme automatically."
        fi
    fi
else
    warn "No previous icon theme on record — leaving the active icon theme as-is."
fi

# ── Restart plasmashell ────────────────────────────────────────────────
info "Restarting plasmashell..."
if systemctl --user is-active plasma-plasmashell.service &>/dev/null; then
    systemctl --user restart plasma-plasmashell.service
else
    kquitapp6 plasmashell 2>/dev/null || killall plasmashell 2>/dev/null || true
    sleep 1
    nohup plasmashell --replace >/dev/null 2>&1 &
    disown
fi
sleep 3

# ── Verify ──────────────────────────────────────────────────────────────
info "Verifying removal..."
if [ -f "$PLUGIN_DST" ]; then
    echo -e "  ${RED}✗${RESET} Plugin still present at ${PLUGIN_DST}"
else
    echo -e "  ${GREEN}✓${RESET} Plugin removed"
fi
if [ -d "$ICON_DEST" ]; then
    echo -e "  ${RED}✗${RESET} Icon theme still present at ${ICON_DEST}"
else
    echo -e "  ${GREEN}✓${RESET} Icon theme removed"
fi
case "$PANEL_STATUS" in
    restored|already-stock)
        echo -e "  ${GREEN}✓${RESET} Stock System Tray is on your panel" ;;
    *)
        echo -e "  ${YELLOW}!${RESET} Panel not confirmed — add the stock System Tray manually if needed" ;;
esac

rm -rf "$STATE_DIR"

echo ""
info "Done. Windows Modern System Tray has been uninstalled."
