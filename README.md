# Wand

Point your Garmin at a device. Flick your wrist. Home Assistant toggles the device.

Wand is a Connect IQ app for the Forerunner 965. It learns the compass direction of each device
from each place you stand. On a flick, it picks the device you aim at and calls a webhook. If two
devices are too close, it refuses and shows the reason. One key press corrects a wrong pick and
teaches the app.

Credit: the idea comes from the Wear OS app **Snap Control** (r/homeassistant, Sep 2026) and
the iOS app **Maestro Snap**. The Forerunner 965 has no microphone. The finger snap becomes a
wrist flick or the START button.

## Read this first

This is a personal project. I built it for my watch and my Home Assistant. I share the source
because people asked for it. It is not on the Connect IQ Store, and I will not publish it there.
There is no support. I test it only on my Forerunner 965.

Use it with caution. The app sends real commands to real devices: lights, switches, locks,
covers, vacuums, scripts. A wrong match or a stray flick can toggle the wrong device. Anyone on
your LAN with the webhook id can do the same. Test with a lamp first. Keep locks out of the
sync list if you are not comfortable. You build it, you sign it, you run it.

Supported device: Forerunner 965. Other Connect IQ 5.0+ watches with a compass and an
accelerometer can work if you add them to `manifest.xml`. This is not tested.

## How it works

```
watch ──BLE──▶ Garmin Connect (phone, home Wi-Fi) ──HTTPS──▶ reverse proxy ──▶ Home Assistant
                                                              POST /api/webhook/<id>        toggle · sync · ping
                                                              GET  /local/wand/state-<id>.json  device list
```

**Spots.** A spot is a place you stand (Couch, Bed, Desk). Each painted device belongs to one
spot. UP/DOWN changes the spot. A presence sensor or a BLE beacon can change it for you.

**Painting.** Stand on the spot. Point your arm at the device. Press START. Zigzag over the
device for 5 seconds. The app samples the compass at 10 Hz. The centre is the circular mean.
The half-width is the 90th percentile of the spread plus 3°, limited to 5–60°. The app stores
`centre ± half` per spot and device, for example `123° ±14°`.

**Matching.** On a trigger, the app scores each painted arc of the current spot: distance to
the centre minus the half-width. A score of 0 or less means inside the arc. Arcs further out
than **Range** (default 10°) do not count. The best score wins. If the second best is within
**Separation** (default 15°), the app refuses and shows `Lamp / Fan?`. A refusal buzzes twice.

**Correction.** The result screen shows the toggled device. Press DOWN and pick the device you
meant. The app toggles the wrong device back, toggles the right one, and widens its arc to
include this heading.

**Flick.** The accelerometer and gyroscope run at 25 Hz. A flick is a jerk above the threshold
of the chosen sensitivity: 1600 / 1100 / 700 mG (Low / Medium / High), or a gyro axis above
500 / 340 / 220 °/s. Flicks less than 1.5 s apart do not count. The app uses the heading from
300 ms before the flick, before the wrist moved.

**Compass.** The heading comes from `Sensor.Info.heading`. If the watch gives none for 3 s, the
app uses a tilt-compensated heading from the raw magnetometer. The main screen then shows
"raw compass". This heading is not true north, but it is consistent. Headings are smoothed
over 0.4 s.

**Presence spots.** A spot can link to a `person`, a `device_tracker`, or an occupancy, motion
or presence `binary_sensor`. When the app opens, it syncs and jumps to the first spot with a
sensor that is `on` or `home`. This runs at most once a minute.

**Beacon spots.** A spot can link to "Beacon · near" or "Beacon · far". An ESP32 with ESPHome
advertises a fixed BLE service UUID. The watch listens for 3 s and picks the spot from the
signal strength. See `esphome/beacon-example.yaml`.

## The watch and Home Assistant

The watch does not talk to HA. It sends the request to Garmin Connect on the phone over
Bluetooth. The phone makes the HTTPS call. The phone must be on the home Wi-Fi.

