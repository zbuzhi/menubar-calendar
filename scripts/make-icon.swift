import AppKit
import Foundation

// Static fallback from the same native layered design. Used when actool is unavailable.
let output = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
let source = URL(fileURLWithPath:CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "Resources/Branding/AppIcon.png")
guard let icon = NSImage(contentsOf:source) else { fatalError("Missing brand icon: \(source.path)") }
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
var sizes: [Int: Data] = [:]
for size in [16,32,64,128,256,512,1024] {
    let context = CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:size * 4,
                            space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext:context,flipped:false)
    context.interpolationQuality = .high
    let inset = CGFloat(size) * 0.10
    icon.draw(in:NSRect(x:inset,y:inset,width:CGFloat(size)-inset*2,height:CGFloat(size)-inset*2))
    NSGraphicsContext.restoreGraphicsState()
    let png = NSBitmapImageRep(cgImage:context.makeImage()!).representation(using:.png,properties:[:])!
    sizes[size] = png
    for name in [16:["icon_16x16.png"],32:["icon_16x16@2x.png","icon_32x32.png"],64:["icon_32x32@2x.png"],
                 128:["icon_128x128.png"],256:["icon_128x128@2x.png","icon_256x256.png"],
                 512:["icon_256x256@2x.png","icon_512x512.png"],1024:["icon_512x512@2x.png"]][size]! {
        try png.write(to:output.appendingPathComponent(name))
    }
}
if CommandLine.arguments.count > 2 {
    var chunks = Data()
    for (kind,size) in [("icp4",16),("icp5",32),("icp6",64),("ic07",128),("ic08",256),("ic09",512),("ic10",1024),("ic11",32),("ic12",64)] {
        let png = sizes[size]!
        chunks.append(kind.data(using:.ascii)!)
        var length = UInt32(png.count + 8).bigEndian
        withUnsafeBytes(of:&length) { chunks.append(contentsOf:$0) }; chunks.append(png)
    }
    var result = Data("icns".utf8), length = UInt32(chunks.count + 8).bigEndian
    withUnsafeBytes(of:&length) { result.append(contentsOf:$0) }; result.append(chunks)
    try result.write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
}
