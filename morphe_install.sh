
bash <<'INSTALL'
set -Eeuo pipefail
umask 022

REPO="MorpheApp/morphe-desktop"
BASE="$HOME/applications/morphe"
APP="$HOME/.local/share/applications"
ICONS="$HOME/.local/share/icons"
JAR="$BASE/morphe-desktop.jar"
DESKTOP="$APP/morphe-desktop.desktop"
ICON="$ICONS/morphe-logo.png"

for cmd in curl python3 unzip cmp install mv mktemp java; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Missing dependency: $cmd" >&2
        exit 1
    }
done

mkdir -p "$BASE" "$APP" "$ICONS"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Finding latest Morphe Desktop release..."

URL="$(python3 - "$REPO" <<'PY'
import json, re, sys, time, urllib.request

url = f"https://api.github.com/repos/{sys.argv[1]}/releases?per_page=100"

while url:
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={
                "Accept": "application/vnd.github+json",
                "User-Agent": "Morphe-Installer",
            })
            with urllib.request.urlopen(req, timeout=30) as r:
                releases = json.load(r)
                links = r.headers.get("Link", "")
            break
        except Exception:
            if attempt == 2:
                raise
            time.sleep(2 ** attempt)

    for release in releases:
        if release.get("draft"):
            continue
        for asset in release.get("assets", []):
            name = asset.get("name", "")
            if name.startswith("morphe-desktop-") and name.endswith("-all.jar"):
                print(asset["browser_download_url"])
                sys.exit(0)

    match = re.search(r'<([^>]+)>;\s*rel="next"', links)
    url = match.group(1) if match else None

sys.exit("No matching JAR found in published releases.")
PY
)"

NAME="${URL##*/}"
echo "Downloading $NAME..."

curl -fLsS --retry 3 --retry-all-errors "$URL" -o "$TMP/morphe.jar"
unzip -tqq "$TMP/morphe.jar"

unzip -p "$TMP/morphe.jar" morphe_logo.png > "$TMP/logo.png"
python3 -c 'import sys; assert open(sys.argv[1],"rb").read(8) == b"\x89PNG\r\n\x1a\n", "Invalid PNG"' "$TMP/logo.png"

# Install only when the contents change.
if ! cmp -s "$TMP/morphe.jar" "$JAR" 2>/dev/null; then
    install -m 644 "$TMP/morphe.jar" "$TMP/morphe.jar.new"
    mv -f "$TMP/morphe.jar.new" "$JAR"
fi

if ! cmp -s "$TMP/logo.png" "$ICON" 2>/dev/null; then
    install -m 644 "$TMP/logo.png" "$TMP/logo.new"
    mv -f "$TMP/logo.new" "$ICON"
fi

cat > "$TMP/launcher" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Morphe Desktop
Comment=Morphe Desktop Manager
Exec="$(command -v java)" -jar "$JAR"
Icon=$ICON
Terminal=false
Categories=Utility;Development;
StartupNotify=true
EOF

if ! cmp -s "$TMP/launcher" "$DESKTOP" 2>/dev/null; then
    install -m 755 "$TMP/launcher" "$APP/.morphe-desktop.new"
    mv -f "$APP/.morphe-desktop.new" "$DESKTOP"
fi

command -v update-desktop-database >/dev/null 2>&1 &&
    update-desktop-database "$APP" >/dev/null 2>&1 || true

echo "Morphe Desktop installed: $NAME"
echo "Launch it from the KDE application menu."
INSTALL
