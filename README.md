# liquid-bar

A macOS 26 menu bar replacement drawn in Liquid Glass. It covers the native menu bar completely. Every item is a small glass pill that stays calm at rest, expands on hover, and expands by itself for a moment when something changes, like the volume keys or plugging in the charger. An expanding pill flows into its neighbour and splits off again when it collapses.

Left of the notch: the Apple menu and AeroSpace workspaces with the icons of their apps. The focused workspace sits under a droplet-shaped lens tinted with its front app's icon colour. Right of the notch: now playing, volume, Wi-Fi, battery, and the clock.

Requirements: macOS 26, Xcode 26 (Swift 6.2 or later), and [AeroSpace](https://github.com/nikitabobko/AeroSpace) for workspaces.

## Install

```sh
make install
```

`make install` builds `build/LiquidBar.app`, copies it to `/Applications`, and loads the launch agent `Support/dev.liquidbar.plist`, which starts the bar at login and restarts it if it crashes. `make uninstall` reverses all three steps.

Other targets:

- `make app` builds `build/LiquidBar.app` only.
- `make run` builds the app and opens it. A newly started bar quits any running one, so repeated runs never stack two bars.
- `make test` runs the unit tests.

`make app` signs with the first Apple Development or Developer ID identity in your keychain, so macOS keeps the Accessibility and Automation grants across rebuilds. Without one it signs ad hoc, and every rebuild asks for the grants again. Set `SIGN=` to pick an identity, for example `make app SIGN=-` for ad hoc.

## Migrate from SketchyBar

1. Stop SketchyBar and its helpers. In home-manager, disable the SketchyBar module (or remove the `org.nix-community.home.sketchybar` launch agent) and remove `sketchybar-toggle`, then switch. To stop them for the current session only, run:

	```sh
	launchctl bootout gui/$(id -u)/org.nix-community.home.sketchybar
	pkill -x sketchybar-toggle; pkill -f aerospace_events.sh
	```

2. In `~/.aerospace.toml`, remove the SketchyBar trigger:

	```toml
	after-startup-command = []
	```

	liquid-bar subscribes to AeroSpace itself and retries until AeroSpace is running, so it needs no startup hook.

3. Keep the native menu bar on auto-hide (`defaults write NSGlobalDomain _HIHideMenuBar -bool true`). liquid-bar sits one level above the menu bar. When the pointer touches the top edge, the left side turns into the front app's menus.

4. Run `make install`.

## Permissions

The bar works without any permission. Two grants add features, and macOS asks for each the first time it is needed:

- **Accessibility** lets the bar show the front app's menus and step aside for notification banners. Clicking the focused workspace without it explains what is missing and offers to open the Privacy pane. Banners are detected as soon as access is granted, with no restart.
- **Automation** for Spotify or Music lets the bar ask a running player what is playing at launch and send play, pause, and skip. Track changes arrive without it. Restart…, Shut Down…, and Log Out… in the Apple menu ask `loginwindow` to show its usual confirmation dialog, which can also trigger an Automation prompt.

The Apple menu's Force Quit item lists running apps and force-quits the one you pick. The system Force Quit window can only be opened with a synthesized ⌥⌘⎋ keystroke.

## Configure

liquid-bar reads `~/.config/liquid-bar/config.json`. Every key is optional. A missing key keeps the default, and a missing file means all defaults. The bar reloads the file when it changes. If the new file is invalid, the bar logs the error to stderr and keeps the previous config.

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `height` | number, 24 to 80 | `40` | Bar height in points. Pills are 6 points shorter. |
| `margin` | number | `10` | Space between the screen edge and the outer pills. |
| `workspaces` | array of `{"id"}` | workspaces `1` to `9` | AeroSpace workspace names, in order. |
| `left` | array of widgets | `["apple", "workspaces"]` | Widgets left of the notch. |
| `right` | array of widgets | `["nowPlaying", "volume", "wifi", "battery", "clock"]` | Widgets right of the notch. |
| `clicks` | object | see below | Shell command per widget name, run with `/bin/sh -c` on click. Merged over the defaults. |

The default clicks open the Sound, Network, and Battery settings panes. The `apple` widget opens the Apple menu and `clock` opens the calendar, unless `clicks` sets a command for them.

### Widgets

A widget is one of these names, or a script object:

| Name | At rest | On hover |
| --- | --- | --- |
| `apple` | Apple logo. Click opens the Apple menu. | |
| `workspaces` | Each workspace's number and a stack of its apps' icons, the most recently used on top. The focused workspace sits under a lens tinted with the colour of its front app's icon. Empty workspaces show a dim number. | The stack fans out into a row. Scroll over the strip to step through workspaces that have windows. Click the focused workspace to see its front app's menus. |
| `nowPlaying` | Artwork and an equalizer, only while Spotify or Music plays and for five minutes after a pause. The glass takes the artwork's colour. | Title, artist, and previous, play or pause, and next buttons. |
| `volume` | Speaker symbol. | Output device, level bar, and percentage. Scroll to change the volume in steps of 2. |
| `wifi` | Network symbol. | Network name (or signal bars when macOS withholds the name) and live download and upload speed. |
| `battery` | Level symbol and percentage. The glass is green, yellow at 40% or less, and red at 20% or less. | Time left, or time to full while charging, and a level bar. |
| `clock` | Time. | Date and time with seconds, like "Friday 25 September · 19:58:12". Click opens the calendar. |

A script object is the SketchyBar-style escape hatch:

| Key | Type | Meaning |
| --- | --- | --- |
| `script` | string, required | Command run with `/bin/sh -c`. Its trimmed stdout is the label. |
| `symbol` | string | SF Symbol drawn before the label. |
| `interval` | number, at least 1 | Seconds between runs. Without it, the script runs at load and on events only. |
| `on` | array of strings | Event names that rerun the script. |
| `click` | string | Command run on click. |

`liquid-bar trigger <event>` reruns every script whose `on` lists `<event>`, like `sketchybar --trigger`. Run it as `/Applications/LiquidBar.app/Contents/MacOS/liquid-bar trigger <event>`.

### Example

```json
{
  "workspaces": [{"id": "1"}, {"id": "2"}, {"id": "3"}],
  "left": ["apple", "workspaces"],
  "right": [
    "nowPlaying",
    {"script": "curl -s 'wttr.in?format=%t'", "symbol": "cloud.sun", "interval": 900, "on": ["weather"], "click": "open -a Weather"},
    "volume", "wifi", "battery", "clock"
  ],
  "clicks": {"clock": "open -a Fantastical"}
}
```

## Behavior

- One pill per bar is expanded at a time. Hovering expands a pill after 90 ms, so sweeping the pointer across the bar does not open every pill. It collapses 0.9 s after the pointer leaves. A change the bar did not cause, like the volume keys, a new track, plugging in the charger, or a network drop, expands the pill for 2.2 s. A detail that does not fit beside the notch is left out.
- The front app's menus: pushing the pointer into the top edge of the screen, or clicking the focused workspace, turns the workspace strip into the front app's menu titles, the app's own menu first and in bold, like the native menu bar. The titles are read through Accessibility. Each title opens a native menu with the app's items, shortcuts, and checkmarks, and picking one runs it in the app. Esc, switching apps, clicking the focused workspace again, or moving the pointer out of the bar brings the workspaces back.
- The calendar opens below the clock: a month grid with week numbers and today highlighted. Scroll, the arrow keys, or the chevrons change the month. Esc or a click elsewhere closes it.
- Notification banners: while one is on screen, the right-hand pills slide up out of its way and come back when it leaves. This needs Accessibility access.
- Screens: every screen gets its own bar. Nothing is drawn beside the notch that does not fit there.

Everything updates from system events: `aerospace subscribe`, IOKit power notifications, CoreAudio property listeners, `NWPathMonitor`, the players' distributed notifications, and Accessibility notifications. At rest the only timer is the clock, which fires on each minute boundary, plus script intervals. Throughput sampling and ticking seconds run only while their detail is visible.

## Layout

- `Sources/LiquidBarCore` holds the pure logic: data types, config decoding, AeroSpace and player parsing, colour extraction, the expansion rules, and display formatting. `Tests/LiquidBarCoreTests` covers it.
- `Sources/LiquidBar` is the app: panels, SwiftUI views, the data sources, the calendar, and the Apple and app menus.
