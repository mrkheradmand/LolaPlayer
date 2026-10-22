import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Preserve the artwork while adding transparent breathing room for Dock sizing.
guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: swift scripts/generate-icon.swift source.png destination.icns")
}
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let destinationURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil),
      artwork.width == artwork.height else {
    fatalError("Icon source must be a readable square image")
}

func appendLength(_ value: Int, to data: inout Data) {
    var length = UInt32(value).bigEndian
    withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
}

var chunks = Data()
for (type, pixels) in [("icp4", 16), ("icp5", 32), ("icp6", 64),
                       ("ic07", 128), ("ic08", 256), ("ic09", 512),
                       ("ic10", 1024), ("ic11", 32), ("ic12", 64),
                       ("ic13", 256), ("ic14", 512)] {
    guard let context = CGContext(data: nil, width: pixels, height: pixels,
                                  bitsPerComponent: 8, bytesPerRow: pixels * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("Unable to allocate icon bitmap")
    }
    context.interpolationQuality = .high
    let canvas = CGRect(x: 0, y: 0, width: pixels, height: pixels)
    let inset = CGFloat(pixels) * 0.08
    context.draw(artwork, in: canvas.insetBy(dx: inset, dy: inset))
    let png = NSMutableData()
    guard let image = context.makeImage(),
          let output = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Unable to create PNG representation")
    }
    CGImageDestinationAddImage(output, image, nil)
    guard CGImageDestinationFinalize(output) else { fatalError("Unable to encode icon PNG") }
    chunks.append(contentsOf: type.utf8)
    appendLength(png.length + 8, to: &chunks)
    chunks.append(png as Data)
}
var icon = Data("icns".utf8)
appendLength(chunks.count + 8, to: &icon)
icon.append(chunks)
try icon.write(to: destinationURL, options: .atomic)
print("Packaged macOS icon: \(destinationURL.path)")
