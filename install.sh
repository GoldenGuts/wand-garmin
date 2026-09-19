#!/bin/zsh
# Sideload build/Wand.prg onto the Forerunner 965 over USB (MTP).
#   ./install.sh          -> copy the current build to the watch
#   ./install.sh build    -> rebuild first
# Uses libmtp (brew install libmtp). If OpenMTP or Android File Transfer is open, quit it
# first: only one program can hold the MTP connection. The watch takes a few seconds to
# show up after you plug it in.
# mtp-sendfile cannot resolve folder paths on the Forerunner ("could not get storage id from
# parent id"), so tools/mtpsend.c sends by folder id instead; it is compiled here on first use.
set -e
cd "$(dirname "$0")"
[ "$1" = "build" ] && ./build.sh
PRG=build/Wand.prg
[ -f "$PRG" ] || { echo "no $PRG - run ./build.sh"; exit 1; }

if [ ! -x build/mtpsend ] || [ tools/mtpsend.c -nt build/mtpsend ]; then
  P=$(brew --prefix libmtp)
  clang -O1 -I"$P/include" -L"$P/lib" -lmtp -o build/mtpsend tools/mtpsend.c
fi

echo "Looking for the watch (plug it in, unlock it)..."
FOLDERS=""
for try in 1 2 3 4 5 6; do
  FOLDERS=$(mtp-folders 2>/dev/null | grep -v "extended association" || true)
  echo "$FOLDERS" | grep -q -i "forerunner\|garmin" && break
  sleep 3
done
# Garmin watches expose the apps folder as GARMIN/Apps (some firmware: GARMIN/APPS).
APPS=$(echo "$FOLDERS" | awk '$2 ~ /^(Apps|APPS)$/ {print $1; exit}')
[ -n "$APPS" ] || { echo "No Garmin MTP device or no Apps folder found. Check the cable, or use OpenMTP and copy $PRG to GARMIN/Apps by hand."; exit 1; }

echo "Sending $PRG -> GARMIN/Apps/Wand.prg (folder id $APPS)"
build/mtpsend "$PRG" Wand.prg "$APPS" 2>&1 | grep -v "extended association"
echo "Done. Unplug the watch; open START -> Wand."
