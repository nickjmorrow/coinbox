#!/bin/sh
# Puts the Coinbox command line and sync hub on your server (HUB_HOST, an ssh host; set it in .env). Usage: scripts/deploy-hub.sh [--load]
#   copies the source to ~/Projects/coinbox on the server, builds the release CLI there, links ~/.local/bin/coinbox,
#   makes ~/coinbox-hub and a token file if missing, and writes the launchd plist.
#   --load also starts the hub (com.nicholai.coinbox-hub, 127.0.0.1:8791); put `tailscale serve` in front for the tailnet.
# If ~/.config/coinbox/simplefin_access_url exists on the server the hub also imports bank activity every 6 hours (you put that file
# there yourself; this script never reads or prints it).
set -e
root="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "$root/.env" ]; then set -a; . "$root/.env"; set +a; fi
host="${HUB_HOST:?set HUB_HOST in .env to the ssh host of the server}"
rsync -a --delete --exclude .build --exclude 'build*' --exclude '*.noindex' --exclude .git --exclude '*.sqlite*' --exclude .env \
  "$root/" "$host:Projects/coinbox/"
ssh "$host" 'sh -s' <<'REMOTE'
set -e
cd ~/Projects/coinbox
swift build --package-path CLI -c release 2>&1 | tail -1
mkdir -p ~/.local/bin ~/coinbox-hub ~/.config/coinbox
ln -sf ~/Projects/coinbox/CLI/.build/release/coinbox ~/.local/bin/coinbox
if [ ! -f ~/.config/coinbox/sync-tokens.json ]; then
  umask 077
  printf '{"%s":"mac"}\n' "$(openssl rand -hex 24)" > ~/.config/coinbox/sync-tokens.json
fi
python3 - <<'PY'
import os
home = os.path.expanduser("~")
extra = ""
if os.path.exists(home + "/.config/coinbox/simplefin_access_url"):
    extra = "    <string>--simplefin-access-file</string><string>" + home + "/.config/coinbox/simplefin_access_url</string>\n"
text = open(home + "/Projects/coinbox/scripts/com.nicholai.coinbox-hub.plist").read().replace("__HOME__", home).replace("__SIMPLEFIN__", extra)
open(home + "/Library/LaunchAgents/com.nicholai.coinbox-hub.plist", "w").write(text)
PY
plutil -lint ~/Library/LaunchAgents/com.nicholai.coinbox-hub.plist
~/.local/bin/coinbox --help | head -3
REMOTE
if [ "$1" = "--load" ]; then
  ssh "$host" 'launchctl bootout gui/$(id -u)/com.nicholai.coinbox-hub 2>/dev/null; launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.nicholai.coinbox-hub.plist && echo loaded'
fi
