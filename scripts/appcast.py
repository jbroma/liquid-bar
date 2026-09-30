#!/usr/bin/env python3
"""appcast.py <tag> <enclosure> <notes.md>: adds the release to the top of appcast.xml.

<enclosure> is what Sparkle's sign_update printed for the zip on the Mac that holds the EdDSA key:
sparkle:edSignature="..." length="...". The version, build, and minimum macOS come from Support/Info.plist.
"""
import plistlib
import re
import sys
from email.utils import formatdate

REPO = "https://github.com/jbroma/liquid-bar"
tag, enclosure, notes_path = sys.argv[1:]

with open("Support/Info.plist", "rb") as f:
    info = plistlib.load(f)
version = info["CFBundleShortVersionString"]
if tag != f"v{version}":
    sys.exit(f"{tag} is not the version in Support/Info.plist, {version}")
if not re.fullmatch(r'sparkle:edSignature="[A-Za-z0-9+/]+={0,2}" length="[0-9]+"', enclosure):
    sys.exit(f"not sign_update's output: {enclosure}")

with open("appcast.xml") as f:
    appcast = f.read()
if f"<sparkle:shortVersionString>{version}<" in appcast:
    sys.exit(f"appcast.xml already has {version}")

with open(notes_path) as f:
    notes = f.read().strip()
item = f"""        <item>
            <title>{version}</title>
            <pubDate>{formatdate(usegmt=True)}</pubDate>
            <sparkle:version>{info["CFBundleVersion"]}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>{info["LSMinimumSystemVersion"]}</sparkle:minimumSystemVersion>
            <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
            <description sparkle:format="markdown"><![CDATA[{notes}

[LiquidBar {version} on GitHub]({REPO}/releases/tag/{tag})
]]></description>
            <enclosure url="{REPO}/releases/download/{tag}/LiquidBar-{version}.zip" {enclosure} type="application/octet-stream"/>
        </item>
"""
head = "        <title>LiquidBar</title>\n"
with open("appcast.xml", "w") as f:
    f.write(appcast.replace(head, head + item, 1))
