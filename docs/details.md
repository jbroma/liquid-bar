# Details

## Layout

On a notched screen the bar is as tall as the native menu bar, one point taller than the notch. Left of the notch, drawn straight on the glass, are the Apple logo and the workspaces. A soft fill marks the focused workspace and flows to the next one like a droplet. Right of the notch, in glass pills, are now playing, volume, Wi-Fi, battery, Control Center, and the clock.

Every screen gets its own bar, exactly as tall as the native menu bar under it: 34 points on a notched screen and 24 on most others. Pills are 8 points shorter. Nothing is drawn beside the notch that does not fit there.

## Workspaces

The strip left of the notch shows one of three sources, picked by `workspaceSource`:

- `aerospace`: the AeroSpace workspaces from the `workspaces` key, each with its apps. Clicking one or scrolling runs `aerospace workspace`.
- `spaces`: the desktops (Spaces) of the display you are on, numbered 1 to 9 as in Mission Control, each with the apps of its windows. Fullscreen apps are left out. The bar reads the list through SkyLight and refreshes it when you switch desktops or an app activates, launches, quits, hides, or unhides. Clicking a desktop or scrolling presses its "Switch to Desktop N" shortcut, because macOS has no API to switch desktops. Those shortcuts are off by default. Turn them on in System Settings, Keyboard, Keyboard Shortcuts, Mission Control. While one is off, clicking its desktop explains this and offers to open the settings. Pressing the shortcut needs Accessibility access.
- `apps`: no workspaces. The strip shows each running app with a window on screen, icon only, the front app first and the rest in the order they were last used. Clicking one brings it forward.

`auto`, the default, uses AeroSpace while it runs, else the desktops when the current display has two or more, else the apps. It picks again when AeroSpace launches or quits and when you switch desktops.

In every source, hovering an item with two or more apps lists them, and clicking the focused item shows the front app's menus. Workspaces never change width on hover.

## Behavior

**Dropdowns.** One dropdown per bar is open at a time. Hovering a pill opens its dropdown after 40 ms, so a fast sweep across the bar does not open every one, and the pill widens by a few points. Once a dropdown is open, moving to another item opens that one at once, like the native menu bar, and the dropdown morphs over to it. The dropdown stays open while the pointer is on the pill or in the dropdown, and closes 0.15 s after the pointer leaves both. A dropdown never crosses the notch and stays on screen. One taller than the screen below the bar scrolls.

**Switches and sliders in dropdowns.** The Wi-Fi dropdown starts with a Wi-Fi switch; while Wi-Fi is off it shows only the switch and Network Settings…. Clicking the IP address copies it, and the row reads Copied for a second. The Battery dropdown has a Show Percentage switch, the same setting as the Apple dropdown's Show Battery Percentage. Scrolling over the volume or a brightness slider moves it: up or right raises the level in the device's direction whatever the natural scrolling setting, about 200pt of trackpad travel covers the range, and a wheel notch moves 5%.

**Wi-Fi networks.** Below the current network, the Wi-Fi dropdown lists the networks in range under Known Networks and Other Networks, each strongest first, with its signal and a lock when secured. Past about eight rows the list scrolls. The list shows CoreWLAN's last scan at once, scans again when the dropdown opens and every 10 s while it stays open, and never scans at rest. Clicking an open network joins it. Clicking a known secured network joins it with the password the System keychain saved for it. macOS asks for an administrator password before it hands that password to the bar. Clicking a new secured network unfolds a password field under its row: Return or Join joins, Esc folds it, and a failed join shows why under the field. A known network whose saved password cannot be read also unfolds the field. A spinner replaces the lock while the Mac joins. Other Network… opens the Wi-Fi settings, because macOS has no public way to open its own Join Other Network dialog.

**Hit areas.** Each item reacts across the full bar height and up to halfway to its neighbours, and the outermost items out to the screen edge. A pointer thrown at the top edge, into a corner, or between two pills still lands on one.

**Changes you did not make.** A change the bar did not cause, like plugging in the charger or a network drop, opens that dropdown for 2.2 s. A new track opens no dropdown. The now playing pill instead widens for 3 s to show the title and artist next to the new artwork, and stays wide while the pointer is on it.

**The front app's menus.** Clicking the focused workspace turns the strip into the front app's menu titles, read through Accessibility, with the app's own menu first and in bold. Each title opens a native menu with the app's items, shortcuts, and checkmarks, and picking an item runs it in the app. Press Esc, switch apps, click the focused workspace again, or move the pointer out of the bar to bring the workspaces back.

