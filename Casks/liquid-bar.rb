# The Release workflow rewrites `version` and `sha256` on every release.
cask "liquid-bar" do
  version "0.15.0"
  sha256 "db8fe75cb3c342a44246f3b888e636847d270f8c84b87c49669f8cf4d1a48ad7"

  url "https://github.com/jbroma/liquid-bar/releases/download/v#{version}/LiquidBar-#{version}.zip"
  name "LiquidBar"
  desc "Liquid Glass menu bar replacement"
  homepage "https://github.com/jbroma/liquid-bar"

  livecheck do
    url "https://raw.githubusercontent.com/jbroma/liquid-bar/main/appcast.xml"
    strategy :sparkle, &:short_version
  end

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "LiquidBar.app"

  uninstall launchctl: "dev.liquidbar",
            quit:      "dev.liquidbar"

  zap trash: [
    "~/.config/liquid-bar",
    "~/Library/Caches/dev.liquidbar",
    "~/Library/HTTPStorages/dev.liquidbar",
    "~/Library/HTTPStorages/dev.liquidbar.binarycookies",
    "~/Library/Preferences/dev.liquidbar.plist",
  ]
end
