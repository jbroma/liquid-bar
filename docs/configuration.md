# Configuration

liquid-bar reads `~/.config/liquid-bar/config.json`. Every key is optional. A missing key keeps its default, and a missing file means all defaults. The bar reloads the file when it changes. If the new file is invalid, the bar logs the error to stderr and keeps the previous config.

## The Settings window

A right-click, or a Control-click, anywhere on the bar opens LiquidBar's menu below the pointer, in the dropdown glass: **LiquidBar Settings…** and **Quit LiquidBar**. A click outside it or Esc closes it. Opening LiquidBar again while it runs (from Finder, or `open -a LiquidBar`) also opens the Settings window. It is a standard macOS settings window that follows the system appearance, whatever the glass style. Every control in it edits the config file, and an edit to the file shows in the window right away. Its sections:

- **General**: Workspaces, Automatic, AeroSpace, Desktops, or Apps (`workspaceSource`). Show Now Playing, which adds `nowPlaying` to the start of `right` or removes it. Show Battery Percentage (`batteryPercent`). The clock as System, 24-Hour, or 12-Hour (`clock24Hour`; System removes the key), and Show Seconds (`clockSeconds`). Permissions: each grant the bar can use, with an icon for its live status (green allowed, orange not asked yet, red not allowed; the words are in the tooltip) and a button that asks or opens its Privacy & Security list (see [Permissions](details.md#permissions)). Configuration: the config file's path, whether a launch agent started the bar, **Open Config File…**, which creates the file as `{}` first when it is missing, and **Reload Config**. Last, the version, a link to the GitHub repository, and the license.
- **Appearance**: Pills, as Separate, Grouped, or None (`pills`), and Bar background, as Glass, Black, or None (`background`). With a background, on a Mac with a notch, Curve into the notch (`notchCurve`). Glass blur is a slider (`glassBlur`). Then the seven glass styles (`glassStyle`) as cards, each with a preview of a bar pill and a dropdown. A click picks one and clears the overrides. Below them, Customize picks the style of the bar's pills (`barStyle`), of the dropdowns (`dropdownStyle`), and of the bar's background (`backgroundStyle`) apart, each from the same seven. The background row shows only while Bar background is Glass. While any differs from the preset, no card is selected, and Reset removes the three keys.
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
| `pills` | string | `"separate"` | `"separate"` draws each right-side item in its own capsule. `"grouped"` draws one capsule behind each side of the bar: the Apple logo and the workspaces on the left, the pinned items and the widgets on the right. `"none"` draws everything straight on the bar, with a line under the focused workspace. Without a capsule of its own, the item under the pointer gets a faint highlight. `true` and `false`, from before the grouped layout, still read as `"separate"` and `"none"`. |
| `background` | string | follows `pills` | What is behind the whole bar: `"glass"` is a strip in the background style, `"black"` is solid black, and `"none"` leaves the items over the wallpaper and the windows behind the bar. Without the key, grouped pills have none and the other layouts have glass. `true` and `false`, from before it could be black, still read as `"glass"` and `"none"`. |
| `notchCurve` | boolean | `false` | On a screen with a notch, the background's lower edge curves up 2 points into the notch's sides, so the bar is slimmer beside the notch and the notch stands out of it. A lit rim follows the curve. It needs a background. |
| `glassStyle` | string | `"liquid"` | The glass of the dropdowns, the pills, the bar's menu, and the Accessibility window: `"liquid"`, `"dew"`, `"pearl"`, `"crystal"`, `"frost"`, `"mist"`, or `"obsidian"`. See [Glass styles](#glass-styles). |
| `barStyle` | string | follows `glassStyle` | The style of the bar's pills, the pinned pill, and the workspace fills. Same names as `glassStyle`. |
| `dropdownStyle` | string | follows `glassStyle` | The style of the dropdowns, the bar's menu, and the Accessibility window. Same names. |
| `backgroundStyle` | string | follows `glassStyle` | The style of the strip behind the bar, drawn in that style's dropdown glass. Same names. It shows only while `background` is `"glass"`. |
| `glassBlur` | number, 0 to 1 | `1` | How much the glass of the dropdowns and of the bar's background blurs what is behind it. `1` is the blur macOS draws, and lower values show more of what is behind. `0` leaves only a little softness. |
| `workspaces` | array of `{"id"}` | workspaces `1` to `9` | AeroSpace workspace names, in order. |
| `left` | array of widgets | `["apple", "workspaces"]` | Widgets left of the notch. |
| `right` | array of widgets | `["nowPlaying", "volume", "wifi", "battery", "controlCenter", "clock"]` | Widgets right of the notch. |
| `pinned` | array of bundle ids | `[]` | Apps whose menu bar items show on the bar, left of the widgets, in this order. The pin button on a row of Control Center's Menu Bar Items section edits it, and so does the Settings window, which also reorders it. |
| `clicks` | object | see below | Shell command per widget name, run with `/bin/sh -c` on click. Merged over the defaults. |

The default clicks open the Sound, Network, and Battery settings panes for `volume`, `wifi`, and `battery`. The `apple` widget opens its dropdown on hover, and a click runs the command `clicks` sets for it, if any. `clock` runs a command only if `clicks` sets one.

## Glass styles

| Style | Dropdowns, the bar's menu, the Accessibility window | Pills and the focused workspace |
| --- | --- | --- |
| `liquid` | Glass with a bright lit rim, like macOS's volume overlay. | A flat 14% white fill. |
| `dew` | A third of the way from `liquid` to `crystal`: `liquid` at 67% opacity over `crystal`. | An 11% white fill with a 10% white outline. |
| `pearl` | Two thirds of the way: `liquid` at 33% opacity over `crystal`. | An 8% white fill with a 20% white outline. |
| `crystal` | The clearest glass, showing the most of what is behind. | A 5% white fill with a 30% white outline. |
| `frost` | Heavy frosted glass that blurs away what is behind. | Liquid Glass. |
| `mist` | Soft, light glass with gentle contrast. | A brighter 26% white fill. |
| `obsidian` | Dark tinted glass. | A dark fill. |

`glassStyle` is the preset. `barStyle`, `dropdownStyle`, and `backgroundStyle` each override their part of it, so `{"glassStyle": "liquid", "barStyle": "crystal"}` gives crystal pills over a liquid background, with liquid dropdowns. A missing override follows `glassStyle`. An unknown name in any of the four is a config error.

`liquid`, `dew`, `pearl`, and `mist` use private parts of macOS's glass. If a later macOS drops them, they fall back to plain Liquid Glass. `glassBlur` changes a private setting of the glass too, and without it the glass keeps macOS's own blur.

## Widgets

A widget is one of these names, or a script object.

| Name | At rest | Dropdown on hover |
| --- | --- | --- |
| `apple` | Apple logo. Hover opens the Apple dropdown. | |
| `workspaces` | Each workspace shows its number and a card stack of up to three app icons, the app of its most recently focused window on top and leftmost, then "+N". Empty workspaces show a dim number. A soft fill marks the focused workspace. | With two or more apps, a list of them, the most recent first, with a dot on the app that holds the focused window. Click one to focus that app's window, switching workspace if needed. Scroll over the strip to step through the workspaces that have windows. Click the focused workspace to see the front app's menus. |
| `nowPlaying` | Artwork and an equalizer, only while Spotify or Music plays and for five minutes after a pause. | Artwork, title, artist, previous, play or pause, next, and a row that opens the player. |
| `volume` | Speaker symbol. Scroll over it to change the volume in steps of 2. | A slider, Mute, the output devices with the current one filled in (click one to switch), AirPlay… (opens the real Control Center on its Sound outputs), and Sound Settings…. |
| `wifi` | Network symbol. | Network name (or the signal, when macOS withholds the name without Location access), IP address, live download and upload speed, and Network Settings…. |
| `battery` | Level symbol and percentage. The symbol is green on power, yellow at 40% or less, and red at 20% or less. | Level meter, power source with the adapter's wattage, time left or to full, condition, maximum capacity, cycle count, and Battery Settings…. |
| `controlCenter` | Control Center symbol, with a moon on its left while a Focus is on. | Control Center without Wi-Fi, Sound, and Now Playing, which have their own pills. See [Control Center](details.md#control-center). |
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
