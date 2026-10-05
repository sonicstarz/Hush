# Hush

A tiny macOS menu bar app for focus. Click the aperture icon (or press **⌃⌥F**) and the window you're working in slides to the center of the screen while everything else blurs and melts into a slowly drifting bokeh background. The menu bar and Dock disappear too.

Click anywhere on the background (or press ⌃⌥F again) to exit — your window slides back to where it was.

## Install

Download `Hush.dmg` from [Releases](../../releases), open it, and drag **Hush** into Applications.

On first launch, allow Hush in **System Settings → Privacy & Security → Accessibility** so it can center windows. Without it you still get the bokeh, but windows won't move.

> The app isn't notarized, so the first time you open it you may need to right-click → **Open**.

## Use

- **Click the menu bar icon** or press **⌃⌥F** — focus on / off
- **Click the background** — exit
- **Right-click the icon** — Open at Login, Quit

## Build from source

Requires Xcode command line tools (macOS 13+).

```sh
./build.sh      # builds and installs to /Applications
./make-dmg.sh   # builds build/Hush.dmg
```
