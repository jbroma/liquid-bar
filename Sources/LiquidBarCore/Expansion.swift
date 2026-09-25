import Foundation

/// Which one pill of a bar is expanded. Hover claims the slot after a short intent delay (so sweeping the pointer
/// across the bar does not flicker every pill) and keeps it for a moment after the pointer leaves; a pulse claims it
/// for a fixed time and wins over hover. Only one pill is ever expanded, so their widths never add up.
public struct ExpansionInputs<ID: Hashable & Sendable>: Equatable, Sendable {
    public struct Mark: Equatable, Sendable {
        public var id: ID
        public var time: Date

        public init(_ id: ID, _ time: Date) {
            self.id = id
            self.time = time
        }
    }

    /// The pill under the pointer and since when.
    public var inside: Mark?
    /// The pulsing pill and when its pulse ends.
    public var pulse: Mark?
    /// The expanded pill the pointer last left and when.
    public var left: Mark?

    public init(inside: Mark? = nil, pulse: Mark? = nil, left: Mark? = nil) {
        self.inside = inside
        self.pulse = pulse
        self.left = left
    }

    public static var hoverIntent: TimeInterval { 0.09 }
    public static var linger: TimeInterval { 0.9 }
    public static var pulseLength: TimeInterval { 2.2 }

    /// The expanded pill at `now`, given the one expanded until now, and when the answer can next change by itself.
    public func owner(now: Date, current: ID?) -> (id: ID?, recheck: Date?) {
        let pulseEnd = pulse.map(\.time).flatMap { $0 > now ? $0 : nil }
        // Re-entering the expanded pill keeps it without waiting for intent again.
        let intentEnd = inside.flatMap { $0.id == current ? nil : $0.time + Self.hoverIntent }.flatMap { $0 > now ? $0 : nil }
        let lingerEnd = left.map { $0.time + Self.linger }.flatMap { $0 > now ? $0 : nil }
        let id: ID? =
            if let pulse, pulseEnd != nil { pulse.id }
            else if let inside, intentEnd == nil { inside.id }
            else if let left, lingerEnd != nil, left.id == current { left.id }
            else { nil }
        return (id, [pulseEnd, intentEnd, lingerEnd].compactMap { $0 }.min())
    }
}
