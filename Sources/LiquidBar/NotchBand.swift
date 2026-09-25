import SwiftUI

/// Opaque black band that grows out of the notch to the full bar width, so the notch looks like it spread across
/// the strip. At rest it is exactly the notch (hidden behind the hardware); on a screen without a notch it grows
/// from a zero-width point at the center.
struct NotchBand: View {
    let extended: Bool
    /// The notch's horizontal extent in bar coordinates.
    let notch: ClosedRange<CGFloat>?
    let restingHeight: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let full = geometry.size
            let center = notch.map { ($0.lowerBound + $0.upperBound) / 2 } ?? full.width / 2
            let width = extended ? full.width : notch.map { $0.upperBound - $0.lowerBound } ?? 0
            let height = extended || notch == nil ? full.height : restingHeight
            UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous)
                .fill(.black)
                .frame(width: width, height: height)
                .position(x: extended ? full.width / 2 : center, y: height / 2)
        }
        .allowsHitTesting(false)
    }
}
