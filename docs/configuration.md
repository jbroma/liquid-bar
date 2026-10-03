# Configuration

liquid-bar reads `~/.config/liquid-bar/config.json`. Every key is optional. A missing key keeps its default, and a missing file means all defaults. The bar reloads the file when it changes. If the new file is invalid, the bar logs the error to stderr and keeps the previous config.

## The Settings window

A right-click, or a Control-click, anywhere on the bar opens LiquidBar's menu below the pointer, in the dropdown glass: **LiquidBar Settings…** and **Quit LiquidBar**. A click outside it or Esc closes it. Opening LiquidBar again while it runs (from Finder, or `open -a LiquidBar`) also opens the Settings window. It is a standard macOS settings window that follows the system appearance, whatever the glass style. Every control in it edits the config file, and an edit to the file shows in the window right away. Its sections:

- **General**: Open at login, which adds the app to macOS's login items and has no config key. Workspaces, Automatic, AeroSpace, Desktops, or Apps (`workspaceSource`). Show Now Playing, which adds `nowPlaying` to the start of `right` or removes it. Show Battery Percentage (`batteryPercent`). The clock as System, 24-Hour, or 12-Hour (`clock24Hour`; System removes the key), and Show Seconds (`clockSeconds`). Permissions: each grant the bar can use, with an icon for its live status (green allowed, orange not asked yet, red not allowed; the words are in the tooltip) and a button that asks or opens its Privacy & Security list (see [Permissions](details.md#permissions)). Configuration: the config file's path, the launch agent that started the bar when one did, **Open Config File…**, which creates the file as `{}` first when it is missing, and **Reload Config**. Last, the version, a link to the GitHub repository, the license, and **Show Welcome and Tips…**, which opens the first-launch window again.
- **Appearance**: Pills, as Separate, Grouped, or None (`pills`), Glass pills (`pillGlass`), and Bar background, as Glass, Black, or None (`background`). With a background, on a Mac with a notch, Curve into the notch (`notchCurve`). Glass blur is a slider (`glassBlur`). Then the four presets (`glassStyle`) as cards, with the default marked, each with a preview of its pill and dropdown at its blur. A click picks one and clears the overrides. Below them, Customize picks the style of the bar's pills (`barStyle`), of the dropdowns (`dropdownStyle`), and of the bar's background (`backgroundStyle`) apart, each from the same four. The background row shows only while Bar background is Glass. The Glass blur slider overrides the preset's blur. While any of them differs from the preset, no card is selected, and Reset removes the four keys.
- **Menu Bar Items**: the pinned apps in bar order (`pinned`). Drag a row to reorder, and its checkbox unpins it. Below them, the other apps' menu bar items, each with a checkbox that pins it.

Each change rewrites the file with sorted keys and keeps every other key.

