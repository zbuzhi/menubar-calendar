import Foundation

public struct RGBColor {
    public let red: Double
    public let green: Double
    public let blue: Double
    public init(_ red: Double,_ green: Double,_ blue: Double) { self.red = red; self.green = green; self.blue = blue }
    public var luminance: Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value/12.92 : pow((value+0.055)/1.055,2.4) }
        return 0.2126*linear(red) + 0.7152*linear(green) + 0.0722*linear(blue)
    }
    public func contrast(with other: RGBColor) -> Double { (max(luminance,other.luminance)+0.05)/(min(luminance,other.luminance)+0.05) }
}
public enum ThemeColors {
    public static let names = ["blue","green","orange","purple","teal","indigo","rose","plum","gold","olive","slate","bronze"]
    public static func title(_ name: String) -> String {
        ["blue":"海蓝","green":"松绿","orange":"琥珀","purple":"鸢紫","teal":"青碧","indigo":"靛青",
         "rose":"雾玫","plum":"梅紫","gold":"鎏金","olive":"橄榄","slate":"石墨","bronze":"古铜"][name] ?? "海蓝"
    }
    private static func rgb(_ hex: UInt32) -> RGBColor {
        RGBColor(Double((hex >> 16) & 255)/255,Double((hex >> 8) & 255)/255,Double(hex & 255)/255)
    }
    public static func selection(_ name: String) -> RGBColor {
        switch name {
        case "green": return RGBColor(0.06,0.40,0.26)
        case "orange": return RGBColor(0.64,0.29,0.035)
        case "purple": return RGBColor(0.46,0.22,0.68)
        case "teal": return RGBColor(0.025,0.39,0.43)
        case "indigo": return rgb(0x454C98)
        case "rose": return rgb(0xA04462)
        case "plum": return rgb(0x824768)
        case "gold": return rgb(0x866322)
        case "olive": return rgb(0x626A32)
        case "slate": return rgb(0x4C5967)
        case "bronze": return rgb(0x885A41)
        default: return RGBColor(0.025,0.34,0.74)
        }
    }
    public static func ink(_ name: String, dark: Bool) -> RGBColor {
        guard dark else { return selection(name) }
        switch name {
        case "green": return RGBColor(0.36,0.82,0.60)
        case "orange": return RGBColor(1,0.71,0.37)
        case "purple": return RGBColor(0.78,0.61,1)
        case "teal": return RGBColor(0.34,0.80,0.86)
        case "indigo": return rgb(0xA8B5FF)
        case "rose": return rgb(0xF2A4BD)
        case "plum": return rgb(0xD7A4CB)
        case "gold": return rgb(0xE3C16F)
        case "olive": return rgb(0xBDCB89)
        case "slate": return rgb(0xB7C5D3)
        case "bronze": return rgb(0xDDB49B)
        default: return RGBColor(0.38,0.70,1)
        }
    }
}
