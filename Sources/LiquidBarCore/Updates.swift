/// Nix installs the app into its read-only store and updates it by rebuilding the configuration, so a copy there
/// cannot update itself. `bundlePath` has its symlinks resolved, as Home Manager links apps into ~/Applications.
public func updatedByNix(bundlePath: String) -> Bool {
    bundlePath.hasPrefix("/nix/store/")
}
