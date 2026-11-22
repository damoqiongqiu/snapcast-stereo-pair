import Foundation

enum VolumeSliderGeometry {
    static let knobDiameter: CGFloat = 18
    static let trackHeight: CGFloat = 4
    static let controlHeight: CGFloat = 26
    static let trackInset = knobDiameter / 2

    static func x(for value: Double, in width: CGFloat) -> CGFloat {
        let bounds = trackBounds(in: width)
        let fraction = min(100, max(0, value)) / 100
        return bounds.lowerBound + (bounds.upperBound - bounds.lowerBound) * fraction
    }

    static func value(at x: CGFloat, in width: CGFloat) -> Double {
        let bounds = trackBounds(in: width)
        let span = bounds.upperBound - bounds.lowerBound
        guard span > 0 else { return 0 }
        let fraction = min(1, max(0, (x - bounds.lowerBound) / span))
        return Double(fraction) * 100
    }

    static func trackBounds(in width: CGFloat) -> ClosedRange<CGFloat> {
        let maximum = max(trackInset, width - trackInset)
        return trackInset...maximum
    }
}