All requests are `POST https://ha.example.com/api/webhook/<id>` with a JSON body:

| Body | HA action |
|---|---|
| `{"action":"toggle","entity_id":"light.desk","spot":"Desk"}` | Toggles the entity by domain. Republishes the state file. Fires the event `wand_action`. |
| `{"action":"sync"}` | Writes the state file. |
| `{"action":"ping"}` | Creates the notification "Wand · Watch connected at HH:MM:SS". Then syncs. |

The webhook has `local_only: true`. HA accepts it only from a LAN address. `on` and `off` also
work, but the watch sends only `toggle`.

**Why a webhook.** The watch has no keyboard for a token. A token gives full API access. The
webhook id does only what the automation allows, and only from the LAN.

**The device list.** A webhook cannot return a body. On `sync`, `script.wand_sync` collects the
entities of these domains: light, switch, fan, media_player, cover, lock, scene, script,
input_boolean, button, climate, humidifier, vacuum, siren, valve. It skips `unavailable`
entities. It adds the presence sensors. `wand.py` writes `/config/www/wand/state-<id>.json`.
HA serves this folder at `/local/` without auth. 2.5 s after the POST, the watch does
`GET https://ha.example.com/local/wand/state-<id>.json`.

**Why the id is in the file name.** `/local/` has no auth. The file lists your entities and who
is home. The id in the path makes the file hard to guess.

**Security.** Anyone on your LAN with the webhook id can toggle every listed entity and read the
state file. Use a long random id. Keep HA off the public internet. If you must expose HA,
limit `/api/webhook/<id>` and `/local/wand/` to LAN addresses in the reverse proxy.

## HTTPS is mandatory

Garmin Connect IQ allows `makeWebRequest` only to HTTPS URLs with a certificate from a public
CA. Plain `http://` and self-signed certificates fail with "HTTPS required" (-1001). You cannot
add your own CA to the Garmin phone app.

This setup keeps HA on the LAN and gets a real certificate:

1. A domain you own, with DNS on Cloudflare (or another provider with a Caddy plugin).
2. Caddy in front of HA. Caddy gets a Let's Encrypt certificate with the DNS-01 challenge
   through the Cloudflare API. No port forward is needed. A wildcard certificate
   (`*.example.com`) covers all internal hosts.
3. The name resolves to the LAN IP of the proxy. Use an `A` record with the private IP (DNS
   only, not proxied), or a DNS rewrite in AdGuard Home or Pi-hole.
4. The phone is on the home Wi-Fi. The request reaches Caddy, the certificate is valid, and HA
   sees a LAN address.

Minimal Caddyfile (needs the `cloudflare` DNS module and `CLOUDFLARE_API_TOKEN`):

```caddyfile
ha.example.com {
    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }
    reverse_proxy 192.168.1.10:8123
}
```

HA must trust the proxy, or `local_only` sees the proxy address. In `configuration.yaml`:

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 192.168.1.5        # the proxy
```

## Home Assistant setup

1. Copy `homeassistant/wand.yaml` to `/config/packages/wand.yaml`. If you do not use packages,
   add to `configuration.yaml`:

   ```yaml
   homeassistant:
     packages: !include_dir_named packages
   ```

2. Copy `homeassistant/wand.py` to `/config/bin/wand.py`.
3. Make a webhook id and add it to `/config/secrets.yaml`:

   ```sh
   echo "wand_webhook_id: $(head -c 48 /dev/urandom | base64 | tr -dc a-zA-Z0-9 | head -c 40)"
   ```

   The id must match `^[A-Za-z0-9_-]{8,128}$`. It becomes a file name.
4. Restart HA. Test: Developer Tools → Actions → `script.wand_sync` with `webhook_id: <id>`.
   This must create `/config/www/wand/state-<id>.json`.
5. Optional: flash `esphome/beacon-example.yaml` on an ESP32 for beacon spots. HA needs nothing
   for it.

## Build

Toolchain:

* Connect IQ SDK 9.x from the Garmin SDK Manager. `build.sh` expects it at `~/ciq-sdk`
  (override with `SDK=…`).
* The fr965 device files (SDK Manager → Devices → Forerunner 965).
* Java 17 (`brew install openjdk@17`).

Make a developer key once:

```sh
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
```

Optional defaults: put the webhook id in `webhook_id.txt` and set `HA_URL=https://ha.example.com`
before the build. Without them, set both values in the Connect IQ phone app (app settings:
**Home Assistant URL**, **Webhook id**). `developer_key.*`, `webhook_id.txt`, `build/` and
`resources/properties/` are git-ignored.

