#!/bin/zsh
# Build Wand for the Forerunner 965.
#   ./build.sh            -> build/Wand.prg (sideload: copy to the watch's GARMIN/Apps)
#   ./build.sh sim        -> build, then start the simulator and run the app in it
#   ./build.sh iq         -> build/Wand.iq, the signed release package for the Connect IQ Store
#   ./build.sh store      -> build/Wand.iq with EMPTY URL and webhook id, whatever is in this folder
#                            (the one to upload: users set both in the Connect IQ app settings)
#   ./build.sh release    -> build/Wand-fr965.prg with EMPTY defaults, for a GitHub release
#   ./build.sh demo       -> build/Wand-demo.prg with sample spots and devices, run in the simulator
#                            (for screenshots; uses demo.jungle, which keeps source/Demo.mc)
# Needs: the Connect IQ SDK symlinked at ~/ciq-sdk, fr965 device files in
# ~/Library/Application Support/Garmin/ConnectIQ/Devices/fr965, Java 17 (brew openjdk@17),
# and a developer key (KEY, default ./developer_key.der; make one with openssl, see README).
# Optional, local-only, never committed: ./webhook_id.txt (the HA webhook id) and HA_URL in the
# environment. Both become the defaults baked into the app; leave them out for a public build,
# users then set the URL and id in the Connect IQ app settings on the phone.
set -e
cd "$(dirname "$0")"
export PATH=/opt/homebrew/opt/openjdk@17/bin:$PATH
SDK=${SDK:-$HOME/ciq-sdk}
KEY=${KEY:-developer_key.der}
HA_URL=${HA_URL:-}
WEBHOOK_ID=""
[ -f webhook_id.txt ] && WEBHOOK_ID=$(cat webhook_id.txt)
TARGET=${1:-prg}
[ $# -gt 0 ] && shift
if [ "$TARGET" = "store" ]; then HA_URL=""; WEBHOOK_ID=""; TARGET=iq; STORE=1; OUT=build/Wand.iq; fi
if [ "$TARGET" = "release" ]; then HA_URL=""; WEBHOOK_ID=""; STORE=1; OUT=build/Wand-fr965.prg; fi
mkdir -p build resources/properties
sed -e "s|__HA_URL__|$HA_URL|" -e "s|__WEBHOOK_ID__|$WEBHOOK_ID|" properties.template.xml > resources/properties/properties.xml
case "$TARGET" in
  iq)
    "$SDK/bin/monkeyc" -e -r -f monkey.jungle -o build/Wand.iq -y "$KEY" -w -l ${TYPECHECK:-1} -O 2 "$@"
    ;;
  prg|sim)
    "$SDK/bin/monkeyc" -d fr965 -f monkey.jungle -o build/Wand.prg -y "$KEY" -w -l ${TYPECHECK:-1} -O 2 "$@"
    ;;
  demo)
    "$SDK/bin/monkeyc" -d fr965 -f demo.jungle -o build/Wand-demo.prg -y "$KEY" -w -l ${TYPECHECK:-1} -O 2 "$@"
    ;;
  release)
    "$SDK/bin/monkeyc" -r -d fr965 -f monkey.jungle -o "$OUT" -y "$KEY" -w -l ${TYPECHECK:-1} -O 2 "$@"
    ;;
  *)
    echo "usage: ./build.sh [prg|sim|iq|store|release|demo] [extra monkeyc args]"; rm -f resources/properties/properties.xml; exit 2
    ;;
esac
rm -f resources/properties/properties.xml   # never leave the webhook id in the tree
if [ -n "$STORE" ] && [ -n "$(cat webhook_id.txt 2>/dev/null)" ] && grep -q -a "$(cat webhook_id.txt)" "$OUT"; then
  echo "ERROR: the webhook id is inside $OUT"; rm -f "$OUT"; exit 1
fi
case "$TARGET" in
  iq)      ls -la build/Wand.iq ;;
  demo)    ls -la build/Wand-demo.prg ;;
  release) ls -la "$OUT" ;;
  *)       ls -la build/Wand.prg ;;
esac
if [ "$TARGET" = "sim" ] || [ "$TARGET" = "demo" ]; then
  open "$SDK/bin/ConnectIQ.app"
  sleep 3
  [ "$TARGET" = "demo" ] && PRG=build/Wand-demo.prg || PRG=build/Wand.prg
  "$SDK/bin/monkeydo" "$PRG" fr965
fi
