// Build the personal icon from the approved enclosure and the official macOS
// logo rendition. All colour conversions and resampling precede RGB inversion.
// Usage: swift make-personal-icon.swift APPROVED_PNG OFFICIAL_APP OUTPUT_DIR
import AppKit
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 4 else { fatalError("usage: make-personal-icon.swift APPROVED_PNG OFFICIAL_APP OUTPUT_DIR") }
let output = URL(fileURLWithPath: args[3], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let rgba = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

func context(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
              bytesPerRow: w * 4, space: space, bitmapInfo: rgba)!
}
func write(_ image: CGImage, _ name: String) throws {
    let url = output.appendingPathComponent(name)
    guard !FileManager.default.fileExists(atPath: url.path) else { fatalError("Refusing to overwrite \(url.path)") }
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("PNG write failed") }
}
func render(_ image: CGImage, width: Int, height: Int, white: Bool = false) -> CGContext {
    let ctx = context(width, height)
    if white { ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height)) }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return ctx
}
func bytes(_ ctx: CGContext) -> [UInt8] {
    Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: ctx.bytesPerRow * ctx.height))
}
func image(_ values: [UInt8], width: Int, height: Int) -> CGImage {
    CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: space, bitmapInfo: CGBitmapInfo(rawValue: rgba),
            provider: CGDataProvider(data: Data(values) as CFData)!, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent)!
}

let official = URL(fileURLWithPath: args[2])
guard FileManager.default.fileExists(atPath: official.path) else { fatalError("Official bundle missing") }
let nativeIcon = NSWorkspace.shared.icon(forFile: official.path)
let largest = nativeIcon.representations.map(\.pixelsWide).max() ?? 0
let nativeSize = min(max(largest, 1024), 2048)
let nativeContext = context(nativeSize, nativeSize)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: nativeContext, flipped: false)
nativeIcon.draw(in: NSRect(x: 0, y: 0, width: nativeSize, height: nativeSize),
                from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
let native = nativeContext.makeImage()!
try write(native, "OfficialLogo-sRGB.png")

// Crop the original's four bands, including their native overlap and shadow;
// leave the wallet housing and amber film border outside this aperture.
let factor = CGFloat(nativeSize) / 512
let crop = native.cropping(to: CGRect(x: 65 * factor, y: 72 * factor,
                                      width: 382 * factor, height: 370 * factor))!
let size = 1024
let aperture = (x: 241, y: 251, w: 530, h: 369) // top-left pixel coordinates
let positive = bytes(render(crop, width: aperture.w, height: aperture.h, white: true))
precondition(stride(from: 3, to: positive.count, by: 4).allSatisfy { positive[$0] == 255 })
var negative = positive
for p in stride(from: 0, to: positive.count, by: 4) {
    for channel in 0..<3 { negative[p + channel] = 255 - positive[p + channel] }
}

let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil)!
let base = bytes(render(CGImageSourceCreateImageAtIndex(source, 0, nil)!, width: size, height: size))
func insert(_ field: [UInt8]) -> [UInt8] {
    var result = base
    for y in 0..<aperture.h {
        let destination = ((aperture.y + y) * size + aperture.x) * 4
        let start = y * aperture.w * 4
        result.replaceSubrange(destination..<(destination + aperture.w * 4), with: field[start..<(start + aperture.w * 4)])
    }
    return result
}
let final = insert(negative)
let positiveIcon = insert(positive)
try write(image(positive, width: aperture.w, height: aperture.h), "Logo-positive-sRGB.png")
try write(image(negative, width: aperture.w, height: aperture.h), "Logo-negative-sRGB.png")
try write(image(final, width: size, height: size), "AppIcon.png")
try write(image(positiveIcon, width: size, height: size), "AppIcon-positive-reference.png")

// Read the actual encoded final PNG back through the same explicit sRGB
// context. A tint, alpha blend, or second colour conversion after inversion
// would fail this comparison against the final-size positive reference.
let encoded = CGImageSourceCreateWithURL(output.appendingPathComponent("AppIcon.png") as CFURL, nil)!
let decoded = bytes(render(CGImageSourceCreateImageAtIndex(encoded, 0, nil)!, width: size, height: size))
var maxError = 0
var outsideChanges = 0
for y in 0..<size {
    for x in 0..<size {
        let p = (y * size + x) * 4
        if x >= aperture.x && x < aperture.x + aperture.w && y >= aperture.y && y < aperture.y + aperture.h {
            let q = ((y - aperture.y) * aperture.w + x - aperture.x) * 4
            for c in 0..<3 { maxError = max(maxError, abs((255 - Int(decoded[p + c])) - Int(positive[q + c]))) }
            precondition(decoded[p + 3] == 255)
        } else if final[p..<(p + 4)] != base[p..<(p + 4)] { outsideChanges += 1 }
    }
}
precondition(maxError == 0 && outsideChanges == 0, "Inversion or enclosure preservation failed")
let record: [String: Any] = [
    "space": "sRGB IEC61966-2.1", "nativeLargestRendition": largest,
    "nativeRenderedSize": nativeSize, "nativeUpscaled": nativeSize > largest,
    "finalSize": size, "aperture": [aperture.x, aperture.y, aperture.w, aperture.h],
    "verifiedRGBSamples": aperture.w * aperture.h * 3,
    "maxRestorationError8bit": maxError, "enclosurePixelsChanged": outsideChanges,
    "formula": "negativeRGB = 255 - positiveRGB; alpha unchanged",
    "scope": "Logo aperture only. Wallet, film border and badge are not inverted."
]
try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("color-verification.json"))
print(String(data: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), encoding: .utf8)!)
