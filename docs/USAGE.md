# Using the camera

## Windows Planetary Deck

Choose a target, open Live Preview, tune brightness and focus through the telescope, close preview, then take a snapshot or record.

| Preset | Starting raw sensor value |
|---|---:|
| Venus | 20 |
| Jupiter | 50 |
| Saturn | 105 |
| Moon | 30 |

These are starting values, not calibrated durations. Telescope aperture, focal ratio, filters and scene brightness all affect the result. Automatic gain/exposure is useful for finding a target; switch to manual for repeatable raw 0–255 control. The panel permits brightness adjustment while preview is running.

Preview uses 640 × 480 at approximately 15 fps in the recorded setup, with an optional crosshair. PNG snapshots use 1280 × 1024 debayered colour. AVI recording uses uncompressed 640 × 480 BGR24, roughly **13.2 MiB/s**, or **791 MiB/minute**, at 15 fps. Allow room for both captures and processing copies.

The camera can perform only one capture operation at a time. Close preview before a snapshot or recording. Do not share it with a second application simultaneously. Stopping a recording intentionally may leave a partial recording; check the resulting file before treating it as a completed capture.

## Native INDIGO

Select **Orion StarShoot** in the Imager Agent, choose **Live 640 × 480**, request `0.01`, then start Preview. Stop preview before changing modes or sensor settings. The exposure field sets a frame wait, not physical shutter duration.

In the camera's device properties, choose **Sensor gain/exposure automation → Manual** before setting **Sensor exposure → Raw units** (0–255). Save the camera configuration to retain the selection. For a still, select **Still 1280 × 1024**, use FITS, set batch count 1 and capture. Select client, local or both upload destinations as appropriate for your application.

FITS is one 8-bit Bayer plane (`BAYERPAT=BGGR`), not three colour planes. Use BGGR debayering in the viewer. `EXPTIME=0`, `EXPVALID=F` and `SHUTTER=UNKNOWN` explicitly mean the integration time is unknown. `SENSRAW` records the raw setting and `WAITSEC` records the requested delay. RAW images retain Bayer metadata, but not every extra FITS keyword.

The adapter uses a fresh stream per capture and discards two initial frames. The tested preview rate is about 3–4 fps. It does not provide AVI/SER recording, calibrated long exposures, dark-shutter operation or on-camera binning/subframes.

## Troubleshooting

- **USB device absent:** check power/cable and USB ID before changing drivers.
- **WSL attached, no video device:** verify the running kernel and matching ov519 modules.
- **Device busy:** close the other capture application; only one path can own the camera.
- **No Windows preview window:** verify WSLg/display availability and inspect the reported ffplay error.
- **Dark or unfocused image:** test response to light; focus needs telescope optics. Software capture success does not establish focus or sky performance.
- **Monochrome checkerboard FITS:** enable BGGR debayering in the image viewer.

Attach a redacted log and platform/version details when reporting a reproducible failure.
