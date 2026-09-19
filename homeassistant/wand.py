#!/usr/bin/env python3
"""Write the Wand state file that the Garmin watch app downloads.

Called by shell_command.wand_write with two arguments: a base64-encoded JSON document
{"devices": [[entity_id, name, state], ...], "presence": [...], "ts": N} and the webhook id.
The file lands in /config/www/wand/state-<webhook_id>.json, which HA serves without auth at
/local/wand/state-<webhook_id>.json. The id in the file name is the only thing that protects
the list, so keep it long and random. LAN only if your reverse proxy restricts it.

Why base64: shell_command with a template runs without a shell and splits arguments
with shlex, so JSON (spaces, quotes) would be mangled. Base64 is a single safe token.
"""
import base64
import json
import os
import re
import sys

OUT_DIR = "/config/www/wand"
ID_RE = re.compile(r"^[A-Za-z0-9_-]{8,128}$")


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: wand.py <base64-json> <webhook-id>", file=sys.stderr)
        return 2
    hook = sys.argv[2]
    if not ID_RE.match(hook):  # it becomes a file name: letters, digits, - and _ only
        print("wand.py: bad webhook id", file=sys.stderr)
        return 2
    raw = base64.b64decode(sys.argv[1])
    data = json.loads(raw)  # validate before we touch the file
    data.setdefault("devices", [])
    data.setdefault("presence", [])
    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, f"state-{hook}.json")
    tmp = out + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, separators=(",", ":"), ensure_ascii=False)
    os.replace(tmp, out)
    print(json.dumps({"ok": True, "devices": len(data["devices"]), "presence": len(data["presence"])}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
