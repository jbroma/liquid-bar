# liquid-bar

A macOS 26 menu bar replacement drawn in Liquid Glass. It shows AeroSpace workspaces on the left and volume, Wi-Fi, battery, clock, and date on the right, and it covers the native menu bar completely. With no config file it reproduces the SketchyBar setup in `~/.config/sketchybar`.

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

3. Keep the native menu bar on auto-hide (`defaults write NSGlobalDomain _HIHideMenuBar -bool true`). liquid-bar sits one level above the menu bar, so the auto-hidden bar never shows through when the pointer touches the top edge.

4. Run `make install`.

## Permissions

The bar needs no permissions for its normal work. Two actions can trigger a permission prompt the first time you use them:

- Clicking the clock opens Notification Center by clicking the clock in Control Center. macOS asks for Accessibility access for LiquidBar.
- **Restart…**, **Shut Down…**, and **Log Out…** in the Apple menu send an Apple event to `loginwindow`, which shows the usual confirmation dialog. macOS can ask whether LiquidBar may control `loginwindow`.

The Apple menu's **Force Quit** item lists running apps and force-quits the one you pick. The system Force Quit window can only be opened with a synthesized ⌥⌘⎋ keystroke, which would need Accessibility access for every user.

## Configure

liquid-bar reads `~/.config/liquid-bar/config.json`. Every key is optional. A missing key keeps the default, and a missing file means all defaults. The bar reloads the file when it changes. If the new file is invalid, the bar logs the error to stderr and keeps the previous config.

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `height` | number, 24 to 80 | `40` | Bar height in points. Glass capsules are 6 points shorter. |
| `margin` | number | `10` | Space between the screen edge and the outer capsules. |
| `workspaces` | array of `{"id", "symbol"}` | workspaces `1` to `9` | AeroSpace workspace names and the SF Symbol drawn for each. |
| `left` | array of widgets | `["apple", "workspaces"]` | Widgets in the left capsule. |
| `right` | array of widgets | `["volume", "wifi", "battery", "clock", "date"]` | Widgets on the right, one capsule each. |
| `clicks` | object | see below | Shell command per widget name, run with `/bin/sh -c` on click. Merged over the defaults. |

The default clicks open the Sound, Network, and Battery settings panes, Notification Center, and Calendar. The `apple` widget opens the Apple menu unless `clicks` sets a command for `apple`.

### Widgets

A widget is one of the names `apple`, `workspaces`, `volume`, `wifi`, `battery`, `clock`, `date`, or a script object:

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
  "workspaces": [
    {"id": "1", "symbol": "terminal"},
    {"id": "2", "symbol": "globe"},
    {"id": "3", "symbol": "apple.terminal"}
  ],
  "right": [
    {"script": "curl -s 'wttr.in?format=%t'", "symbol": "cloud.sun", "interval": 900, "on": ["weather"], "click": "open -a Weather"},
    "volume", "wifi", "battery", "clock", "date"
  ],
  "clicks": {"date": "open -a Fantastical"}
}
```

## Behavior

- Workspaces: the focused workspace has a highlight that slides to the new workspace, and its symbol bounces. Workspaces with windows are brighter than empty ones. When AeroSpace leaves the `main` mode, a badge shows the mode name. Clicking a workspace runs `aerospace workspace <id>`.
- Volume: scroll over the volume capsule to change the volume in steps of 2. Hovering or scrolling widens the capsule to show the level, and it collapses 1.5 seconds after the last interaction.
- Battery: the symbol is green while on AC power, yellow at 40% or less, and red at 20% or less.
- Screens: every screen gets its own bar. On a screen with a notch, the left capsule stays left of the notch and the right capsules stay right of it.

Everything updates from system events: `aerospace subscribe`, IOKit power notifications, CoreAudio property listeners, and `NWPathMonitor`. The only timers are the clock, which fires on each minute boundary, and script intervals.

## Layout

- `Sources/LiquidBarCore` holds the pure logic: data types, config decoding, AeroSpace output parsing, and display rules. `Tests/LiquidBarCoreTests` covers it.
- `Sources/LiquidBar` is the app: panels, SwiftUI views, the data sources, and the Apple menu.
