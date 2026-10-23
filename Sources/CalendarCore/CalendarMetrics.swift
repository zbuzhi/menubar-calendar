import Foundation

public enum CalendarMetrics {
    public static let dateFontSize = 16.0
    public static let iconSizeRange = 4.0...dateFontSize
    public static func iconSize(_ value: Double) -> Double {
        guard value.isFinite else { return 6 }
        return min(iconSizeRange.upperBound,max(iconSizeRange.lowerBound,value))
    }
}
