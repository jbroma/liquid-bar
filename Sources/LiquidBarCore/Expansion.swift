import Foundation

/// Which one item of a bar is open. Hover claims an empty slot after a short intent delay, so sweeping the pointer
/// across the bar does not open every item, and an occupied one at once, like sliding along the native menu bar. It
/// keeps the slot for a moment after the pointer leaves. A pulse claims it for a fixed time while the pointer is on
/// no item, and the pointer coming to an item ends it. The pointer resting in the open item's dropdown keeps it over
/// everything.
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
    /// The pill showing its change inline instead of opening its dropdown, and when that ends.
    public var inline: Mark?
    /// The expanded pill the pointer last left and when.
    public var left: Mark?
    /// The pointer is in the open item's dropdown, which lives in another window than the pill.
    public var holding: Bool
    /// Pulses before this are ignored: sources report their first state just after launch, which is not news.
    public var quietUntil: Date

    public init(inside: Mark? = nil, pulse: Mark? = nil, inline: Mark? = nil, left: Mark? = nil, holding: Bool = false, quietUntil: Date = .distantPast) {
        self.inside = inside
        self.pulse = pulse
        self.inline = inline
        self.left = left
        self.holding = holding
        self.quietUntil = quietUntil
    }

    /// Starts a pulse of `id` at `now`, and returns false when the change is not news: during the quiet time, or made
    /// while the pointer is on the item or in its open dropdown, like dragging its volume slider.
    public mutating func startPulse(_ id: ID, now: Date, current: ID?) -> Bool {
        guard isNews(id, now: now, current: current) else { return false }
        pulse = Mark(id, now + Self.pulseLength)
        return true
    }

    /// Starts showing a change of `id` inline in its pill, like `startPulse`, but not while its dropdown is open,
    /// which already shows it. A new change while one shows restarts the time.
    public mutating func startInline(_ id: ID, now: Date, current: ID?) -> Bool {
        guard isNews(id, now: now, current: current), current != id else { return false }
        inline = Mark(id, now + Self.inlineLength)
        return true
    }

    /// The pill showing its change inline at `now`, and when that can next end by itself. It stays past its time
    /// while the pointer is on it or its dropdown is open, so the pill does not shrink out from under the pointer.
    public mutating func inlined(now: Date, current: ID?) -> (id: ID?, recheck: Date?) {
        guard let inline else { return (nil, nil) }
        if inline.time > now { return (inline.id, inline.time) }
        if inside?.id == inline.id || current == inline.id { return (inline.id, nil) }
        self.inline = nil
        return (nil, nil)
    }

    private func isNews(_ id: ID, now: Date, current: ID?) -> Bool {
        now >= quietUntil && inside?.id != id && !(holding && current == id)
    }

    /// Waking from sleep reconnects the network and re-reads the power source, which is not news either.
    public mutating func woke(at now: Date) {
        quietUntil = max(quietUntil, now + 5)
    }

    public static var hoverIntent: TimeInterval { 0.04 }
    public static var linger: TimeInterval { 0.5 }
    public static var pulseLength: TimeInterval { 2.2 }
    public static var inlineLength: TimeInterval { 3 }

    /// The expanded pill at `now`, given the one expanded until now, and when the answer can next change by itself.
    public func owner(now: Date, current: ID?) -> (id: ID?, recheck: Date?) {
        // A pulse is news until the pointer comes to an item.
        let pointerSince = [inside?.time, left?.time].compactMap { $0 }.max()
        let pulseEnd = pulse.flatMap { $0.time > now && (pointerSince ?? .distantPast) < $0.time - Self.pulseLength ? $0.time : nil }
        // Intent applies only while nothing is open; re-entering the open pill keeps it without waiting again.
        let intentEnd = inside.flatMap { current != nil ? nil : $0.time + Self.hoverIntent }.flatMap { $0 > now ? $0 : nil }
        let lingerEnd = left.map { $0.time + Self.linger }.flatMap { $0 > now ? $0 : nil }
        if holding, let current { return (current, nil) }
        let id: ID? =
            if let inside, intentEnd == nil { inside.id }
            else if let pulse, pulseEnd != nil { pulse.id }
            else if let left, lingerEnd != nil, left.id == current { left.id }
            else { nil }
        return (id, [pulseEnd, intentEnd, lingerEnd].compactMap { $0 }.min())
    }
}
