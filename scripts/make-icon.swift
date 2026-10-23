import AppKit
import Foundation

let output = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
for size in [16,32,64,128,256,512,1024] {
    let image = NSImage(size:NSSize(width:size,height:size))
    image.lockFocus()
    let scale = CGFloat(size)/1024
    NSAffineTransform(scale:scale).concat()
    let rect = NSRect(x:48,y:48,width:928,height:928)
    let shape = NSBezierPath(roundedRect:rect,xRadius:210,yRadius:210)
    NSGradient(colors:[NSColor(calibratedRed:0.22,green:0.60,blue:1,alpha:1),NSColor(calibratedRed:0.17,green:0.29,blue:0.8,alpha:1)])!.draw(in:shape,angle:-70)
    let page = NSRect(x:192,y:190,width:640,height:646)
    NSColor.white.withAlphaComponent(0.95).setFill()
    NSBezierPath(roundedRect:page,xRadius:94,yRadius:94).fill()
    NSColor(calibratedRed:0.9,green:0.95,blue:1,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:192,y:674,width:640,height:162),xRadius:60,yRadius:60).fill()
    for x in [350,674] {
        NSColor(calibratedRed:0.19,green:0.36,blue:0.72,alpha:1).setFill()
        NSBezierPath(roundedRect:NSRect(x:x-16,y:756,width:32,height:124),xRadius:16,yRadius:16).fill()
    }
    let number:NSString = "廿一"
    let attrs:[NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:192,weight:.medium),.foregroundColor:NSColor(calibratedRed:0.12,green:0.3,blue:0.65,alpha:1)]
    let textSize = number.size(withAttributes:attrs)
    number.draw(at:NSPoint(x:(1024-textSize.width)/2,y:345),withAttributes:attrs)
    NSColor(calibratedRed:0.9,green:0.64,blue:0.35,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:425,y:271,width:174,height:14),xRadius:7,yRadius:7).fill()
    image.unlockFocus()
    let rep = NSBitmapImageRep(data:image.tiffRepresentation!)!
    let data = rep.representation(using:.png,properties:[:])!
    let name:String
    switch size {
    case 16:name="icon_16x16.png"
    case 32:name="icon_16x16@2x.png"
    case 64:name="icon_32x32@2x.png"
    case 128:name="icon_128x128.png"
    case 256:name="icon_128x128@2x.png"
    case 512:name="icon_256x256@2x.png"
    default:name="icon_512x512@2x.png"
    }
    try data.write(to:output.appendingPathComponent(name))
    if size == 32 { try data.write(to:output.appendingPathComponent("icon_32x32.png")) }
    if size == 256 { try data.write(to:output.appendingPathComponent("icon_256x256.png")) }
    if size == 512 { try data.write(to:output.appendingPathComponent("icon_512x512.png")) }
}
extension NSAffineTransform {
    convenience init(scale:CGFloat) { self.init(); scaleX(by:scale,yBy:scale) }
}

// Modern ICNS PNG chunks. This also works where iconutil is unavailable.
if CommandLine.arguments.count > 2 {
    var chunks = Data()
    for (kind,name) in [("ic07","icon_128x128.png"),("ic08","icon_256x256.png"),("ic09","icon_512x512.png"),("ic10","icon_512x512@2x.png")] {
        let png = try Data(contentsOf:output.appendingPathComponent(name))
        chunks.append(kind.data(using:.ascii)!)
        var length = UInt32(png.count + 8).bigEndian
        withUnsafeBytes(of:&length) { chunks.append(contentsOf:$0) }
        chunks.append(png)
    }
    var icns = Data("icns".utf8)
    var length = UInt32(chunks.count + 8).bigEndian
    withUnsafeBytes(of:&length) { icns.append(contentsOf:$0) }
    icns.append(chunks)
    try icns.write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
}
