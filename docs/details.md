# Details

## Layout

On a notched screen the bar is as tall as the native menu bar, one point taller than the notch. Left of the notch, drawn straight on the glass, are the Apple logo and the workspaces. With glass pills, the Apple logo is a round glass button and the workspaces sit beside it in a glass capsule like iOS's tab bar. Each workspace shows its apps' icons, or a dot when it has no windows, which becomes its number while it is focused. No workspace changes width with the focus, so the strip stays still under the moving selection. A glass lens marks the focused workspace, 3 points inside the capsule on every side. On its way to another workspace the lens lifts, grows with a brighter rim, and magnifies the workspaces it passes over. With flat pills, a soft fill marks the focused workspace and flows to the next one like a droplet. Right of the notch, in glass pills (one each, one shared, or none, by the `pills` setting), are now playing, volume, Wi-Fi, battery, Control Center, and the clock.

Every screen gets its own bar, exactly as tall as the native menu bar under it: 34 points on a notched screen and 24 on most others. Pills are 8 points shorter. Nothing is drawn beside the notch that does not fit there.

## Workspaces

The strip left of the notch shows one of three sources, picked by `workspaceSource`:

- `aerospace`: the AeroSpace workspaces from the `workspaces` key, each with its apps. Clicking one or scrolling runs `aerospace workspace`.
- `spaces`: the desktops (Spaces) of the display you are on, numbered 1 to 9 as in Mission Control, each with the apps of its windows. Fullscreen apps are left out. The bar reads the list through SkyLight and refreshes it when you switch desktops or an app activates, launches, quits, hides, or unhides. Clicking a desktop or scrolling presses its "Switch to Desktop N" shortcut, because macOS has no API to switch desktops. Those shortcuts are off by default. Turn them on in System Settings, Keyboard, Keyboard Shortcuts, Mission Control. While one is off, clicking its desktop explains this and offers to open the settings. Pressing the shortcut needs Accessibility access.
- `apps`: no workspaces. The strip shows each running app with a window on screen, icon only, the front app first and the rest in the order they were last used. Clicking one brings it forward.

`auto`, the default, uses AeroSpace while it runs, else the desktops when the current display has two or more, else the apps. It picks again when AeroSpace launches or quits and when you switch desktops.

In every source, hovering an item with two or more apps lists them, and clicking the focused item shows the front app's menus. Workspaces never change width on hover.

## Behavior

**Dropdowns.** One dropdown per bar is open at a time. Hovering a pill opens its dropdown after 40 ms, so a fast sweep across the bar does not open every one, and the pill widens by a few points. The dropdown fades in and drops into place, and fades out when it closes. Once a dropdown is open, moving to another item opens that one at once, like the native menu bar, and the dropdown morphs over to it. The dropdown stays open while the pointer is on the pill or in the dropdown, and closes 0.15 s after the pointer leaves both. A dropdown never crosses the notch and stays on screen. One taller than the screen below the bar scrolls.

**Switches and sliders in dropdowns.** The Wi-Fi dropdown starts with a Wi-Fi switch; while Wi-Fi is off it shows only the switch and Network Settings…. Clicking the IP address copies it, and the row reads Copied for a second. The Battery dropdown has a Show Percentage switch, the same setting as the Apple dropdown's Show Battery Percentage. Scrolling over the volume or a brightness slider moves it: up or right raises the level in the device's direction whatever the natural scrolling setting, about 200pt of trackpad travel covers the range, and a wheel notch moves 5%.

**Wi-Fi networks.** Below the current network, the Wi-Fi dropdown lists the networks in range under Known Networks and Other Networks, each strongest first, with its signal and a lock when secured. Past about eight rows the list scrolls. The list shows CoreWLAN's last scan at once, scans again when the dropdown opens and every 10 s while it stays open, and never scans at rest. Clicking an open network joins it. Clicking a known secured network joins it with the password the System keychain saved for it. macOS asks for an administrator password before it hands that password to the bar. Clicking a new secured network unfolds a password field under its row: Return or Join joins, Esc folds it, and a failed join shows why under the field. A known network whose saved password cannot be read also unfolds the field. A spinner replaces the lock while the Mac joins. Other Network… opens the Wi-Fi settings, because macOS has no public way to open its own Join Other Network dialog.

