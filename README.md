# Wand — point your Garmin at a device, flick, it toggles

Stand where you usually stand, raise your arm at a lamp, flick your wrist (or press START),
and Home Assistant toggles it. Wand is a Connect IQ watch app: it learns which compass
direction each device sits in from each place you use it, and on a flick it picks the device you
are aiming at and fires a webhook. If it is not sure, it refuses and tells you why instead of
guessing. One tap on the result screen corrects a wrong pick and teaches the app for next time.

Credit: this is a Connect IQ port of the idea from the Wear OS app **Snap Control**
(r/homeassistant, Sep 2026) and the iOS app **Maestro Snap**. The Forerunner 965 has no
microphone, so the finger snap of the originals becomes a **wrist flick** or the **START button**.

> **Personal project — read this first**
>
> I built Wand for my own watch and my own Home Assistant. I share the source because people
> asked for it, not because it is a product. It is **not** on the Connect IQ Store and I do not
> plan to publish it there. There is no support, no update channel, and no promise that it works
> on any watch other than my Forerunner 965 with my firmware.
>
> **Use it with caution.** The app fires real actions on real devices (lights, switches, locks,
> covers, vacuums, scripts). A wrong match or a stray wrist flick can toggle the wrong thing.
> Anyone on your LAN who knows the webhook id can do the same. Read the security notes below,
> keep locks and anything dangerous out of the sync list if you are not comfortable with that,
> and test with a lamp first. You build it, you sign it, you run it: it is your responsibility.

Supported device: **Garmin Forerunner 965** (the only product in `manifest.xml`). Other Connect
IQ 5.0+ watches with a compass and an accelerometer should work if you add them to
`manifest.xml`, but that is untested.

## How it works

```
 Forerunner 965 ──BLE──▶ Garmin Connect (phone, on home Wi-Fi) ──HTTPS──▶ reverse proxy ──▶ Home Assistant
   Wand app                                                        (Caddy)
                                                                        POST /api/webhook/<id>      toggle · sync · ping
                                                                        GET  /local/wand/state-<id>.json   device list
```

**Spots.** A spot is a place you stand: Couch, Bed, Desk. Directions only make sense from a fixed
place, so every painted device belongs to one spot. You switch spots with UP/DOWN, or let a
presence sensor pick one (see below).

**Painting.** To teach a device, you stand on the spot, point your arm at it, press START, and
for 5 seconds lazily zigzag over the device, slightly past each edge. The app samples the compass
at 10 Hz, takes the circular mean as the centre, and uses the 90th percentile of the angular
spread (plus 3°, clamped to 5–60°) as the half-width. A percentile rather than the maximum means
one compass glitch during the sweep cannot blow the arc up. The result is stored as
`centre ± half`, for example `123° ±14°`, per (spot, device).

**Matching.** On a trigger, the app takes the current heading and scores every painted arc of the
current spot: distance to the centre minus the half-width, so ≤ 0 means inside the arc. Arcs
further out than **Range** (default +10°) are ignored. The best score wins, unless the runner-up
is within **Separation** (default 15°): then the app refuses with `Lamp / Fan?` instead of
guessing. Refusals buzz twice and show the reason on the main screen.

