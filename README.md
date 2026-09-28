# liquid-bar

A macOS 26 menu bar replacement drawn in Liquid Glass.

<p align="center">
  <img src="docs/images/hero-glass.png" width="100%" alt="The bar over a blue wallpaper: the Apple logo and workspaces 1 to 9 with app icons on the left, the now playing, volume, Wi-Fi, battery, Control Center, and clock pills on the right, and the clock's calendar dropdown open below the clock">
</p>

## What you get

- A glass bar with glass pills. Hover a pill and its dropdown floats below it.
- Workspaces with their apps' icons, from AeroSpace, the macOS desktops, or the running apps.
- The front app's menus when you click the focused workspace.
- Control Center, with the other apps' menu bar items listed inside it. Pin one and it moves onto the bar as its own pill, with the item's menu as its dropdown.
- Now playing for Spotify and Music. On a new track the pill slides out to show the title.
- The native menu bar stays hidden while the bar runs.
- A LiquidBar submenu in the Apple menu for settings.

<p align="center">
  <img src="docs/images/clock-glass.png" height="320" alt="Clock dropdown: the full date over a month calendar with week numbers and today marked">
  <img src="docs/images/battery-glass.png" height="320" alt="Battery dropdown: level, power source, status, condition, maximum capacity, and cycle count">
</p>
<p align="center">
  <img src="docs/images/workspace-glass.png" height="200" alt="Workspace 9 dropdown listing its apps, Messages and Spotify">
  <img src="docs/images/now-playing-glass.png" height="200" alt="Now playing dropdown: artwork, title, artist, playback controls, and Open Spotify">
</p>

## Install

Download `LiquidBar-<version>.zip` from [Releases](https://github.com/jbroma/liquid-bar/releases), unzip it, and move `LiquidBar.app` to `/Applications`. The app is signed but not notarized, so allow it once:

```sh
xattr -dr com.apple.quarantine /Applications/LiquidBar.app
```

To start it at login, copy [`Support/dev.liquidbar.plist`](Support/dev.liquidbar.plist) to `~/Library/LaunchAgents/` and run:

```sh
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/dev.liquidbar.plist
```

To build from source instead, run `make install` (needs Xcode 26). It installs the app and the launch agent. [Building from source](docs/details.md#build-from-source) lists the other `make` targets.

## Requirements

- macOS 26 or later.
- Menu bar auto-hide off (System Settings, "Automatically hide and show the menu bar", Never). With auto-hide on, windows and notification banners can slide under the bar.
- Accessibility access, for the front app's menus, other apps' menu bar items, and a few Control Center tiles. The bar runs without it. [Permissions](docs/details.md#permissions) lists every grant.
- [AeroSpace](https://github.com/nikitabobko/AeroSpace) is optional.

## Settings

Open the Apple menu and pick **LiquidBar** to switch the workspace source, the clock format, and whether now playing and the battery percentage show.

<p align="center">
  <img src="docs/images/settings-glass.png" height="240" alt="The LiquidBar submenu: Workspaces, Clock, Show Now Playing, Show Battery Percentage, Open Config File, Reload Config, and Quit LiquidBar">
</p>

Everything else, like widget order, click commands, and script widgets, lives in `~/.config/liquid-bar/config.json`. See [Configuration](docs/configuration.md).

## How it works

The bar uses private macOS frameworks (SkyLight, DisplayServices, CoreBrightness) where no public API exists. A macOS update can break one of those features, but the bar loads each one at runtime, so a missing framework costs that feature and never crashes the bar. While the bar runs, the native menu bar is invisible. If the bar quits, macOS brings the native menu bar back. [Details](docs/details.md) covers behavior, permissions, and migrating from SketchyBar.

## License

MIT. See [LICENSE](LICENSE).
