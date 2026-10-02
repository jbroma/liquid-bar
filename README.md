<p align="center">
  <img src="docs/images/hero-v080b.webp" width="100%" alt="Banner: A Liquid Glass menu bar for macOS. The whole bar over a violet and blue wallpaper, with the Apple logo and workspaces 1 to 9 on the left, pinned menu bar items, volume, Wi-Fi, battery, Control Center, and the clock on the right, and the top of the Control Center dropdown open below it">
</p>

## What you get

<img src="docs/images/workspaces-v080c.webp" width="100%" alt="Banner: Workspaces and menus. Workspace 2's dropdown lists Google Chrome, 1Password, and Xcode, and next to it the strip shows the front app's menus, Studio, File, Edit, View, Window, and Help, with the top of the Edit menu open">

<img src="docs/images/control-center-v080c.webp" width="100%" alt="Banner: Control Center. Two Control Center dropdowns, one at rest and one with the AirDrop section unfolded to Contacts Only and Everyone, each showing Bluetooth, AirDrop, Focus, and the display and keyboard brightness sliders">

<img src="docs/images/styles-v080c.webp" width="100%" alt="Banner: Seven glass styles. The top of the battery dropdown in four styles side by side, Liquid, Crystal, Mist, and Obsidian">

<img src="docs/images/clock-battery-v080c.webp" width="100%" alt="Banner: Clock, battery, and Wi-Fi. The clock dropdown with the full date and a month calendar, and the battery dropdown with power source, status, condition, cycle count, and a Show Percentage switch">

Also in the bar:

- Now playing for Spotify and Music. On a new track the pill slides out to show the title.
- The Apple logo opens a dropdown with the Apple menu's items.
- A right-click on the bar opens LiquidBar's menu: Settings and Quit.
- The native menu bar stays hidden while the bar runs.

## Install

Download `LiquidBar-<version>.zip` from [Releases](https://github.com/jbroma/liquid-bar/releases), unzip it, and move `LiquidBar.app` to `/Applications`. It is signed with a Developer ID and notarized by Apple, so it opens like any other downloaded app.

A downloaded copy updates itself. It checks for a new release once a day and asks before installing it. "Check for Updates…" in the bar's right-click menu checks right away, and Settings, General turns the daily check off. A copy installed with Nix leaves updates to your Nix configuration. [Updates](docs/details.md#releases-and-updates) has the details.

To start it at login, copy [`Support/dev.liquidbar.plist`](Support/dev.liquidbar.plist) to `~/Library/LaunchAgents/` and run:

```sh
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/dev.liquidbar.plist
```

To build from source instead, run `make install` (needs Xcode 26). It installs the app and the launch agent. [Building from source](docs/details.md#build-from-source) lists the other `make` targets.

## Requirements

- macOS 26 or later.
- Menu bar auto-hide off (System Settings, "Automatically hide and show the menu bar", Never). With auto-hide on, windows and notification banners can slide under the bar.
- Accessibility access, for the front app's menus, other apps' menu bar items, and a few Control Center tiles. The bar runs without it. On first launch it is the only thing the bar asks for; every other grant is asked for when you first use what needs it. Settings, General lists each grant with its live status. [Permissions](docs/details.md#permissions) lists every grant.
- [AeroSpace](https://github.com/nikitabobko/AeroSpace) is optional.

## Settings

Right-click the bar and choose **LiquidBar Settings…**, or open LiquidBar again while it runs. The Settings window has three sections. General holds the workspace source, now playing, the battery percentage, the clock format, each permission's status, the config file, and the version. Appearance sets the pills as separate, grouped, or none, in real glass or flat, the bar's background, and how much the glass blurs. It picks the look from four presets with a live preview, and Customize sets the glass of the pills, the dropdowns, and the background apart. Menu Bar Items pins other apps' menu bar items to the bar and reorders them by drag.

<p align="center">
  <img src="docs/images/settings-v0120.webp" width="480" alt="The Settings window on its Appearance pane, with the General, Appearance, and Menu Bar Items panes in the sidebar: the Pills picker, the Glass pills switch, the Bar background picker, the Glass blur slider, and seven glass preset cards over a busy preview backdrop">
</p>

Everything else, like widget order, click commands, and script widgets, lives in `~/.config/liquid-bar/config.json`. See [Configuration](docs/configuration.md).

## How it works

The bar uses private macOS frameworks (SkyLight, DisplayServices, CoreBrightness) where no public API exists. A macOS update can break one of those features, but the bar loads each one at runtime, so a missing framework costs that feature and never crashes the bar. While the bar runs, the native menu bar is invisible. If the bar quits, macOS brings the native menu bar back. [Details](docs/details.md) covers behavior, permissions, and migrating from SketchyBar.

## License

MIT. See [LICENSE](LICENSE).
