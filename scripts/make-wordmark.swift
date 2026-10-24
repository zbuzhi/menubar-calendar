import AppKit
import CoreText
import Foundation

// Usage: swift scripts/make-wordmark.swift Resources/AppIcon.icon/Assets/wordmark.svg
// Store glyph outlines, not font files, so every build uses the exact reviewed lettering.
func outline(_ text: String,size: CGFloat,weight: String,spacing: CGFloat,center: CGPoint) -> CGPath {
    let font = NSFont(name:weight,size:size) ?? .systemFont(ofSize:size,weight:.semibold)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string:text,attributes:[.font:font,.kern:spacing]))
    let combined = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let actual = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating:0,count:count), positions = [CGPoint](repeating:.zero,count:count)
        CTRunGetGlyphs(run,CFRange(location:0,length:0),&glyphs)
        CTRunGetPositions(run,CFRange(location:0,length:0),&positions)
        for i in 0..<count {
            if let path = CTFontCreatePathForGlyph(actual,glyphs[i],nil) {
                combined.addPath(path,transform:CGAffineTransform(translationX:positions[i].x,y:positions[i].y))
            }
        }
    }
    let bounds = combined.boundingBoxOfPath
    var transform = CGAffineTransform(translationX:center.x-bounds.midX,y:center.y+bounds.midY).scaledBy(x:1,y:-1)
    return combined.copy(using:&transform)!
}
let mark = CGMutablePath()
mark.addPath(outline("不知时",size:120,weight:"PingFangSC-Medium",spacing:12,center:CGPoint(x:512,y:365)))
mark.addPath(outline("历",size:340,weight:"PingFangSC-Semibold",spacing:0,center:CGPoint(x:512,y:655)))
func n(_ value: CGFloat) -> String { String(format:"%.2f",value) }
var parts: [String] = []
mark.applyWithBlock { pointer in
    let e = pointer.pointee,p = e.points
    switch e.type {
    case .moveToPoint: parts.append("M\(n(p[0].x)) \(n(p[0].y))")
    case .addLineToPoint: parts.append("L\(n(p[0].x)) \(n(p[0].y))")
    case .addQuadCurveToPoint: parts.append("Q\(n(p[0].x)) \(n(p[0].y)) \(n(p[1].x)) \(n(p[1].y))")
    case .addCurveToPoint: parts.append("C\(n(p[0].x)) \(n(p[0].y)) \(n(p[1].x)) \(n(p[1].y)) \(n(p[2].x)) \(n(p[2].y))")
    case .closeSubpath: parts.append("Z")
    @unknown default: break
    }
}
let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"0 0 1024 1024\"><path fill=\"#30455B\" d=\"\(parts.joined(separator:" "))\"/></svg>"
try svg.write(toFile:CommandLine.arguments[1],atomically:true,encoding:.utf8)
