import AppKit

/// The light tick of a pressed control, on trackpads that have a haptic engine.
func haptic() {
    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
}