**The native menu bar.** While the bar runs, it sets the native menu bar's opacity to 0 through SkyLight, as yabai's `menubar_opacity` does, so the native menu bar never shows through the glass and ignores the mouse. While a fullscreen window hides the bar, the native menu bar is visible again, so that app's menus stay reachable. If the bar quits or crashes, macOS restores the native menu bar.

**Menu bar auto-hide.** Turn it off in System Settings ("Automatically hide and show the menu bar", Never) or with `defaults write NSGlobalDomain _HIHideMenuBar -bool false`. macOS then keeps windows, notification banners, and Notification Center below the menu bar strip, and the bar is exactly as tall as that strip. With auto-hide on, the bar still works, but windows and banners can slide under it.

## Control Center

The Control Center dropdown is 300pt wide and opens with modules like the top of macOS's Control Center. Bluetooth and AirDrop are rows in the left module, and Focus is a tile of its own on the right. Each circle fills with the accent colour while its control is on. A click anywhere on a Bluetooth or AirDrop row unfolds its module below, and the row stays lit while it is open. The module starts with the control's name and a switch, and ends with its Settings row. Each opening of the dropdown starts with every module folded.

- Bluetooth: the switch turns Bluetooth on or off. The module lists the paired devices, connected ones first, each with its battery when the device reports it and a filled circle while connected. Click a device to connect or disconnect it. While Bluetooth is off the devices are dimmed. Bluetooth Settings… opens its pane.
- AirDrop: the row reads Off, Contacts Only, or Everyone. The switch turns AirDrop off, or back on in the last mode that was on, Contacts Only by default. The module lists Contacts Only and Everyone, with a filled circle on the current one, and AirDrop Settings… opens General > AirDrop & Continuity.
- Focus: click the tile to turn the active Focus off, or Do Not Disturb on.

One row is expanded at a time. Its chevron turns down, and the dropdown grows downward without moving the rows. Below are a module with horizontal sliders for the built-in display and keyboard brightness, which also follow scrolling as the volume slider does, and a module of labeled tiles for Dark Mode, Night Shift, and Screenshot, which opens the Screenshot toolbar. Screen Mirroring is not in it, because listing AirPlay displays and starting mirroring need entitlements only Apple's Control Center has.

**Menu Bar Items** is a module at the bottom that opens folded, with the number of items beside its title; a click on the title unfolds the other apps' items in the covered menu bar, in the native left-to-right order, each with its app's icon and name. Clicking an item with a menu lists its entries inline; clicking one without a menu presses it, so its window or popover opens. The pin before each icon, shown on hover and filled while pinned, moves the item onto the bar. Apple's items and AeroSpace's are left out, because the bar shows them. The module is hidden when no other app has an item, or without Accessibility. The list refreshes when an app launches or quits and each time the dropdown opens.

A control this Mac lacks stays unfilled. Its tile then opens the matching settings pane, and its switch is dimmed.

Most of these controls have no public API, so the dropdown uses the private frameworks macOS itself uses: DisplayServices for display brightness, CoreBrightness for the keyboard backlight and Night Shift, SkyLight for Dark Mode (no Automation prompt), and `IOBluetoothPreferenceSetControllerPowerState` for Bluetooth power. sharingd accepts an AirDrop mode only from Apple's own apps and reads its `DiscoverableMode` preference only at launch, so the bar writes that preference and restarts sharingd, which launchd relaunches within a second. The restart briefly interrupts Handoff and any AirDrop transfer in progress. The bar loads them at runtime, so a missing one costs a tile, never a crash. Focus has neither an API nor a store the bar can read without Full Disk Access. The bar reads Focus from its menu bar item once at launch. Up to macOS 26 it then follows the `_NSDoNotDisturbEnabledNotification` and `_NSDoNotDisturbDisabledNotification` distributed notifications macOS posts as Focus turns on and off. macOS 27 no longer posts them, so there the bar follows the Focus menu bar item as it appears and leaves. The item leaves about five seconds after Focus ends, so a Focus turned off outside the bar shows off that much later. Which Focus is on stays unknown, so the pill shows a moon for all of them. The Focus tile presses macOS's "Turn Do Not Disturb On/Off" keyboard shortcut. If you have not set that shortcut yourself, the bar binds it through SkyLight to ⌃⌥⇧⌘D for the moment of each press, then unbinds it. If another system shortcut already uses ⌃⌥⇧⌘D, the bar takes F, J, or K instead. The binding never reaches your keyboard shortcut settings. macOS shows its own Do Not Disturb banner on every Focus change, whatever made it, and nothing turns it off. It hangs below the hidden native Focus menu bar item, or below the Control Center item while there is no Focus item, so the tile closes the dropdown before it switches Focus. Without SkyLight's shortcut calls, the tile falls back to pressing through the real Control Center over Accessibility, which opens Control Center behind the dropdown for about three seconds.

