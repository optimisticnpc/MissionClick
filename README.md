# MissionClick

A small menu bar utility for macOS. Right-click a window preview in Mission Control to close that window.

The right-click interaction in Mission Control has been manually confirmed to work on macOS 26.6. All 13 window-selection checks also pass.

## Start

1. Build the app with `zsh build.sh`, then open `MissionClick.app` in this folder. Keep it in one location after granting permission.
2. Click **Open Accessibility Settings** in its setup window. Enable **MissionClick** under **System Settings → Privacy & Security → Accessibility**. If it is not listed, use the `+` button to add this app.
3. Close the setup window, open Mission Control as usual, and right-click a window preview. On a trackpad, use the normal two-finger secondary click.

The menu bar icon provides an enable toggle, setup instructions, last action status, and Quit. Permission changes are picked up automatically. It does not start automatically at login.

## Behaviour and limits

- Requests a normal window close through the app’s own close button. Save prompts remain under that app’s control.
- Right-clicks outside Mission Control and on empty areas pass through normally. Modifier-right-clicks also pass through.
- Only normal window previews are supported; full-screen Spaces are excluded.
- Matches actual window IDs instead of window titles, including when two windows have identical titles.
- If the previews move during selection, it cancels the action; right-click again after the animation settles.
- An app must expose its window and enabled close button to macOS Accessibility. Some custom app windows may not support it.
- Targets macOS 14–26 using the Dock’s Mission Control surface. Later system versions may require an update.
- Uses the undocumented `_AXUIElementGetWindow` interface; macOS updates can affect compatibility.
- Runs locally with no network requests, telemetry, recording, third-party dependencies, or force-quit behaviour.

## Build

With Xcode or Apple command line developer tools installed:

```sh
git clone https://github.com/optimisticnpc/MissionClick.git
cd MissionClick
zsh build.sh
open MissionClick.app
```

The result is an app built for the current Mac’s CPU, signed locally with an ad hoc signature. The app has not been notarised. Rebuilding changes the binary; macOS may require re-enabling its Accessibility permission. Build caches and test executables stay in `.build/`.

Source files are in `Source/`. To inspect permission and system interface availability without closing any windows, run:

```sh
./MissionClick.app/Contents/MacOS/MissionClick --diagnose
```

Run `zsh test.sh` for 13 selection checks, including Mission Control detection, frontmost overlap ordering, excluded processes, malformed metadata, transparent windows, and coordinates on a secondary display.

## Implementation references

This implementation was written for this request. The use of window IDs, Dock layer 18, and transformed CoreGraphics bounds was checked against the public [CloseUp architecture](https://github.com/oomol-lab/CloseUp/blob/main/docs/DESIGN.md) and its [window representation](https://github.com/oomol-lab/CloseUp/blob/main/Sources/CloseUpKit/MissionControl/WindowInfo.swift).
