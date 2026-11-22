import Foundation

enum VolumeScale {
    static let tickValues = Array(stride(from: 0, through: 100, by: 5))
    static let labeledValues = [0, 25, 50, 75, 100]

    static func fraction(for value: Int) -> Double {
        Double(min(max(value, 0), 100)) / 100
    }
}
