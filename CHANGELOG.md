# Changelog

What changed in each release, from the commit messages.

## 0.10.0 (2026-09-30)

### New

- Settings icons are white symbols on System Settings style tiles, with dot status and small buttons on permissions
- Add an option to hide bar item backgrounds (thanks rudrankriyam)
- Downloaded copies update themselves through Sparkle
- The Accessibility request is a standard window with Apple's permission layout
- Settings looks and behaves like System Settings
- Settings shows System Settings' own icons, drawn by macOS

### Fixes

- The workspace strip follows windows moved without focus and stays on AeroSpace when another app quits
- The Accessibility and update windows come forward when LiquidBar runs in the background
- LiquidBar's windows follow a switch to Light or Dark while they are open
- Check for Updates brings Sparkle's windows forward from the background too
- A closed Settings window stops using CPU
- Settings panes start right under the toolbar and use System Settings' sidebar icons
- The Settings sidebar keeps its width when switching panes

## 0.9.0 (2026-09-30)

### New

- Settings is a standard macOS settings window, whatever the glass style
- A Show Pills option draws the bar's items straight on the bar
- The clock follows the system's 24-hour setting unless clock24Hour is set
- Settings folds About and Advanced into General and shows permissions as icons

### Fixes

- Each permission is asked for only on first use, one at a time, with its live status in Settings
- Without pills the bar's items sit as close as native status items

## 0.8.0 (2026-09-30)

### New

- Builds sign with the Developer ID and releases are notarized
- The Accessibility window steps into the corner while System Settings is open
- Clicking the Wi-Fi dropdown's IP address copies it
- The Wi-Fi dropdown lists networks in range and joins them
- The Wi-Fi dropdown folds its network list by default
- Holding Shift over the bar shows the front app's menus
- Dropdowns and the About and Accessibility windows wear the volume overlay's glass
- The Sound dropdown's slider is the volume overlay's thin track between two speakers
- Five glass styles for the dropdowns, windows and pills
- A Settings window, opened from a right-click on the bar
- The bar's right-click menu drops About LiquidBar
- Dew, a glass style between Liquid and Crystal
- Dew and Pearl, even steps between Liquid and Crystal
- Pick the bar's and the dropdowns' glass style apart

### Fixes

- The bar stays put when Mission Control opens and closes
- Dropdowns sit as close to the screen edge as they hang below the bar
- Builds with Swift 6.4, whose stricter isolation rejected two shapes
- Apple's status items are found again on macOS 27
- Focus follows its menu bar item on macOS 27
- The Focus fallback finds Control Center's modes on macOS 27
- The native menu bar stays hidden through Mission Control on macOS 27
- The Accessibility request is one flow with macOS's own prompt
- Settings header stays clear of scrolled content, presets fit four to a row

## 0.7.1 (2026-09-30)

### New

- The right side's pills take the focused workspace's fill

## 0.7.0 (2026-09-30)

### New

- Bluetooth and AirDrop lists open like Control Center's modules, with a switch in the header
- Menu Bar Items fold into a module that opens collapsed, with each row's pin at its start
- The Battery dropdown has a Show Percentage switch
- Sliders follow trackpad and mouse wheel scrolling under the pointer
- The Bluetooth and AirDrop rows are one target that unfolds their module
- The Wi-Fi dropdown has a Wi-Fi switch in its header
- An Allow Accessibility window on launch, and Permissions… in the LiquidBar menu
- The Apple logo opens its dropdown on hover, with Force Quit and LiquidBar unfolding inline
- About LiquidBar in the Apple dropdown opens a glass window with the version and repository
- The Bluetooth and AirDrop circles switch their control again, inside one row
- An app icon, a glass menu bar over the violet wallpaper, rendered by make icon
- The clock dropdown opens Calendar, and marks today in the accent colour
- The battery pill shows the percentage only when asked

### Fixes

- Volume changes no longer pulse the Sound dropdown open, since macOS shows its own overlay
- Dropdowns close 0.15 s after the pointer leaves, checked against the real pointer while open
- About drops the AeroSpace line and shows its GitHub link as a link

## 0.6.0 (2026-09-29)

### New

- A compact Control Center in the glass idiom
- The dropdowns have a lit edge and a shadow
- The dropdowns use regular glass, frosted like native menus
- Control Center is a grid of eight round tiles, 20pt narrower
- The Control Center pill shows a moon while a Focus is on
- Control Center's circles drop their labels
- Control Center groups its switches into rows beside tall brightness sliders
- The Do Not Disturb banner appears at the top right, below the bar
- A control that is on fills its circle with the accent colour
- Config can pin apps' menu bar items, and a setting pins or unpins one
- Pinned apps' menu bar items move onto the bar as pills with their menu as the dropdown
- The Do Not Disturb banner stays out of sight
- The Do Not Disturb banner shows where macOS puts it, and the Focus row closes the dropdown first
- Bluetooth and AirDrop rows expand inline, and AirDrop modes switch without Finder
- Control Center is laid out in modules like macOS's own
- Pinned apps' menu bar items share one pill, each icon opening its own dropdown

### Fixes