```sh
./build.sh          # -> build/Wand.prg
./build.sh sim      # build and run in the simulator
./build.sh iq       # -> build/Wand.iq (store package, with your defaults baked in)
./build.sh store    # -> build/Wand.iq with EMPTY defaults: the one to upload for other people
./build.sh demo     # sample spots and devices in the simulator, for screenshots
TYPECHECK=2 ./build.sh   # strict type check
```

## Install

**USB.** Plug the watch in, unlock it, wait a few seconds. Run `./install.sh` (needs
`brew install libmtp` and `clang` from the Xcode command line tools). `./install.sh build`
rebuilds first. The script compiles `tools/mtpsend.c` once, because `mtp-sendfile` cannot
resolve folder paths on the Forerunner. By hand: open OpenMTP or Android File Transfer, copy
`build/Wand.prg` to `Internal Storage/GARMIN/Apps/` (or `GARMIN/APPS`), eject. On the watch:
START → scroll to "Wand".

**Wireless.** Garmin has no wireless sideload. A private beta on the Connect IQ Store works. It
skips review and is hidden from search. This is your own upload under your own developer
account. There is no official Wand listing.

1. `./build.sh store` (never `iq` for an upload: `iq` bakes your webhook id into the file).
2. Sign in at <https://apps.garmin.com/developer/upload>. Upload `build/Wand.iq`. Fill in the
   name, a description and a screenshot.
3. On the version, choose **Beta**. Garmin shows a beta link.
4. Open the link on the phone. It opens in the Connect IQ app. Tap **Install**.

If you share the beta link, build without `webhook_id.txt` and `HA_URL`. Each user sets their
own values in the app settings.
If you fork this and upload your own build, set a new `iq:application id` UUID in
`manifest.xml`.

## First run

1. Keep Garmin Connect open on the phone. Phone on the home Wi-Fi.
2. Set **Home Assistant URL** and **Webhook id** in the Connect IQ phone app, unless you baked
   them in.
3. On the watch, hold UP (or tap) → **Test connection**. The watch shows "HA answered." and
   buzzes once. HA shows the notification "Wand · Watch connected".
4. Menu → **Sync devices**. The watch shows "Synced N devices".
5. Menu → **Spots → + Add spot**. Pick a name.
6. **Paint device here** → pick a device. Stand on the spot. Aim. Press START. Zigzag over the
   device for 5 s. The watch shows "Saved" and the arc, for example `123° ±14°`. Repeat for each
   device. Paint the same device again from other spots.
7. BACK to the main screen. The ring shows the arcs of the current spot. The arc you aim at
   turns green. Flick or press START. The watch buzzes once and shows "Toggled".

## Keys

Main screen:

| Key | Action |
|---|---|
| START | Fire at the device you aim at |
| Wrist flick | Same, if Trigger = START + wrist flick |
| UP / DOWN | Previous / next spot |
| Hold UP, or tap | Menu |
| BACK | Exit |

A tap opens the menu only. It never fires.

Result screen: DOWN = pick the device you meant. START = close.

Menu: Paint device · Spots (+ Add spot; per spot: Use this spot, Paint device here, Presence
sensor, Painted devices (select = delete), Delete spot) · Sync devices · Test connection ·
Settings.

## Settings

