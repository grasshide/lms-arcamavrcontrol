# Arcam AVR Control (Lyrion Music Server plugin)

Controls an **Arcam AVR380** over the network from **Lyrion Music Server (LMS)**:

- Power on / standby
- Follow player volume (scaled to an AVR max)
- Optional “Direct” mode on power-on

This is a **per-player** plugin: each LMS player can be tied to exactly one receiver.

Protocol reference: Arcam AVR380/450/750 serial/network protocol

## Settings

In **Settings → Player → Arcam AVR Control**, configure:
  - Receiver host/port
  - Max AVR volume (0–99)
  - Power-on-on-play / follow volume / direct-on-power-on

## Install (via “Additional Repositories”)

This repo includes an `extensions.xml` template for LMS’ Extensions Manager. Host it (eg GitHub Pages) and add its URL in:

- LMS Web UI → **Settings → Plugins → Additional Repositories**

## Volume scaling

`maxVolume` is an AVR-level cap (0–99). LMS volume (0–100%) is scaled into `0..maxVolume`.

Example: `maxVolume=40`

- LMS 100% → AVR 40
- LMS 50% → AVR 20

## Debug logging

Enable logging category `plugin.arcamavrcontrol` at DEBUG to see:

- Event triggers (power / playlist / volume)
- Exact bytes sent (hex), connect + write results

## Dev

Create a release:
```bash
VERSION="0.1"
zip -r "ArcamAvrControl-${VERSION}.zip" ArcamAvrControl
shasum -a 1 "ArcamAvrControl-${VERSION}.zip"
````

## Credits / references

- Denon plugin: `https://github.com/SamInPgh/denonavpcontrol`