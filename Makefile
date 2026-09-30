APP := build/LiquidBar.app
# A stable identity keeps the Accessibility and Automation grants across rebuilds; ad-hoc signing loses them. Developer
# ID comes first, so local builds share the grants of the notarized releases.
IDENTITIES := $(shell security find-identity -p codesigning -v)
SIGN ?= $(or $(shell echo '$(IDENTITIES)' | grep -o '"Developer ID Application[^"]*"' | head -1 | tr -d '"'),$(shell echo '$(IDENTITIES)' | grep -o '"Apple Development[^"]*"' | head -1 | tr -d '"'),-)
TIMESTAMP := $(if $(filter -,$(SIGN)),--timestamp=none,--timestamp)
CODESIGN := codesign --force --options runtime $(TIMESTAMP) --sign "$(SIGN)"
# Where SwiftPM unpacks the Sparkle release: the framework and its bin/ tools (generate_keys, sign_update).
SPARKLE := .build/artifacts/sparkle/Sparkle
FRAMEWORK := $(APP)/Contents/Frameworks/Sparkle.framework
# The keychain profile `xcrun notarytool store-credentials` saved the notary credentials under.
NOTARY ?= liquid-bar
AGENT := $(HOME)/Library/LaunchAgents/dev.liquidbar.plist
DOMAIN := gui/$(shell id -u)
SERVICE := $(DOMAIN)/dev.liquidbar
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)
ZIP := build/LiquidBar-$(VERSION).zip
REPO := https://github.com/jbroma/liquid-bar

.PHONY: app icon run test install uninstall restore release clean

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/liquid-bar $(APP)/Contents/MacOS/
	cp Support/Info.plist $(APP)/Contents/
	cp Support/AppIcon.icns $(APP)/Contents/Resources/
	ditto $(SPARKLE)/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework $(FRAMEWORK)
	# Sparkle's XPC services are for sandboxed apps only, and LiquidBar is not sandboxed. Sign inside out, never --deep.
	rm -rf $(FRAMEWORK)/XPCServices $(FRAMEWORK)/Versions/B/XPCServices
	$(CODESIGN) $(FRAMEWORK)/Versions/B/Autoupdate
	$(CODESIGN) $(FRAMEWORK)/Versions/B/Updater.app
	$(CODESIGN) $(FRAMEWORK)
	$(CODESIGN) --entitlements Support/LiquidBar.entitlements $(APP)

# Regenerates Support/AppIcon.icns and docs/images/icon.png from Support/icon/render.swift.
icon:
	swift Support/icon/render.swift

# The launch agent's bar would quit for this one and stay down, so stop the agent first; `make restore` brings it back.
run: app
	-launchctl bootout $(SERVICE) 2>/dev/null
	open -n $(APP)

test:
	swift test

install: app
	-launchctl bootout $(SERVICE) 2>/dev/null
	rm -rf /Applications/LiquidBar.app
	cp -R $(APP) /Applications/
	cp Support/dev.liquidbar.plist $(AGENT)
	launchctl bootstrap $(DOMAIN) $(AGENT)

# Loads the installed agent again, or starts its bar if it is loaded but stopped.
restore:
	-launchctl bootstrap $(DOMAIN) $(AGENT) 2>/dev/null
	launchctl kickstart $(SERVICE)

uninstall:
	-launchctl bootout $(SERVICE)
	rm -f $(AGENT)
	rm -rf /Applications/LiquidBar.app

# Bump CFBundleShortVersionString and CFBundleVersion in Support/Info.plist and push main first. The Mac does what
# needs its keychain: notarizes and staples the app, tags main as v$(VERSION), uploads the zip to a draft release, and
# signs the zip with the Sparkle EdDSA key (see generate_keys). .github/workflows/release.yml does the rest: the notes,
# publishing, CHANGELOG.md and appcast.xml. No resource forks or extended attributes in the zip: plain `unzip` turns
# them into ._ files inside the bundle, which breaks its signature. The printed hash is what a Nix package pins.
release: app
	test -z "$$(git status --porcelain)"
	test "$$(git rev-parse HEAD)" = "$$(git rev-parse origin/main)"
	ditto -c -k --keepParent $(APP) build/notarize.zip
	xcrun notarytool submit build/notarize.zip --keychain-profile $(NOTARY) --wait
	xcrun stapler staple $(APP)
	ditto -c -k --keepParent --norsrc --noextattr --noacl $(APP) $(ZIP)
	git tag -s v$(VERSION) -m "v$(VERSION)"
	git push origin v$(VERSION)
	gh release create v$(VERSION) $(ZIP) --verify-tag --draft --title "v$(VERSION)" --notes ""
	gh workflow run release.yml -f tag=v$(VERSION) -f enclosure="$$($(SPARKLE)/bin/sign_update $(ZIP))"
	@echo "GitHub publishes the release: $(REPO)/actions/workflows/release.yml"
	@echo "Nix hash: $$(nix hash file --type sha256 --sri $(ZIP) 2>/dev/null || shasum -a 256 $(ZIP))"

clean:
	rm -rf .build build
