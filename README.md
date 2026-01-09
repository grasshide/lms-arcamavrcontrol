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
  - Fixed player output (recommended)

## Install (via “Additional Repositories”)

This repo can be added in the LMS Extensions Manager directly for easy installation. Add the URL: `https://raw.githubusercontent.com/grasshide/lms-arcamavrcontrol/refs/heads/main/public.xml`at the buttom of the plugin page: LMS Web UI → **Settings → Server → Manage Plugins → Additional Repositories**

## Volume scaling

`maxVolume` is an AVR-level cap (0–99). LMS volume (0–100%) is scaled into `0..maxVolume`.

Example: `maxVolume=40`

- LMS 100% → AVR 40
- LMS 50% → AVR 20

## Fixed player output (avoid “double volume”)

If you enable **Force fixed player output**, the plugin forces the LMS player to **fixed 100% output** by setting the server preference `digitalVolumeControl=0` for that player. This avoids having both:

- LMS player attenuation *and*
- AVR volume control

…which can feel like “double volume” and reduces effective resolution at low levels.

When you disable the option (or disable the plugin for that player), the plugin restores the player’s previous `digitalVolumeControl` value.

Note: If you are using the Material Skin client, you must make this change to support 100% volume processing: **Settings → Server → Material Skin → Fixed volume players → 'Display standard volume control'**.


## Debug logging

Enable logging category `plugin.arcamavrcontrol` at DEBUG to see:

- Event triggers (power / playlist / volume)
- Exact bytes sent (hex), connect + write results

## Dev

Create a release:
```bash
VERSION="0.2"
zip -r "ArcamAvrControl-${VERSION}.zip" ArcamAvrControl
shasum -a 1 "ArcamAvrControl-${VERSION}.zip"
```

## Credits / references

- Denon plugin: `https://github.com/SamInPgh/denonavpcontrol`