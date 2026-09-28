APP := build/LiquidBar.app
# A stable identity keeps the Accessibility and Automation grants across rebuilds; ad-hoc signing loses them.
SIGN ?= $(or $(shell security find-identity -p codesigning -v | awk -F'"' '/Apple Development|Developer ID Application/ { print $$2; exit }'),-)
AGENT := $(HOME)/Library/LaunchAgents/dev.liquidbar.plist
DOMAIN := gui/$(shell id -u)
SERVICE := $(DOMAIN)/dev.liquidbar
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)
ZIP := build/LiquidBar-$(VERSION).zip

.PHONY: app run test install uninstall restore release clean

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp .build/release/liquid-bar $(APP)/Contents/MacOS/
	cp Support/Info.plist $(APP)/Contents/
	codesign --force --sign "$(SIGN)" $(APP)

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

# Bump the version in Support/Info.plist first. Tags the committed tree as v$(VERSION) and publishes the signed app as
# that GitHub release. The printed sha256 is what a Nix package pins. No resource forks or extended attributes: plain
# `unzip` turns them into ._ files inside the bundle, which breaks its signature.
release: app
	test -z "$$(git status --porcelain)"
	ditto -c -k --keepParent --norsrc --noextattr --noacl $(APP) $(ZIP)
	git tag -s v$(VERSION) -m "v$(VERSION)"
	git push origin v$(VERSION)
	gh release create v$(VERSION) $(ZIP) --verify-tag --title "v$(VERSION)" --generate-notes
	shasum -a 256 $(ZIP)

clean:
	rm -rf .build build
