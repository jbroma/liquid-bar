APP := build/LiquidBar.app
# A stable identity keeps the Accessibility and Automation grants across rebuilds; ad-hoc signing loses them.
SIGN ?= $(or $(shell security find-identity -p codesigning -v | awk -F'"' '/Apple Development|Developer ID Application/ { print $$2; exit }'),-)
AGENT := $(HOME)/Library/LaunchAgents/dev.liquidbar.plist

.PHONY: app run test install uninstall clean

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp .build/release/liquid-bar $(APP)/Contents/MacOS/
	cp Support/Info.plist $(APP)/Contents/
	codesign --force --sign "$(SIGN)" $(APP)

run: app
	open -n $(APP)

test:
	swift test

install: app
	rm -rf /Applications/LiquidBar.app
	cp -R $(APP) /Applications/
	cp Support/dev.liquidbar.plist $(AGENT)
	-launchctl bootout gui/$$(id -u) $(AGENT) 2>/dev/null
	launchctl bootstrap gui/$$(id -u) $(AGENT)

uninstall:
	-launchctl bootout gui/$$(id -u) $(AGENT)
	rm -f $(AGENT)
	rm -rf /Applications/LiquidBar.app

clean:
	rm -rf .build build