## Permissions

The bar works without any permission. Each grant adds features, and macOS asks for it the first time the bar needs it.

- **Accessibility** lets the bar show the front app's menus, open other apps' menu bar items and the Sound module of the real Control Center, read and switch Focus, and press the "Switch to Desktop N" shortcuts. Without it, the bar opens an "Allow Accessibility" window at launch, centred on screen. Its button adds LiquidBar to the Accessibility list, shows macOS's prompt, and opens that pane. While the window is open the bar checks for the grant once a second. When it arrives the window says "You're all set", closes after 1.5 seconds, and the bar re-reads the status items and Focus without a relaunch. "Not Now" closes the window until the next launch, which shows it again only if the grant is still missing. Apple dropdown, LiquidBar, Permissions… reopens the window at any time, and shows the granted state when access is on. Clicking the focused workspace or a desktop without the grant also explains what is missing and offers to open the pane.
- **Location** lets the Wi-Fi dropdown show network names, which macOS hides from apps without it. macOS asks the first time the Wi-Fi dropdown opens, never at launch. Without it the dropdown lists no networks and shows one row, "Allow Location to see network names", which opens Privacy & Security, Location Services.
- **Bluetooth** lets the Control Center dropdown list paired devices, connect them, and switch Bluetooth. macOS asks the first time the dropdown opens.
- **Automation** for Spotify or Music lets the bar ask a running player what is playing at launch, and send play, pause, and skip. Track changes arrive without it. Restart…, Shut Down…, and Log Out… in the Apple dropdown ask `loginwindow` to show its usual confirmation dialog, which can also trigger an Automation prompt.

**Apple dropdown.** Hovering the Apple logo opens a dropdown with the Apple menu's items in the same order: About This Mac, System Settings…, Force Quit, Sleep, Restart…, Shut Down…, Lock Screen, Log Out…, and LiquidBar. Force Quit and LiquidBar unfold inline, one at a time, and both are folded each time the dropdown opens. Settings under LiquidBar keep the dropdown open, so the checkmarks and the bar change at once; every other row closes it. The Force Quit row lists running apps and force-quits the one you pick. The bar does not open the system Force Quit window, because only a synthesized ⌥⌘⎋ keystroke can open it.

## Updates and timers

Everything updates from system events: `aerospace subscribe`, NSWorkspace app and desktop notifications, IOKit power notifications, CoreAudio property listeners, `NWPathMonitor`, the players' distributed notifications, and Accessibility notifications. liquid-bar subscribes to AeroSpace itself and retries until AeroSpace runs, so it needs no AeroSpace startup hook.

At rest the only timers are the clock, which fires on each minute boundary, and script intervals. Throughput sampling and Wi-Fi scans run only while the Wi-Fi dropdown is open. Control Center reads its controls only when its dropdown opens, after a change, and on appearance changes while it is open.

## Build from source

Building needs Xcode 26 (Swift 6.2 or later).

- `make install` builds `build/LiquidBar.app`, copies it to `/Applications`, and loads the launch agent `Support/dev.liquidbar.plist`, which starts the bar at login and restarts it if it crashes. `make uninstall` reverses all three steps.
- `make app` builds `build/LiquidBar.app` only.
- `make run` stops the launch agent, builds the app, and opens it. A newly started bar quits any running one, so repeated runs never stack two bars.
- `make restore` hands the bar back to the launch agent after `make run`.
- `make test` runs the unit tests.
- `make release` notarizes the signed app and publishes it as the GitHub release for the version in `Support/Info.plist`. It needs notary credentials saved once with `xcrun notarytool store-credentials liquid-bar`.

`make app` signs with the Developer ID identity in your keychain, or else an Apple Development one, with the hardened runtime, so macOS keeps the Accessibility and Automation grants across rebuilds. Without one it signs ad hoc, and every rebuild asks for the grants again. Set `SIGN=` to pick an identity, for example `make app SIGN=-` for ad hoc.

`Sources/LiquidBarCore` holds the pure logic: data types, config decoding, AeroSpace and player parsing, the expansion rules, and display formatting. `Tests/LiquidBarCoreTests` covers it. `Sources/LiquidBar` is the app: panels, SwiftUI views, the dropdown and its menus, the data sources, and the Apple dropdown and app menus.

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

3. Turn menu bar auto-hide off (see [Menu bar auto-hide](#behavior)).

4. Run `make install`.

Script widgets replace SketchyBar items, and `liquid-bar trigger <event>` replaces `sketchybar --trigger`. See [Script widgets](configuration.md#script-widgets).
