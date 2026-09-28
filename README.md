# liquid-bar

A macOS 26 menu bar replacement drawn in Liquid Glass. It covers the native menu bar completely. Every item right of the notch is a small glass pill. Hovering one opens a black menu that flows down out of the bar under it, like the native menu extras, and the same menu opens by itself for a moment when something changes, like the volume keys or plugging in the charger.

The pills sit on an opaque pure black bar that runs the full width of the screen. On a notched screen the bar is exactly as tall as the notch, so the notch disappears into it.

Left of the notch, drawn straight on the black: the Apple logo and the AeroSpace workspaces, each showing the icon of its most recently used app. A soft fill marks the focused workspace and flows to the next one like a droplet. Right of the notch, in glass pills: now playing, volume, Wi-Fi, battery, Control Center, and the clock. Control Center's dropdown also lists the other apps' menu bar items.

Requirements: macOS 26, Xcode 26 (Swift 6.2 or later), and [AeroSpace](https://github.com/nikitabobko/AeroSpace) for workspaces.

## Install

```sh
make install
```

`make install` builds `build/LiquidBar.app`, copies it to `/Applications`, and loads the launch agent `Support/dev.liquidbar.plist`, which starts the bar at login and restarts it if it crashes. `make uninstall` reverses all three steps.

Other targets:

- `make app` builds `build/LiquidBar.app` only.
- `make run` stops the launch agent, builds the app and opens it. A newly started bar quits any running one, so repeated runs never stack two bars.
- `make restore` hands the bar back to the launch agent after `make run`.
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

3. Keep the native menu bar visible (System Settings > Control Center > Automatically hide and show the menu bar: Never, or `defaults write NSGlobalDomain _HIHideMenuBar -bool false`). liquid-bar covers it exactly, and it shows again if liquid-bar ever stops. When the pointer touches the top edge, the left side turns into the front app's menus.

4. Run `make install`.

## Permissions

The bar works without any permission. These grants add features, and macOS asks for each the first time it is needed:

- **Accessibility** lets the bar show the front app's menus, open other apps' menu bar items, Screen Mirroring and the real Control Center, and read and switch Focus. Clicking the focused workspace or Control Center… without it explains what is missing and offers to open the Privacy pane.
- **Bluetooth** lets the Control Center dropdown list paired devices, connect them, and switch Bluetooth. macOS asks the first time the dropdown opens.
- **Automation** for Spotify or Music lets the bar ask a running player what is playing at launch and send play, pause, and skip. Track changes arrive without it. Restart…, Shut Down…, and Log Out… in the Apple menu ask `loginwindow` to show its usual confirmation dialog, which can also trigger an Automation prompt.

The Apple menu's Force Quit item lists running apps and force-quits the one you pick. The system Force Quit window can only be opened with a synthesized ⌥⌘⎋ keystroke.

## Configure

liquid-bar reads `~/.config/liquid-bar/config.json`. Every key is optional. A missing key keeps the default, and a missing file means all defaults. The bar reloads the file when it changes. If the new file is invalid, the bar logs the error to stderr and keeps the previous config.

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `margin` | number | `10` | Space between the screen edge and the outer pills. |
| `workspaces` | array of `{"id"}` | workspaces `1` to `9` | AeroSpace workspace names, in order. |
| `left` | array of widgets | `["apple", "workspaces"]` | Widgets left of the notch. |
| `right` | array of widgets | `["nowPlaying", "volume", "wifi", "battery", "controlCenter", "clock"]` | Widgets right of the notch. |
| `clicks` | object | see below | Shell command per widget name, run with `/bin/sh -c` on click. Merged over the defaults. |

The default clicks open the Sound, Network, and Battery settings panes. The `apple` widget opens the Apple menu unless `clicks` sets a command for it. `clock` runs a command only if `clicks` sets one.

### Widgets

A widget is one of these names, or a script object:

| Name | At rest | Dropdown on hover |
| --- | --- | --- |
| `apple` | Apple logo. Click opens the Apple menu. | |
| `workspaces` | Each workspace shows its number and the icon of its most recently used app; empty workspaces show a dim number only. A soft fill marks the focused workspace. | With two or more apps, a black dropdown under the workspace lists them, the most recent first, with a dot on the app holding the focused window. Clicking one focuses that app's window there, switching workspace if needed. Workspaces never change width on hover. Scroll over the strip to step through workspaces that have windows. Click the focused workspace to see its front app's menus. |
| `nowPlaying` | Artwork and an equalizer, only while Spotify or Music plays and for five minutes after a pause. | Artwork, title, artist, previous, play or pause, and next, and a row that opens the player. |
| `volume` | Speaker symbol. | A slider that sets the level on click or drag, Mute, the output devices with the current one filled in (click one to switch), AirPlay… (opens the real Control Center on its Sound outputs, where AirPlay receivers are listed), and Sound Settings…. Scroll over the pill to change the volume in steps of 2. |
| `wifi` | Network symbol. | Network name (or the signal when macOS withholds the name without Location access), IP address, live download and upload speed, and Network Settings…. |
| `battery` | Level symbol and percentage. The symbol is green on power, yellow at 40% or less, and red at 20% or less. | Level meter, power source with the adapter's wattage, time left or to full, condition, maximum capacity and cycle count, and Battery Settings…. |
| `controlCenter` | Control Center symbol. | Control Center without Wi-Fi, Sound and Now Playing, which have their own items. Glass tiles for Bluetooth (on or off; click switches it), AirDrop (who can see this Mac; click opens the AirDrop window), Focus (click turns the active Focus off, or Do Not Disturb on), Screen Mirroring (opens the real Control Center on its list of displays to mirror to), Dark Mode, Night Shift, and Screenshot (opens the Screenshot toolbar). Sliders for the built-in display and keyboard brightness. The paired Bluetooth devices with their battery, filled in while connected; click one to connect or disconnect it. Under Menu Bar Items, the other apps' items in the covered menu bar (Containers, Vault, Launcher, and so on) in the native left-to-right order, each with its app's icon and name; clicking one closes the dropdown and opens that app's own menu. Apple's items and AeroSpace's are left out, since the bar shows them, and the section is hidden when no other app has an item or without Accessibility. The list refreshes when an app launches or quits and each time the dropdown opens. Control Center… opens the real one for the rest. A control this Mac lacks reads Unavailable, and its tile opens the matching settings pane instead. |
| `clock` | Time. | The full date over a month grid with week numbers and today marked. Scroll or the chevrons change the month. |

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

- One dropdown per bar is open at a time. Hovering a pill opens its dropdown after 40 ms, so a fast sweep across the bar does not open every one, and the pill widens by a few points. Once a dropdown is open, moving to another item opens that one at once, like the native menu bar. Each item reacts across the full bar height and up to halfway to its neighbours, and the outermost ones out to the screen edge, so a pointer thrown at the top edge, into a corner, or between two pills still lands on one. The dropdown stays open while the pointer is on the pill or in the dropdown and closes 0.5 s after it leaves both. Moving to another pill morphs the dropdown over to it. A change the bar did not cause, like the volume keys, a new track, plugging in the charger, or a network drop, opens the dropdown for 2.2 s. A dropdown never crosses the notch and stays on screen; one taller than the screen below the bar scrolls.
- The front app's menus: pushing the pointer into the top edge of the screen, or clicking the focused workspace, turns the workspace strip into the front app's menu titles, the app's own menu first and in bold, like the native menu bar. The titles are read through Accessibility. Each title opens a native menu with the app's items, shortcuts, and checkmarks, and picking one runs it in the app. Esc, switching apps, clicking the focused workspace again, or moving the pointer out of the bar brings the workspaces back.
- Height: each screen's bar is exactly as tall as the native menu bar under it, 33 points on a notched screen and 24 on most others. Pills are 8 points shorter. macOS keeps notification banners, Notification Center and windows below the menu bar, so nothing slides under the bar.
- Screens: every screen gets its own bar. Nothing is drawn beside the notch that does not fit there.

Control Center has no public API for most of its controls, so the dropdown uses the private frameworks macOS itself uses, loaded at runtime so a missing one costs a tile, never a crash: DisplayServices for display brightness, CoreBrightness for the keyboard backlight and Night Shift, SkyLight for Dark Mode (no Automation prompt), and `IOBluetoothPreferenceSetControllerPowerState` for Bluetooth power. Focus has neither an API nor a readable store without Full Disk Access, so the Focus tile reads Focus from its menu bar item and switches it by pressing through the real Control Center over Accessibility, which opens Control Center behind the dropdown for about three seconds.

Everything updates from system events: `aerospace subscribe`, IOKit power notifications, CoreAudio property listeners, `NWPathMonitor`, the players' distributed notifications, and Accessibility notifications. At rest the only timer is the clock, which fires on each minute boundary, plus script intervals. Throughput sampling runs only while the Wi-Fi dropdown is open, and Control Center reads its controls only when its dropdown opens, after a change, and on appearance changes while it is open.

## Layout

- `Sources/LiquidBarCore` holds the pure logic: data types, config decoding, AeroSpace and player parsing, the expansion rules, and display formatting. `Tests/LiquidBarCoreTests` covers it.
- `Sources/LiquidBar` is the app: panels, SwiftUI views, the dropdown and its menus, the data sources, and the Apple and app menus.
