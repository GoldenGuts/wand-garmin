#!/bin/zsh
# Sideload build/Wand.prg onto the Forerunner 965 over USB (MTP).
#   ./install.sh          -> copy the current build to the watch
#   ./install.sh build    -> rebuild first
# Uses libmtp (brew install libmtp). If OpenMTP or Android File Transfer is open, quit it
# first: only one program can hold the MTP connection.
set -e
cd "$(dirname "$0")"
[ "$1" = "build" ] && ./build.sh
PRG=build/Wand.prg
[ -f "$PRG" ] || { echo "no $PRG - run ./build.sh"; exit 1; }

echo "Looking for the watch (plug it in, unlock it)..."
if ! mtp-detect 2>/dev/null | grep -q -i "garmin\|forerunner"; then
  echo "No Garmin MTP device found. Check the cable, or use OpenMTP and copy $PRG to GARMIN/Apps by hand."
  exit 1
fi

# Garmin watches expose the apps folder as GARMIN/Apps (some firmware: GARMIN/APPS).
FOLDERS=$(mtp-folders 2>/dev/null || true)
DEST=""
for cand in "GARMIN/Apps" "GARMIN/APPS" "Apps" "APPS"; do
  if echo "$FOLDERS" | grep -q -i "$(basename "$cand")"; then DEST="$cand"; break; fi
done
[ -n "$DEST" ] || DEST="GARMIN/Apps"
echo "Sending $PRG -> $DEST/Wand.prg"
mtp-sendfile "$PRG" "$DEST/Wand.prg"
echo "Done. Unplug the watch; open START -> Wand."