**Hit areas.** The bar takes clicks over the whole strip at the top of the screen, also where nothing is drawn, so a right-click beside the items opens the bar's menu. Each item reacts across the full bar height and up to halfway to its neighbours, and the outermost items out to the screen edge. A pointer thrown at the top edge, into a corner, or between two pills still lands on one.

**Changes you did not make.** A change the bar did not cause, like plugging in the charger or a network drop, opens that dropdown for 2.2 s. A new track opens no dropdown. The now playing pill instead widens for 3 s to show the title and artist next to the new artwork, and stays wide while the pointer is on it.

**The front app's menus.** Clicking the focused workspace, or holding Shift with the pointer on the bar, turns the strip into the front app's menu titles, read through Accessibility, with the app's own menu first and in bold. Each title opens a native menu with the app's items, shortcuts, and checkmarks, and picking an item runs it in the app. Press Esc, switch apps, click the focused workspace again, or move the pointer out of the bar to bring the workspaces back.

**The native menu bar.** While the bar runs, it sets the native menu bar's opacity to 0 through SkyLight, as yabai's `menubar_opacity` does, so the native menu bar never shows through the glass and ignores the mouse. In a fullscreen Space, or while a window covers the whole screen, the bar hides as the native menu bar does, on a screen with a notch too. Move the pointer to the top edge and the bar slides back down in the native menu bar's place, and it stays while one of its dropdowns or menus is open. Mission Control brings the native menu bar back as it opens and closes, in its first frame before any event tells an app. So the bar draws an opaque copy of the desktop picture behind everything else, and stays above the native menu bar, which then never shows through, whatever the bar's background. The copy comes from the desktop picture's own window, which the window server hands out without Screen Recording access, and is read again every five seconds, so a dynamic picture stays in step. Over a full-screen window the copy is black. If the picture cannot be read, the bar stays under the native menu bar as before, resets its opacity while Mission Control is up, and a bar without a background shows a frosted strip for that time. If the bar quits or crashes, macOS restores the native menu bar.

**Menu bar auto-hide.** Turn it off in System Settings ("Automatically hide and show the menu bar", Never) or with `defaults write NSGlobalDomain _HIHideMenuBar -bool false`. macOS then keeps windows, notification banners, and Notification Center below the menu bar strip, and the bar is exactly as tall as that strip. With auto-hide on, the bar still works, but windows and banners can slide under it.

## Control Center

The Control Center dropdown is 300pt wide and is laid out like the top of macOS's Control Center. Settings, Control Center chooses what it shows (`controlCenter` in the config): Bluetooth, AirDrop, and Focus, sliders for the display, the keyboard's backlight, and the sound, and tiles for Dark Mode, Night Shift, True Tone, Stage Manager, and Screenshot. Sound, True Tone, and Stage Manager start off. Its groups sit straight on the dropdown's glass, with a hairline between them. Bluetooth and AirDrop are rows on the left, and Focus is a tile on the right, with a hairline between them. Each circle fills with the accent colour while its control is on. A click anywhere on a Bluetooth or AirDrop row unfolds its list below, and the row stays lit while it is open. A click on the circle switches the control without unfolding it. The list ends with its Settings row. Each opening of the dropdown starts with every list folded.

- Bluetooth: the circle turns Bluetooth on or off. The list has the paired devices, connected ones first, each with its battery when the device reports it and a filled circle while connected. Click a device to connect or disconnect it. While Bluetooth is off the devices are dimmed. Bluetooth Settings… opens its pane.
- AirDrop: the row reads Off, Contacts Only, or Everyone. The circle turns AirDrop off, or back on in the last mode that was on, Contacts Only by default. The list has Contacts Only and Everyone, with a filled circle on the current one, and AirDrop Settings… opens General > AirDrop & Continuity.
- Focus: click the tile to turn the active Focus off, or Do Not Disturb on.

One row is expanded at a time. Its chevron turns down, and the dropdown grows downward without moving the rows. Below are horizontal sliders for the built-in display and keyboard brightness, which also follow scrolling as the volume slider does, and a row of labeled tiles for Dark Mode, Night Shift, and Screenshot, which opens the Screenshot toolbar. Screen Mirroring is not in it, because listing AirPlay displays and starting mirroring need entitlements only Apple's Control Center has.

