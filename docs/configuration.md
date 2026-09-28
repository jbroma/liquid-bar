# Configuration

liquid-bar reads `~/.config/liquid-bar/config.json`. Every key is optional. A missing key keeps its default, and a missing file means all defaults. The bar reloads the file when it changes. If the new file is invalid, the bar logs the error to stderr and keeps the previous config.

## The LiquidBar submenu

The Apple menu's **LiquidBar** submenu edits the same file. It has these items:

- **Workspaces**: Automatic, AeroSpace, Desktops, or Apps (`workspaceSource`).
- **Clock**: 24-Hour or 12-Hour (`clock24Hour`), and Show Seconds (`clockSeconds`).
- **Show Now Playing**: adds `nowPlaying` to the start of `right`, or removes it.
- **Show Battery Percentage** (`batteryPercent`).
- **Open Config File…** opens the file, and creates it as `{}` first when it is missing.
- **Reload Config** and **Quit LiquidBar**.

Each change rewrites the file with sorted keys and keeps every other key.

## Keys

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `margin` | number, at least 0 | `10` | Space between the screen edge and the outer pills. |
| `workspaceSource` | string | `"auto"` | Where the workspace strip's items come from: `"auto"`, `"aerospace"`, `"spaces"`, or `"apps"`. See [Workspaces](details.md#workspaces). |
| `clock24Hour` | boolean | `true` | `false` shows the clock as 12-hour with AM or PM. |
| `clockSeconds` | boolean | `false` | Shows seconds in the clock. |
| `batteryPercent` | boolean | `true` | `false` shows the battery symbol without the percentage. |
| `workspaces` | array of `{"id"}` | workspaces `1` to `9` | AeroSpace workspace names, in order. |
| `left` | array of widgets | `["apple", "workspaces"]` | Widgets left of the notch. |
| `right` | array of widgets | `["nowPlaying", "volume", "wifi", "battery", "controlCenter", "clock"]` | Widgets right of the notch. |
| `clicks` | object | see below | Shell command per widget name, run with `/bin/sh -c` on click. Merged over the defaults. |

The default clicks open the Sound, Network, and Battery settings panes for `volume`, `wifi`, and `battery`. The `apple` widget opens the Apple menu unless `clicks` sets a command for it. `clock` runs a command only if `clicks` sets one.

## Widgets

A widget is one of these names, or a script object.

| Name | At rest | Dropdown on hover |
| --- | --- | --- |
| `apple` | Apple logo. Click opens the Apple menu. | |
| `workspaces` | Each workspace shows its number and a card stack of up to three app icons, the app of its most recently focused window on top and leftmost, then "+N". Empty workspaces show a dim number. A soft fill marks the focused workspace. | With two or more apps, a list of them, the most recent first, with a dot on the app that holds the focused window. Click one to focus that app's window, switching workspace if needed. Scroll over the strip to step through the workspaces that have windows. Click the focused workspace to see the front app's menus. |
| `nowPlaying` | Artwork and an equalizer, only while Spotify or Music plays and for five minutes after a pause. | Artwork, title, artist, previous, play or pause, next, and a row that opens the player. |
| `volume` | Speaker symbol. Scroll over it to change the volume in steps of 2. | A slider, Mute, the output devices with the current one filled in (click one to switch), AirPlay… (opens the real Control Center on its Sound outputs), and Sound Settings…. |
| `wifi` | Network symbol. | Network name (or the signal, when macOS withholds the name without Location access), IP address, live download and upload speed, and Network Settings…. |
| `battery` | Level symbol and percentage. The symbol is green on power, yellow at 40% or less, and red at 20% or less. | Level meter, power source with the adapter's wattage, time left or to full, condition, maximum capacity, cycle count, and Battery Settings…. |
| `controlCenter` | Control Center symbol. | Control Center without Wi-Fi, Sound, and Now Playing, which have their own pills. See [Control Center](details.md#control-center). |
| `clock` | Time. | The full date over a month grid with week numbers and today marked. Scroll or click the chevrons to change the month. |

## Script widgets

A script object adds a pill whose label is a command's output, like a SketchyBar item.

| Key | Type | Meaning |
| --- | --- | --- |
| `script` | string, required | Command run with `/bin/sh -c`. Its trimmed stdout is the label. |
| `symbol` | string | SF Symbol drawn before the label. |
| `interval` | number, at least 1 | Seconds between runs. Without it, the script runs at load and on events only. |
| `on` | array of strings | Event names that rerun the script. |
| `click` | string | Command run on click. |

To rerun every script whose `on` lists an event, run:

```sh
/Applications/LiquidBar.app/Contents/MacOS/liquid-bar trigger <event>
```

## Example

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