- Release zips carry no ._ files that break the app's signature
- The time sits just left of the privacy dot, not far from it
- Control Center opens with menu bar auto-hide on
- Notification banners draw over the bar
- Turning Focus off presses only the Focus status item
- The Focus tile switches Do Not Disturb with its keyboard shortcut instead of opening Control Center
- A closing dropdown leaves no line behind

## 0.5.0 (2026-09-28)

### New

- Glass bar panel per screen with static layout
- AeroSpace workspaces, focus, occupancy and mode
- Battery, volume, network and clock sources
- Apple menu and click actions
- JSON config with hot reload, script widgets and trigger
- Stretch islands into wings while the pointer is in the bar
- LivePill expansion with hover intent and pulse
- Battery and network details
- Merged clock and date with a calendar popover
- Workspaces show their apps as icon stacks
- Now playing from Spotify and Music
- Show only the time at rest
- Right island yields to notification banners
- Front app pill and the app's menus in the bar
- Read T3 Code agent threads from its SQLite read model
- An agent island grown out of the notch
- Chromatic liquid glass
- Menus from the top edge instead of a front app pill
- Agent island off by default behind "agents"; drop the moving backgrounds
- Ferrofluid renderer
- Glass ampoules with ferrofluid poured out of the notch
- Free ferrofluid beads that wrap their items
- Ferrofluid material that reflects the wallpaper
- The workspace droplet necks as it flows
- Ferrofluid lit like a studio photograph
- Today in the calendar is a vessel of ferrofluid; README for v4
- One dark band behind the bar that grows into the notch
- Pure black bar exactly as tall as the notch, with smaller pills
- Flat workspace strip and Apple logo on the black bar
- Always show workspace numbers
- Black dropdown under the open right item
- Volume dropdown with slider, mute and output devices
- Wi-Fi dropdown with network, address and throughput
- Battery dropdown with power source, status and health
- Calendar moves into the clock's dropdown
- Now playing dropdown with artwork and transport controls
- Control Center item opens the real Control Center
- Tray of the menu bar items the bar covers
- Workspace apps in a dropdown instead of fanning out in place
- Control Center opens on hover like the other items
- Control Center item opens its own dropdown of glass tiles
- Display and keyboard brightness sliders in Control Center
- Dark Mode and Night Shift tiles
- Bluetooth tile and paired devices in Control Center
- Focus tile that reads and switches Focus
- Menu bar items listed in Control Center instead of their own pill
- A faint fill under the pointer on the Apple glyph and the workspaces
- Esc closes an open dropdown
- Sliding onto another app-menu title switches to its menu
- App-menu titles that do not fit beside the notch move into a » title
- Workspaces show a card stack of their apps' icons again
- Control Center sits before the battery by default
- The battery pill is a slim white battery filled to the level
- Control Center lists a status item's menu entries inline
- The bar and its dropdowns are Liquid Glass
- The front app's menus open only by clicking the focused workspace
- The native menu bar never shows through the glass
- The clock pill leaves room for the macOS privacy dot
- Workspaces can come from AeroSpace, the macOS desktops, or the running apps
- The workspace strip works without AeroSpace
- A change can show inline in its pill instead of opening the dropdown
- A new track shows its title in the now playing pill instead of opening the dropdown
- The clock can show 12-hour time and seconds, and the battery can hide its percentage
- A LiquidBar submenu in the Apple menu changes the bar's settings in the config file
- The clock pill makes room for the privacy dot only while it shows
- The LiquidBar submenu is last in the Apple menu, after a divider

### Fixes

- Grow a black band out of the notch instead of two glass slabs
- One expanded pill per bar, and details yield instead of overflowing
- Watch only Notification Center's banner window
- No transitions on resting ticks; stable signing; README for v2
- Keep now playing in the right island; the island is for agents only
- Cover the whole 33pt native menu bar
- Drop the bar below notification banners while one shows
- Hover wins over pulses
- No dead zones between or above the pills, shorter hover intent
- One row per Bluetooth device, and a phone symbol for iPhones
- Screen Mirroring tile opens Control Center's mirroring list
- AirPlay audio outputs reachable from the volume dropdown
- First item of the Apple and app menus hidden behind a scroll arrow
- Dropdown closes under the pointer after a row hands over
- Native menu bar showed through while a banner was up
- Pointer thrown into a top corner lands on the outermost item
- Dropdown taller than the screen scrolls instead of running off it
- Bar covers the visible native menu bar exactly instead of juggling levels for banners
- A slow or hung command no longer starves the bar's threads
- Hide a screen's bar while a window covers the whole screen
- A busy app stalls Accessibility calls for 1s, not 6s
- Rebuild the bars once after screen changes settle
- Config errors and launch problems go to the system log
- Make run and install stop the launch agent first; make restore
- No pulses for 5s after wake, and only on the pointer's screen
- Workspaces come back within 3s of AeroSpace starting, dim while it is gone
- Guard the keyboard backlight lookup; the clock follows time zone changes
- Blocking Accessibility and Bluetooth work runs on GCD threads
- Rebuilding the bars removes a showing app menu's Esc monitor
- App-menu shortcuts show ⇧ only when the app's shortcut has it
- The Apple menu and app menus are dark in Light mode too
- The cards behind a workspace's top icon peek out far enough to recognise
- The Apple menu opens with About This Mac showing
- The bar resizes when menu bar auto-hide is switched