A control this Mac lacks stays unfilled. Its tile then opens the matching settings pane, and its switch is dimmed.

Most of these controls have no public API, so the dropdown uses the private frameworks macOS itself uses: DisplayServices for display brightness, CoreBrightness for the keyboard backlight and Night Shift, SkyLight for Dark Mode (no Automation prompt), and `IOBluetoothPreferenceSetControllerPowerState` for Bluetooth power. sharingd accepts an AirDrop mode only from Apple's own apps and reads its `DiscoverableMode` preference only at launch, so the bar writes that preference and restarts sharingd, which launchd relaunches within a second. The restart briefly interrupts Handoff and any AirDrop transfer in progress. The bar loads them at runtime, so a missing one costs a tile, never a crash. Focus has neither an API nor a store the bar can read without Full Disk Access. The bar reads Focus from its menu bar item once at launch. Up to macOS 26 it then follows the `_NSDoNotDisturbEnabledNotification` and `_NSDoNotDisturbDisabledNotification` distributed notifications macOS posts as Focus turns on and off. macOS 27 no longer posts them, so there the bar follows the Focus menu bar item as it appears and leaves. The item leaves about five seconds after Focus ends, so a Focus turned off outside the bar shows off that much later. Which Focus is on stays unknown, so the pill shows a moon for all of them. The Focus tile presses macOS's "Turn Do Not Disturb On/Off" keyboard shortcut. If you have not set that shortcut yourself, the bar binds it through SkyLight to ⌃⌥⇧⌘D for the moment of each press, then unbinds it. If another system shortcut already uses ⌃⌥⇧⌘D, the bar takes F, J, or K instead. The binding never reaches your keyboard shortcut settings. macOS shows its own Do Not Disturb banner on every Focus change, whatever made it, and nothing turns it off. It hangs below the hidden native Focus menu bar item, or below the Control Center item while there is no Focus item, so the tile closes the dropdown before it switches Focus. Without SkyLight's shortcut calls, the tile falls back to pressing through the real Control Center over Accessibility, which opens Control Center behind the dropdown for about three seconds.

## Permissions

