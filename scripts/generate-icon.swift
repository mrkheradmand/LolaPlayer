import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for (name, pixels) in [("icon_16x16",16), ("icon_16x16@2x",32), ("icon_32x32",32), ("icon_32x32@2x",64), ("icon_128x128",128), ("icon_128x128@2x",256), ("icon_256x256",256), ("icon_256x256@2x",512), ("icon_512x512",512), ("icon_512x512@2x",1024)] {
    let space = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 44, y: 44, width: 936, height: 936), cornerWidth: 210, cornerHeight: 210, transform: nil)); ctx.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.19, green: 0.15, blue: 0.50, alpha: 1), CGColor(red: 0.44, green: 0.40, blue: 0.94, alpha: 1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 90,y: 90), end: CGPoint(x: 900,y: 980), options: [])
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.32)); ctx.setLineWidth(16)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 208,y: 260,width: 608,height: 506), cornerWidth: 80, cornerHeight: 80, transform: nil)); ctx.strokePath()
    ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.move(to: CGPoint(x: 428,y: 370)); ctx.addLine(to: CGPoint(x: 428,y: 660)); ctx.addLine(to: CGPoint(x: 664,y: 515)); ctx.closePath(); ctx.fillPath()
    ctx.setFillColor(CGColor(red: 0.65, green: 0.83, blue: 1, alpha: 1)); ctx.move(to: CGPoint(x: 698,y: 260)); ctx.addLine(to: CGPoint(x: 698,y: 150)); ctx.addLine(to: CGPoint(x: 740,y: 184)); ctx.addLine(to: CGPoint(x: 782,y: 150)); ctx.addLine(to: CGPoint(x: 782,y: 260)); ctx.closePath(); ctx.fillPath()
    let file = destination.appendingPathComponent(name + ".png")
    let output = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(output, ctx.makeImage()!, nil); CGImageDestinationFinalize(output)
}
