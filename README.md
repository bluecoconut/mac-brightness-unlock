# Full Mac

Unlock the native brightness range on each compatible Apple XDR display, including the MacBook Pro’s built-in screen and Studio Display XDR.

Full Mac lives in the menu bar. Each screen has its own live brightness reading, boost switch, ambient-light reading, Auto Brightness control, and **Set to 1000 nits** action. The menu keeps the compact controls of Studio XDR Brightness and adds a section for every compatible screen.

## How it works

On the tested M4 Max MacBook Pro and Studio Display XDR, macOS exposes a normal SDR maximum of 600 nits and an Aurora maximum of 1000 nits. Full Mac uses Apple’s private native CoreBrightness / DisplayServices controls to set the Aurora multiplier to the display-reported maximum (1000 / 600, approximately 1.667×). It does not use gamma manipulation or an HDR overlay.

- **Boost** enables the native multiplier while preserving that screen’s brightness slider.
- **Set to 1000 nits** enables boost and moves that screen’s brightness slider to maximum.
- Boost pauses Auto Brightness only on the selected screen. Turning boost off restores that screen’s previous Auto Brightness setting, including after an app relaunch.
- Turning Auto Brightness on explicitly ends manual boost for that screen.
- Screens operate independently, including simultaneous transitions. Displays are identified by UUID; pending operations do not move to another display after disconnection.
- Compatible screens appear and disappear automatically as displays connect or disconnect. A compatible built-in display keeps the menu available without an external monitor.

The numeric brightness readings are macOS telemetry, not measurements from a light meter. Hardware support is detected at runtime; only the two screens documented below have been physically tested. macOS may reset the boost after sleep, reconnection, a preset change, or a brightness adjustment. The app shows the live state rather than silently forcing a persistent override.

## Verified hardware

Tested on November 8, 2026 with a 14-inch MacBook Pro (M4 Max, Mac16,6), macOS 27.2, and a connected Studio Display XDR. Tests exercised the shipping transition methods on both physical displays: each reached a macOS-reported 1000 nits, changing one left the other unchanged, and disabling boost restored each screen’s own original Auto Brightness setting.

See `docs/hardware-verification.log` for the recorded values and assertions. To repeat the physical test, run `make test-hardware` with the built-in display and Studio Display XDR connected. This opt-in test changes brightness, verifies restoration, and leaves both screens boosted.

## Build and test

Requires macOS 26 or newer and Xcode command-line tools.

```sh
make test
make build
open "build/Full Mac.app"
```

The build is ad-hoc signed. Launch at Login and menu-bar visibility remain available in Settings. This update retains the previous app’s bundle identifier to preserve existing preferences and per-display Auto Brightness restoration entries.

Private Apple APIs can change between macOS releases. Full Mac limits requests to each screen’s declared native Aurora range and reports rejected transitions.