The bar works without any permission. Each grant adds features. At first launch the bar asks only for Accessibility. Once it has access, the same window walks through three tips, one time: hold Shift over the bar for the front app's menus, pin other apps' menu bar items in Settings, and right-click the bar for Settings. Each tip has a looping demo drawn in your glass style and is ticked off when you do it on the real bar. It asks for every other grant when you first use what needs it, with a click, never on hover or at launch, so one request is on screen at a time. Settings, General, Permissions lists each grant live as Allowed, Not asked yet, or Not allowed, with **Grant…** (macOS's prompt) or **Open Settings…** (its Privacy & Security list).

- **Accessibility** lets the bar show the front app's menus, open other apps' menu bar items and the Sound module of the real Control Center, read and switch Focus, and press the "Switch to Desktop N" shortcuts. Without it, the bar opens an "Allow Accessibility" window at launch, centred on screen. Its button adds LiquidBar to the Accessibility list, shows macOS's prompt, and opens that pane. The bar then checks for the grant once a second. When it arrives the window says "You're all set", closes after 1.5 seconds, and the bar re-reads the status items and Focus without a relaunch. "Not Now" closes the window until the next launch, which shows it again only if the grant is still missing. Opening Settings closes the window, and Grant… there asks without it. Clicking the focused workspace or a desktop without the grant explains what is missing and offers to ask.
- **Location** lets the Wi-Fi dropdown show network names, which macOS hides from apps without it. Without it the dropdown lists no networks and shows one row: "Show Network Names…" asks, and after a no "Allow Location to see network names…" opens Privacy & Security, Location Services.
- **Bluetooth** lets the Control Center dropdown list paired devices, connect them, and switch Bluetooth. The bar reads nothing from Bluetooth until you allow it. The Bluetooth circle, or "Allow Bluetooth Access…" in its unfolded list, asks.
- **Automation** for Spotify or Music lets the bar send play, pause, and skip, and ask a running player what is playing at launch, which it does only once the grant exists. Track changes arrive without it. The first transport click asks. After a no, the dropdown shows "Allow Control of Spotify…" and the transport buttons open the Automation list. Restart…, Shut Down…, and Log Out… in the Apple dropdown ask `loginwindow` to show its usual confirmation dialog, which needs Automation for `loginwindow`; the first click asks, and after a no the rows open the Automation list.
- **System keychain.** Joining a known secured Wi-Fi network from the dropdown reads its saved password, and macOS asks for an administrator password first. Cancel it, and the row asks for the Wi-Fi password instead.

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
- `make release` notarizes the signed app and uploads it as the GitHub release for the version in `Support/Info.plist`. A GitHub workflow then writes the notes, publishes it, and adds it to the update feed. [Releases and updates](#releases-and-updates) describes each step.

`make app` signs with the Developer ID identity in your keychain, or else an Apple Development one, with the hardened runtime, so macOS keeps the Accessibility and Automation grants across rebuilds. Without one it signs ad hoc, and every rebuild asks for the grants again. Set `SIGN=` to pick an identity, for example `make app SIGN=-` for ad hoc.

`Sources/LiquidBarCore` holds the pure logic: data types, config decoding, AeroSpace and player parsing, the expansion rules, and display formatting. `Tests/LiquidBarCoreTests` covers it. `Sources/LiquidBar` is the app: panels, SwiftUI views, the dropdown and its menus, the data sources, and the Apple dropdown and app menus.

## Releases and updates

The app updates itself with [Sparkle](https://sparkle-project.org) 2, which `Package.swift` pins to an exact version. `make app` copies `Sparkle.framework` into `Contents/Frameworks` and deletes its XPC services, which only sandboxed apps use. It then signs `Autoupdate`, `Updater.app`, the framework, and the app in that order, each with the same identity, the hardened runtime, and a secure timestamp.

Once a day Sparkle reads `appcast.xml` from this repository's `main` branch (`SUFeedURL` in `Support/Info.plist`). It offers any entry with a higher `CFBundleVersion` whose zip passes two checks: the EdDSA signature must match `SUPublicEDKey`, and the new app must be signed by the same Developer ID. After an install it relaunches the bar.

A release starts on the Mac, which holds the Developer ID and the Sparkle key, and GitHub Actions finishes it. `make release` runs these steps in order:

1. Checks that the working tree is clean and matches `origin/main`, then notarizes and staples the app.
2. Zips it, pushes the signed tag `v<version>`, and uploads the zip to a draft GitHub release.
3. Signs the zip with the EdDSA private key from the login keychain, using Sparkle's `sign_update`, and starts the Release workflow with that signature.

The [Release workflow](../.github/workflows/release.yml) then:

1. Writes the release notes and `CHANGELOG.md` from the commit messages with [git-cliff](https://git-cliff.org) (`cliff.toml`). `CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/): `feat` commits go under Added, `fix` and `perf` under Fixed, and `chore`, `docs`, `refactor`, `test`, and `build` commits are left out, so a commit subject should read as a line of release notes.
2. Publishes the release with the notes: the version's changelog section without its heading.
3. Adds an entry to the top of `appcast.xml` with `scripts/appcast.py`: the version, build, and minimum macOS from `Support/Info.plist`, the zip's size and signature, and the notes.
4. Commits `CHANGELOG.md` and `appcast.xml` to `main`. The feed changes only after the release is public, so it never points to a missing file.

The [CI workflow](../.github/workflows/ci.yml) runs the tests and a release build on every push to `main` and every pull request.

Every release needs a higher `CFBundleVersion` as well as a new `CFBundleShortVersionString`. The release needs notary credentials saved once with `xcrun notarytool store-credentials liquid-bar`. It also needs the EdDSA key that `.build/artifacts/sparkle/Sparkle/bin/generate_keys` created in the login keychain. Losing that key means shipped copies reject every later update, so keep a backup (`generate_keys -x <file>` exports it).

A copy inside `/nix/store` is read-only, and Nix replaces it on a configuration switch. There the bar starts no updater, leaves "Check for Updates…" out of its menu, and Settings shows "Updated by your Nix configuration".

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