## Keys

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `margin` | number, at least 0 | `10` | Space between the screen edge and the outer pills. |
| `workspaceSource` | string | `"auto"` | Where the workspace strip's items come from: `"auto"`, `"aerospace"`, `"spaces"`, or `"apps"`. See [Workspaces](details.md#workspaces). |
| `clock24Hour` | boolean | follows the system | `true` shows a 24-hour clock, `false` a 12-hour clock with AM or PM. Without the key the clock follows the region and the 24-hour time setting in System Settings. |
| `clockSeconds` | boolean | `false` | Shows seconds in the clock. |
| `batteryPercent` | boolean | `false` | `true` shows the percentage next to the battery symbol. |
| `pills` | string | `"separate"` | `"separate"` draws each right-side item in its own capsule. `"grouped"` draws one capsule behind each side of the bar: the Apple logo and the workspaces on the left, the pinned items and the widgets on the right. `"none"` draws everything straight on the bar. The focused workspace keeps its selection. Without a capsule of its own, the item under the pointer gets a faint highlight. `true` and `false`, from before the grouped layout, still read as `"separate"` and `"none"`. |
| `pillGlass` | boolean | `true` | The pills and the focused workspace are the bar style's real glass, in a version of each style made for a pill's height. `false` draws the style's flat fill. `glassBlur` applies to the glass. |
| `background` | string | `"none"` | What is behind the whole bar: `"none"` leaves the items over the wallpaper and the windows behind the bar, `"glass"` is a strip in the background style, and `"black"` is solid black. `true` and `false`, from before it could be black, still read as `"glass"` and `"none"`. |
| `notchCurve` | boolean | `true` | On a screen with a notch, a background's lower edge curves up 2 points into the notch's sides, so the bar is slimmer beside the notch. The lit line along the edge follows the curve. It shows only with a background. |
| `glassStyle` | string | `"crystal"` | The preset: the glass of the pills, the dropdowns, the bar's background, the bar's menu, and the Accessibility window, and how much it blurs. `"crystal"`, `"liquid"`, `"frost"`, or `"graphite"`. See [Glass styles](#glass-styles). |
| `barStyle` | string | follows `glassStyle` | The style of the bar's pills, the pinned pill, and the workspace fills. Same names as `glassStyle`. |
| `dropdownStyle` | string | follows `glassStyle` | The style of the dropdowns, the bar's menu, and the Accessibility window. Same names. |
| `backgroundStyle` | string | follows `glassStyle` | The style of the strip behind the bar, in the same glass and light as that style's glass pills, with a lit line along its lower edge. Same names. It shows only while `background` is `"glass"`. |
| `glassBlur` | number, 0 to 1 | follows `glassStyle` | How much the glass blurs what is behind it. `1` is the blur macOS draws, and lower values show more of what is behind. Each preset has its own: `crystal` 0.2, `liquid` 0.5, `frost` 1, `graphite` 1. |
| `workspaces` | array of `{"id"}` | workspaces `1` to `9` | AeroSpace workspace names, in order. |
| `left` | array of widgets | `["apple", "workspaces"]` | Widgets left of the notch. |
| `right` | array of widgets | `["nowPlaying", "volume", "wifi", "battery", "controlCenter", "clock"]` | Widgets right of the notch. |
| `pinned` | array of bundle ids | `[]` | Apps whose menu bar items show on the bar, left of the widgets, in this order. The Settings window's Menu Bar Items pane edits and reorders it. An item that is not pinned stays in the covered menu bar, out of reach until it is pinned. |
| `clicks` | object | see below | Shell command per widget name, run with `/bin/sh -c` on click. Merged over the defaults. |

The default clicks open the Sound, Network, and Battery settings panes for `volume`, `wifi`, and `battery`. The `apple` widget opens its dropdown on hover, and a click runs the command `clicks` sets for it, if any. A click on `controlCenter` opens macOS's Control Center, and on `clock` Notification Center, unless `clicks` sets a command for them.

## Glass styles

| Style | Dropdowns, the bar's menu, the Accessibility window | Pills, the focused workspace, the bar's background | With `pillGlass` off | Blur |
| --- | --- | --- | --- | --- |
| `crystal` | Clear glass with a faint lit rim, which keeps a menu's text readable. | Clear glass, only its fine lit edge. | A 5% white fill with a 30% white outline. | 20% |
| `liquid` | Glass with a bright lit rim, like macOS's volume overlay. | Rich glass with a bright edge. | A flat 14% white fill. | 50% |
| `frost` | Lightened frosted glass with no rim, close to macOS's own menus. | Lightened frosted glass with a soft edge. | A 20% white fill. | 100% |
| `graphite` | Dark frosted glass with a soft lit rim. | Dark frosted glass with the fine edge. | A dark fill. | 100% |

`glassStyle` is the preset: it sets the glass of every part and the blur. `barStyle`, `dropdownStyle`, and `backgroundStyle` each override their part and `glassBlur` the blur, so `{"glassStyle": "liquid", "barStyle": "crystal"}` gives crystal pills with liquid dropdowns. A missing override follows the preset. An unknown name in any of the four is a config error. Versions up to 0.13 had seven styles: `dew` now reads as `liquid`, `pearl` as `crystal`, `mist` as `frost`, and `obsidian` as `graphite`.

Glass does not sit on glass. On a bar with a background, glass or black, a glass pill is a light wash with the lit edge, and only without a background is it glass itself.

`crystal`, `liquid`, and `graphite` use private parts of macOS's glass. If a later macOS drops them, they fall back to plain Liquid Glass. `glassBlur` changes a private setting of the glass too, and without it the glass keeps macOS's own blur.

## Widgets

A widget is one of these names, or a script object.

| Name | At rest | Dropdown on hover |
| --- | --- | --- |
| `apple` | Apple logo. Hover opens the Apple dropdown. | |
| `workspaces` | Each workspace shows a card stack of up to three app icons, the app of its most recently focused window on top and leftmost, then "+N". A workspace without windows shows a dot, which becomes its number while it is focused. No workspace changes width with the focus. | With two or more apps, a list of them, the most recent first, with a dot on the app that holds the focused window. Click one to focus that app's window, switching workspace if needed. Scroll over the strip to step through the workspaces that have windows. Click the focused workspace to see the front app's menus. |
| `nowPlaying` | Artwork and an equalizer, only while Spotify or Music plays and for five minutes after a pause. | Artwork, title, artist, previous, play or pause, next, and a row that opens the player. |
| `volume` | Speaker symbol. Scroll over it to change the volume in steps of 2. | A switch that mutes while off and goes off when the level reaches 0, a slider like Control Center's, the output devices with the current one filled in (click one to switch), paired Bluetooth headphones and speakers that are not connected (click one to connect it and switch to it), AirPlay… (opens the real Control Center on its Sound outputs), and Sound Settings…. |
| `wifi` | Network symbol. | Network name (or the signal, when macOS withholds the name without Location access), IP address, live download and upload speed, and Network Settings…. |
| `battery` | Level symbol, with the percentage if turned on. It is white, also while charging, when a bolt shows beside it, and red at 20% or less on battery. | The percentage and a wide level bar, which while charging is a liquid on its side, with a rolling surface at the end of the fill and bubbles drifting along it. Under it, one line with what the battery is doing and the power source. Battery Health shows the condition and unfolds to the maximum capacity and cycle count. Then a Show Percentage switch and Battery Settings…. |
| `controlCenter` | Control Center symbol, with a moon on its left while a Focus is on. | None. A click opens macOS's own Control Center, which System Settings, Control Center customizes. |
| `clock` | Time. | None. A click opens Notification Center, with its widgets. |

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