**Correction that learns.** The result screen shows what was toggled. Press **DOWN** ("Wrong?
DOWN to fix"), pick the device you meant. The app toggles the wrong device back, toggles the
right one, and widens the right one's painted arc so it covers this heading next time.

**Flick detection.** The accelerometer and gyroscope stream at 25 Hz. A flick is a jerk between
two samples above the threshold for the chosen sensitivity (1600 / 1100 / 700 mG for Low /
Medium / High), or any gyro axis above 500 / 340 / 220 °/s. Flicks closer than 1.5 s apart are
ignored. The heading used is the one from about 300 ms *before* the flick, before the wrist
moved, taken from a 3-second heading history.

**Compass.** The heading comes from `Sensor.Info.heading` (the fused compass). If the watch
reports none for 3 seconds the app falls back to a tilt-compensated heading from the raw
magnetometer and accelerometer; the main screen then shows "raw compass". That heading is not
true north, but it is consistent, which is all the matching needs. Headings are smoothed over
0.4 s for display and aiming.

**Presence-linked spots.** Each spot can be linked to a presence sensor from HA (a `person`, a
`device_tracker`, or an occupancy/motion/presence `binary_sensor`). When the app opens (at most
once a minute) it re-syncs and jumps to the first spot whose sensor is `on` or `home`.

**Beacon-linked spots.** Or link two spots to a BLE beacon ("Beacon · near" / "Beacon · far"):
an ESP32 running ESPHome next to one of the spots advertises a fixed service UUID, the watch
listens for 3 s and picks the spot from the signal strength. See `esphome/beacon-example.yaml`.

## How the watch talks to Home Assistant

The watch never talks to HA directly. It hands the request to Garmin Connect on the phone over
Bluetooth, and the phone makes the HTTPS call. The phone must be on the home Wi-Fi.

**Three actions**, all `POST https://ha.example.com/api/webhook/<id>` with a JSON body:

| Body | What HA does |
|---|---|
| `{"action":"toggle","entity_id":"light.desk","spot":"Desk"}` | Toggles the entity by domain (`homeassistant.toggle`, `cover.toggle`, `lock.lock`/`unlock`, `vacuum.start`/`return_to_base`, `scene.turn_on`, `script.turn_on`, `button.press`). Then republishes the state file. Fires the event `wand_action`. |
| `{"action":"sync"}` | Renders the device list and writes the state file. |
| `{"action":"ping"}` | Creates the persistent notification "Wand · Watch connected at HH:MM:SS", then syncs. |

The webhook trigger uses `local_only: true`, so HA only accepts it from a LAN address. `on` and
`off` also work as actions but the watch only sends `toggle`.

**Why a webhook and not a long-lived token.** The watch has no keyboard to type a token into,
and a token would give the watch (and anyone who reads the app settings) full API access. The
webhook id only does what the automation allows, and only from the LAN.

**The device list.** Webhook triggers cannot return a body, so the list goes the other way
round. On `sync`, `script.wand_sync` renders every entity in the domains light, switch, fan,
media_player, cover, lock, scene, script, input_boolean, button, climate, humidifier, vacuum,
siren, valve (skipping `unavailable` ones), plus the presence sensors, and calls
`/config/bin/wand.py`, which writes `/config/www/wand/state-<id>.json`. HA serves that folder
without auth at `/local/…`, so 2.5 seconds after the POST the watch does
`GET https://ha.example.com/local/wand/state-<id>.json`.

**Why the id is in the file name.** `/local/` has no authentication at all, and the file lists
your entities and who is home (`person.*`, `device_tracker.*` states). Putting the webhook id in
the path makes it unguessable; the watch already knows the id, so nothing else is needed.

> **Security note.** Anyone on your LAN who knows the webhook id can toggle every listed entity,
> including locks and covers, and can read the state file. Use a long random id, keep HA off the
> public internet (the reference setup below does not need a port forward), and if you must
> expose HA, restrict `/api/webhook/<id>` and `/local/wand/` to LAN addresses in the reverse
> proxy.

## HTTPS is mandatory

Garmin Connect IQ only allows `makeWebRequest` to **HTTPS** URLs with a certificate from a
**public CA**. Plain `http://` and self-signed certificates fail with "HTTPS required" (code
-1001), and there is no way to add your own CA to the phone's Garmin app.

The reference setup keeps HA on the LAN and still gets a real certificate:

1. **A real domain** you control, with DNS on Cloudflare (any DNS provider Caddy has a plugin
   for works).
2. **Caddy** (or another reverse proxy) in front of HA, with a Let's Encrypt certificate obtained
   through the **DNS-01 challenge**. Caddy proves ownership by creating a DNS TXT record via
   the Cloudflare API, so **no port forward** and no inbound access are needed. A wildcard
   certificate (`*.example.com`) covers every internal host.
3. **The name resolves to the proxy's LAN IP.** Either an `A` record on Cloudflare with the
   private IP (DNS only, not proxied), or a local DNS rewrite in AdGuard Home / Pi-hole so
   `ha.example.com` → `192.168.1.10` inside the house.
4. The phone is on the home Wi-Fi, so `https://ha.example.com` reaches Caddy, the certificate
   is valid, and the request arrives at HA from a LAN address.

Minimal Caddyfile (needs a Caddy build with the `cloudflare` DNS module and
`CLOUDFLARE_API_TOKEN` in the environment):

```caddyfile
ha.example.com {
    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }
    reverse_proxy 192.168.1.10:8123
}
```

HA must trust the proxy so `local_only` sees the phone's LAN address instead of the proxy's.
In `configuration.yaml`:

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 192.168.1.5        # the proxy's IP
```

## Home Assistant setup

1. Copy `homeassistant/wand.yaml` to `/config/packages/wand.yaml`. If you do not use packages
   yet, add this to `configuration.yaml`:

   ```yaml
   homeassistant:
     packages: !include_dir_named packages
   ```

2. Copy `homeassistant/wand.py` to `/config/bin/wand.py` (the package's `shell_command` calls
   `python3 /config/bin/wand.py`).
3. Generate a webhook id and add it to `/config/secrets.yaml`:

   ```sh
   echo "wand_webhook_id: $(head -c 48 /dev/urandom | base64 | tr -dc a-zA-Z0-9 | head -c 40)"
   ```

   The id must match `^[A-Za-z0-9_-]{8,128}$` (it becomes a file name). Keep it: you will type
   it into the watch app settings, or put it in `webhook_id.txt` for the build.
4. Restart Home Assistant. Developer Tools → Actions → `script.wand_sync` with
   `webhook_id: <your id>` should create `/config/www/wand/state-<id>.json`.
5. Optional: `esphome/beacon-example.yaml` turns any ESP32 running ESPHome into a BLE beacon
   for automatic spot detection (see "Beacon-linked spots" below). Nothing is needed in HA
   for it.

## Build the watch app

Toolchain:

* Connect IQ SDK 9.x (install with Garmin's SDK Manager; `build.sh` expects it at `~/ciq-sdk`,
  override with `SDK=…`).
* The **fr965** device files, downloaded once in the SDK Manager (Devices → Forerunner 965).
* Java 17 (`brew install openjdk@17` on macOS; `build.sh` adds it to `PATH`).

Generate a developer key (once, kept out of git):

```sh
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
```

Optional defaults baked into the app: put your webhook id in `webhook_id.txt` and export
`HA_URL=https://ha.example.com` before building. Without them the app starts unconfigured and
you set both values in the Connect IQ phone app (Settings of the installed app: **Home Assistant
URL** and **Webhook id**). `developer_key.*`, `webhook_id.txt`, `build/` and the generated
`resources/properties/` are git-ignored.

```sh
./build.sh          # -> build/Wand.prg  (sideload)
./build.sh sim      # build, start the simulator, run the app on a virtual fr965
./build.sh iq       # -> build/Wand.iq   (signed release package for the Connect IQ Store)
TYPECHECK=2 ./build.sh   # stricter Monkey C type checking
```

## Install on the watch

### A. USB sideload

Fastest: plug the watch in, unlock it, wait a few seconds, run `./install.sh` (needs
`brew install libmtp` and the Xcode command line tools for `clang`; `./install.sh build`
rebuilds first). It compiles `tools/mtpsend.c` once, because `mtp-sendfile` cannot resolve
folder paths on the Forerunner. By hand:

1. Plug the watch into the computer with its USB cable.
2. Open OpenMTP (macOS) or Android File Transfer. The watch shows up as an MTP device.
3. Copy `build/Wand.prg` into `Internal Storage/GARMIN/Apps/` (some firmware: `GARMIN/APPS`; use
   the folder that already holds `.prg` files).
4. Eject and unplug. On the watch: **START → scroll to "Wand"**. Connect IQ apps sit in the
   activity list; you can add it to the favourites via Settings → Activities & Apps.

### B. Wireless, via a private Connect IQ Store beta

Garmin has no wireless sideload, but a beta app on the store skips review, is hidden from
search, and installs from the phone. This is a private upload under **your own** developer
account for **your own** watch; there is no official Wand listing and there will not be one.

1. `./build.sh iq` → `build/Wand.iq`.
2. Sign in at <https://apps.garmin.com/developer/upload> (a free Garmin developer account) and
   upload the `.iq`. Fill in name, description and a screenshot.
3. On the app's version, choose **Beta**. Garmin shows a beta link.
4. Open the beta link on the phone. It opens in the **Connect IQ** app. Tap **Install**. The watch
   gets the app on the next Bluetooth sync. New versions update the same way.

If you share the beta link, build **without** `webhook_id.txt` and `HA_URL`: the package would
otherwise carry your id and URL. Each user then enters their own in the Connect IQ app settings.

## First run

1. Keep Garmin Connect open and paired on the phone, phone on the home Wi-Fi.
2. If you did not bake in the defaults: in the Connect IQ phone app, open Wand → Settings and
   fill **Home Assistant URL** (`https://ha.example.com`, no trailing slash needed) and
   **Webhook id**.
3. On the watch, hold **UP** (or tap the screen) → **Test connection**. The screen shows
   "Pinging HA…", then "HA answered. Check the HA notification." and the watch buzzes once. HA
   shows the notification "Wand · Watch connected at …".
4. Menu → **Sync devices**. "Asking HA…" then "Synced N devices / M presence sensors".
5. Menu → **Spots → + Add spot**. Pick a preset (Couch, Bed, Desk, Kitchen, Dining, Door,
   Bathroom, Balcony, Hall, TV) or "Spot N". The spot menu opens.
6. **Paint device here** (or Menu → **Paint device** for the current spot) → pick a device from
   the list. Stand on the spot, raise your arm at the device, press **START** ("START = paint
   5 s"), and zigzag over it for 5 seconds ("Sweep… 5"). "Saved" and a double buzz; the screen
   shows the arc, e.g. `123° ±14°`. Repeat for every device from that spot; paint the same device
   again from other spots.
7. BACK to the main screen. The ring shows the painted arcs of the current spot, heading-up;
   the arc you are aiming at turns green and the device name appears in the middle. **Flick**
   the wrist or press **START** → one buzz → the result screen says "Toggled". It closes by
   itself after 2.5 s.

## Keys and screens

Main screen:

| Key | Action |
|---|---|
| START | Fire at the device you are aiming at |
| Wrist flick | Same (when Trigger = START + wrist flick) |
| UP / DOWN | Previous / next spot |
| Hold UP, or tap the screen | Menu |
| BACK | Exit the app |

A tap never fires a device, only opens the menu, so a brush of the touchscreen is safe.

Result screen (after a trigger): **DOWN** = "Wrong? DOWN to fix" → pick the device you meant;
**START** = close now.

Paint screen: **START** starts the 5-second sweep; **BACK** is ignored during the sweep.

Menu: **Paint device** · **Spots** (list, `+ Add spot`; each spot: Use this spot, Paint device
here, Presence sensor, Painted devices (select = delete), Delete spot) · **Sync devices** ·
**Test connection** · **Settings**.

Settings:

| Setting | Values (default in bold) |
|---|---|
| Trigger | START button only / **START + wrist flick** |
| Flick sensitivity | Low (1600 mG, 500 °/s) / **Medium (1100 mG, 340 °/s)** / High (700 mG, 220 °/s) |
| Range past edge | 0° / 5° / **10°** / 15° / 20° / 30° |
| Separation | 5° / 10° / **15°** / 20° / 30° |
| Beacon near | -50 / -55 / -58 / **-62** / -65 / -68 dBm (stronger = the near spot) |
| Beacon far | -65 / -70 / **-72** / -75 / -80 / -85 dBm (weaker = the far spot) |
| Beacon signal | Live RSSI screen for tuning the two thresholds |
| HA URL | Shows the current URL; change it in the Connect IQ app settings, or rebuild |
| Reset all data | Erases spots, paints and the device list (asks "Erase all Wand data?") |

All data lives on the watch in `Application.Storage`. Nothing is stored on the phone or in HA
except the state file.

## Presence-linked spots

Spot → **Presence sensor** → pick a `person.*`, a `device_tracker.*`, or an occupancy / motion /
presence `binary_sensor` (the list comes from the last sync). When the app opens and at least
one spot is linked, it shows "Locating…", syncs, and switches to the first spot whose sensor is
`on` or `home`; otherwise "No presence match" and the current spot stays. This runs at most
once a minute. Without links you switch spots with UP/DOWN.

## Beacon-linked spots

A Garmin watch sends no BLE adverts while it is connected to the phone, so a room scanner in
HA (ESPresense, `esp32_ble_tracker`) never sees it. Wand does the reverse: an ESP32 running
ESPHome advertises a fixed BLE service UUID (`esphome/beacon-example.yaml`, six lines of
`esp32_ble_server`), and the watch listens for it. Put the ESP32 next to one of two spots.

1. Spot → **Presence sensor** → **Beacon · near** for the spot next to the ESP32, and
   **Beacon · far** for the other spot.
2. Stand at each spot and open Settings → **Beacon signal**. It scans back to back and shows
   the average RSSI of each 3 s window (green = a zone, orange = between the thresholds, red =
   not found).
3. Set Settings → **Beacon near** (default -62 dBm) and **Beacon far** (default -72 dBm) from
   those numbers. Keep a gap between them: in the gap the current spot stays (hysteresis).

When the app opens and a spot is linked to the beacon, the aim screen shows "Locating…", listens
for 3 s, and picks the spot. It listens again every 30 s while the aim screen is up, so a walk
from one spot to the other changes the spot by itself. The hint line shows the last RSSI. The
watch never connects to the beacon, and it scans only while the app is open. Status texts:
"Beacon not found", "Between spots", "No near spot" / "No far spot" (no spot linked to that zone).

## Troubleshooting

| Message | Cause | Fix |
|---|---|---|
| Set URL / Set URL in settings | URL or webhook id empty on the watch | Fill both in the Connect IQ phone app settings, or build with `webhook_id.txt` + `HA_URL` |
| Phone not connected (-104) | The watch cannot reach Garmin Connect | Open Garmin Connect on the phone, check Bluetooth |
| HTTPS required (-1001) | URL is `http://`, or the certificate is not from a public CA | Use `https://` and a Let's Encrypt (or similar) certificate; see "HTTPS is mandatory" |
| HA timeout (-300) | The phone could not reach the URL | Phone on the home Wi-Fi? Does `ha.example.com` resolve to the LAN IP there? Proxy up? |
| Webhook not found (404) | HA has no webhook with this id | `wand_webhook_id` in `secrets.yaml` must equal the id on the watch; restart HA after changing it |
| Not local / denied (401 / 403) | HA rejected the call as non-local | Set `use_x_forwarded_for` + `trusted_proxies`; make sure the phone is on the LAN |
| Wrong method (405) | Something answered the URL but not HA's webhook | Check the URL path is `/api/webhook/<id>` (the app builds it from the base URL) |
| Bad response (-400 / -1002) | The proxy or HA returned something the phone could not parse | Check the proxy passes the request straight to HA |
| Response too big (-402 / -403) | The state file is too large for the watch | Reduce the entity count, e.g. limit `domains` in `script.wand_sync` |
| State file missing | The sync POST succeeded but `/local/wand/state-<id>.json` gave 404 | Is `wand.py` at `/config/bin/`? Check the HA log for `shell_command.wand_write` errors; the id must match `^[A-Za-z0-9_-]{8,128}$` |
| Bad state file | The file exists but has no `devices` array | Delete `/config/www/wand/state-*.json` and run `script.wand_sync` again |
| Comm error N / HTTP N | Any other Connect IQ or HTTP code | Look the code up in the Connect IQ `Communications` docs / the proxy log |
| No compass | The watch has no heading yet | Move the arm; calibrate the compass (watch Settings → Sensors & Accessories → Compass) |
| raw compass (main screen) | Fused heading unavailable, using the magnetometer fallback | Harmless; paint and aim the same way. Calibrate the compass if it never goes away |
| No spot (menu) | No spot exists yet | Menu → Spots → + Add spot |
| Nothing painted | The current spot has no painted devices | Paint a device from this spot |
| Nothing in range | No painted arc within Range of this heading | Aim closer, raise Range, or paint the device again |
| `Lamp / Fan?` | Two arcs are within Separation of each other | Lower Separation, repaint one device narrower, or move the spot |
| No devices yet | Device list empty | Menu → Sync devices |
| Too few samples | Fewer than 5 compass readings in the sweep | Keep the arm up and moving; wait for "No compass yet" to clear before START |
| No presence match | No linked sensor is `on` / `home` | Pick the spot with UP/DOWN, or check the sensor in HA |
| Beacon not found | No advert with the Wand service UUID in 3 s | Check the ESP32 is up and advertises (a phone BLE scanner app shows it as its ESPHome name); come closer |
| Between spots | RSSI is between the near and far thresholds | Widen the thresholds in Settings, or move; the current spot stays |
| No near spot / No far spot | RSSI is in a zone, but no spot is linked to it | Spot → Presence sensor → Beacon · near / far |

HA side: a bad or unavailable entity creates the persistent notification "Wand · Unknown or
unavailable entity …"; a domain with no handler creates "Wand · No handler for …".

## Files

| File | What |
|---|---|
| `source/WandApp.mc` | App entry point; loads and saves the store |
| `source/AimView.mc` | Main screen: compass ring, painted arcs, keys, trigger |
| `source/Aim.mc` | Compass polling, magnetometer fallback, flick detector, paint sampling |
| `source/Store.mc` | Persistence (`Application.Storage`), spots / targets / devices, matching and arc maths |
| `source/Ha.mc` | Webhook POST, state file GET, error texts |
| `source/PaintView.mc` | The 5-second paint sweep |
| `source/ResultView.mc` | After-trigger screen, correction that learns |
| `source/Menus.mc` | All menus, settings, message screen, beacon signal screen |
| `source/Beacon.mc` | BLE beacon scan and near / far zones |
| `manifest.xml`, `monkey.jungle` | Connect IQ app manifest (fr965, permissions Communications + Sensor + BluetoothLowEnergy) and project file |
| `resources/settings/settings.xml` | The two Connect IQ app settings: Home Assistant URL, Webhook id |
| `resources/strings/strings.xml`, `resources/drawables/` | App name and launcher icon |
| `properties.template.xml` | `haUrl` / `webhookId` defaults, filled in by `build.sh` at build time |
| `build.sh`, `install.sh`, `tools/mtpsend.c` | Build (`prg` / `sim` / `iq`) and USB sideload (libmtp sender by folder id) |
| `homeassistant/wand.yaml` | HA package: webhook automation, sync script, shell command |
| `homeassistant/wand.py` | Writes `/config/www/wand/state-<id>.json` |
| `esphome/beacon-example.yaml` | Optional: ESPHome BLE beacon for automatic spot detection |
| `developer_key.*`, `webhook_id.txt` | Local secrets, git-ignored, never commit |

If you fork this and upload your own build to the Connect IQ Store, give it a new
`iq:application id` UUID in `manifest.xml`.

## License

MIT, see `LICENSE`.