| Setting | Values (default in bold) |
|---|---|
| Trigger | START button only / **START + wrist flick** |
| Flick sensitivity | Low / **Medium** / High |
| Range past edge | 0° / 5° / **10°** / 15° / 20° / 30° |
| Separation | 5° / 10° / **15°** / 20° / 30° |
| Beacon near | -50 / -55 / -58 / **-62** / -65 / -68 dBm |
| Beacon far | -65 / -70 / **-72** / -75 / -80 / -85 dBm |
| Beacon signal | Live RSSI screen |
| HA URL | Shows the URL. Change it in the phone app or rebuild |
| Reset all data | Erases spots, arcs and devices |

All data lives on the watch in `Application.Storage`.

## Beacon spots

A Garmin watch sends no BLE adverts while the phone is connected. A room scanner in HA cannot
see it. Wand does the reverse. The ESP32 advertises a fixed service UUID. The watch listens.
Put the ESP32 next to one of two spots.

1. Spot → **Presence sensor** → **Beacon · near** for the spot next to the ESP32. **Beacon · far**
   for the other spot.
2. Stand at each spot. Open Settings → **Beacon signal**. It shows the average RSSI of each 3 s
   window.
3. Set **Beacon near** and **Beacon far** from those numbers. Keep a gap between them. In the
   gap, the current spot stays.

When the app opens, it listens for 3 s and picks the spot. It listens again every 30 s while the
main screen is up. The watch never connects to the beacon. It scans only while the app is open.

## Troubleshooting

| Message | Cause | Fix |
|---|---|---|
| Set URL | URL or webhook id is empty | Set both in the phone app, or build with `webhook_id.txt` + `HA_URL` |
| Phone not connected (-104) | No link to Garmin Connect | Open Garmin Connect. Check Bluetooth |
| HTTPS required (-1001) | `http://`, or a certificate not from a public CA | Use HTTPS with a Let's Encrypt certificate |
| HA timeout (-300) | The phone cannot reach the URL | Phone on the home Wi-Fi? Does the name resolve to the LAN IP? Proxy up? |
| Webhook not found (404) | HA has no webhook with this id | `wand_webhook_id` in `secrets.yaml` must equal the id on the watch. Restart HA |
| Not local / denied (401 / 403) | HA sees a non-LAN address | Set `use_x_forwarded_for` and `trusted_proxies` |
| Wrong method (405) | The URL is not HA's webhook | Check the path is `/api/webhook/<id>` |
| Bad response (-400 / -1002) | The phone cannot parse the answer | Check the proxy passes the request to HA unchanged |
| Response too big (-402 / -403) | The state file is too large | Reduce `domains` in `script.wand_sync` |
| State file missing | The GET gave 404 | Is `wand.py` in `/config/bin/`? Check the HA log for `shell_command.wand_write` |
| Bad state file | The file has no `devices` array | Delete `/config/www/wand/state-*.json`. Run `script.wand_sync` again |
| Comm error N / HTTP N | Other code | See the Connect IQ `Communications` docs or the proxy log |
| No compass | No heading yet | Move the arm. Calibrate the compass (Settings → Sensors & Accessories → Compass) |
| raw compass | Magnetometer fallback | Harmless. Calibrate the compass if it stays |
| Nothing painted | The spot has no arcs | Paint a device |
| Nothing in range | No arc within Range | Aim closer, raise Range, or paint again |
| `Lamp / Fan?` | Two arcs within Separation | Lower Separation, or paint one device narrower |
| No devices yet | Empty device list | Menu → Sync devices |
| Too few samples | Under 5 compass readings in the sweep | Keep the arm up and moving |
| No presence match | No linked sensor is `on` or `home` | Pick the spot with UP/DOWN |
| Beacon not found | No advert with the Wand UUID in 3 s | Check the ESP32. Come closer |
| Between spots | RSSI is between the thresholds | Widen the thresholds, or move |
| No near spot / No far spot | No spot linked to that zone | Spot → Presence sensor → Beacon · near / far |

HA creates the notification "Wand · Unknown or unavailable entity" for a bad entity, and
"Wand · No handler for …" for a domain without a handler.

## License

MIT. See `LICENSE`.

Written with Claude Code (Claude Opus 5).
