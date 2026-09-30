import LiquidBarCore
import Testing

@Test func onlyNixStoreCopiesAreUpdatedByNix() {
    #expect(updatedByNix(bundlePath: "/nix/store/0abc-liquid-bar-0.9.0/Applications/LiquidBar.app"))
    #expect(!updatedByNix(bundlePath: "/Applications/LiquidBar.app"))
    #expect(!updatedByNix(bundlePath: "/Users/me/Downloads/nix/store/LiquidBar.app"))
    #expect(!updatedByNix(bundlePath: "/nix/storefront/LiquidBar.app"))
}
