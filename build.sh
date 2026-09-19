#!/bin/zsh
# Build Wand for the Forerunner 965.
#   ./build.sh            -> build/Wand.prg (sideload: copy to the watch's GARMIN/Apps)
#   ./build.sh sim        -> build, then start the simulator and run the app in it
#   ./build.sh iq         -> build/Wand.iq, the signed release package for the Connect IQ Store
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
mkdir -p build resources/properties
sed -e "s|__HA_URL__|$HA_URL|" -e "s|__WEBHOOK_ID__|$WEBHOOK_ID|" properties.template.xml > resources/properties/properties.xml
case "$TARGET" in
  iq)
    "$SDK/bin/monkeyc" -e -r -f monkey.jungle -o build/Wand.iq -y "$KEY" -w -l ${TYPECHECK:-1} -O 2 "$@"
    ;;
  prg|sim)
    "$SDK/bin/monkeyc" -d fr965 -f monkey.jungle -o build/Wand.prg -y "$KEY" -w -l ${TYPECHECK:-1} -O 2 "$@"
    ;;
  *)
    echo "usage: ./build.sh [prg|sim|iq] [extra monkeyc args]"; rm -f resources/properties/properties.xml; exit 2
    ;;
esac
rm -f resources/properties/properties.xml   # never leave the webhook id in the tree
if [ "$TARGET" = "iq" ]; then ls -la build/Wand.iq; else ls -la build/Wand.prg; fi
if [ "$TARGET" = "sim" ]; then
  open "$SDK/bin/ConnectIQ.app"
  sleep 3
  "$SDK/bin/monkeydo" build/Wand.prg fr965
fi
