// A final, colour-managed PNG layer. Coordinates are relative to the finished
// photograph (after crop/rotation/resize), with the origin at its top left.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct SignatureAsset: Codable, Hashable, Sendable {
    var id: UUID
    var name: String
}

struct SignatureSettings: Codable, Hashable, Sendable {
    var enabled = false
    var asset: SignatureAsset?
    var centerX: Double = 0.8
    var centerY: Double = 0.9
    var widthFraction: Double = 0.2
    var opacity: Double = 1

    init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, asset, centerX, centerY, widthFraction, opacity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        asset = try c.decodeIfPresent(SignatureAsset.self, forKey: .asset)
        centerX = try c.decodeIfPresent(Double.self, forKey: .centerX) ?? 0.8
        centerY = try c.decodeIfPresent(Double.self, forKey: .centerY) ?? 0.9
        widthFraction = try c.decodeIfPresent(Double.self, forKey: .widthFraction) ?? 0.2
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
    }
}

enum SignatureError: LocalizedError {
    case invalidPNG, tooLarge, missing(String), noPixels, digitalIntermediate
    var errorDescription: String? {
        switch self {
        case .invalidPNG: return "无法读取此 PNG 签名，请选择有效的 PNG 图片。"
        case .tooLarge: return "签名 PNG 过大，请使用不超过 128 MB、3200 万像素、单边 16384 像素的图片。"
        case .missing(let name): return "找不到签名“\(name)”，请重新导入，或关闭签名后导出。"
        case .noPixels: return "无法合成签名图层，请重新导入 PNG 后重试。"
        case .digitalIntermediate: return "数字中间片不支持签名，请关闭签名，或改用 JPEG、PNG、TIFF。"
        }
    }
}

/// Imported bytes have an immutable UUID filename. Moving the original PNG
/// does not break a recipe, and a new import cannot change an in-flight batch.
/// The directory is injectable so tests never use the person's signature library.
struct SignatureAssetStore: Sendable {
    let directory: URL
    static let shared = SignatureAssetStore(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "SpektraLab/SignatureAssets", directoryHint: .isDirectory))

    func importPNG(from url: URL) throws -> SignatureAsset {
        let data = try Self.readBounded(from: url)
        _ = try Self.decode(data)
        let asset = SignatureAsset(id: UUID(), name: url.lastPathComponent)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: self.url(for: asset), options: .atomic)
        return asset
    }

    func url(for asset: SignatureAsset) -> URL {
        directory.appending(path: asset.id.uuidString + ".png")
    }

    func image(for asset: SignatureAsset) throws -> CGImage {
        let data: Data
        do { data = try Self.readBounded(from: url(for: asset)) }
        catch let error as SignatureError { throw error }
        catch { throw SignatureError.missing(asset.name) }
        return try Self.decode(data)
    }

    private static func readBounded(from url: URL) throws -> Data {
        let limit = 128 * 1024 * 1024
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        // The file can grow between a size check and a read. Bound the read
        // itself; a mistaken multi-gigabyte selection never loads in full.
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw SignatureError.tooLarge }
        return data
    }

    private static func decode(_ data: Data) throws -> CGImage {
        guard data.count <= 128 * 1024 * 1024 else { throw SignatureError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0 else { throw SignatureError.invalidPNG }
        guard w <= 16384, h <= 16384, w * h <= 32_000_000 else { throw SignatureError.tooLarge }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0,
            [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            throw SignatureError.invalidPNG
        }
        return image
    }
}

enum SignatureCompositor {
    private static func bounded(_ value: Double, _ lower: Double, _ upper: Double,
                                fallback: Double) -> Double {
        min(upper, max(lower, value.isFinite ? value : fallback))
    }

    /// Top-left rectangle, shared by the drag hit target and file compositor.
    /// A tall signature is additionally limited by the photograph's height.
    static func rect(settings: SignatureSettings, photoSize: CGSize,
                     signatureSize: CGSize) -> CGRect {
        guard photoSize.width > 0, photoSize.height > 0,
              signatureSize.width > 0, signatureSize.height > 0 else { return .zero }
        let fraction = bounded(settings.widthFraction, 0.01, 1, fallback: 0.2)
        let w = min(photoSize.width * fraction,
                    photoSize.height * signatureSize.width / signatureSize.height)
        let h = w * signatureSize.height / signatureSize.width
        let cx = bounded(settings.centerX, w / (2 * photoSize.width),
                         1 - w / (2 * photoSize.width), fallback: 0.8) * photoSize.width
        let cy = bounded(settings.centerY, h / (2 * photoSize.height),
                         1 - h / (2 * photoSize.height), fallback: 0.9) * photoSize.height
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    /// Preserve the photo's output profile and 16-bit samples. PNG alpha is
    /// multiplied by the layer opacity using source-over. Core Graphics
    /// converts the PNG's own colour profile into this destination context.
    static func composite(_ base: CGImage, settings: SignatureSettings,
                          signature: CGImage?) throws -> CGImage {
        guard settings.enabled else { return base }
        guard let signature else { throw SignatureError.missing(settings.asset?.name ?? "PNG") }
        let alpha = bounded(settings.opacity, 0, 1, fallback: 1)
        guard alpha > 0 else { return base }
        let bits = base.bitsPerComponent > 8 ? 16 : 8
        let space = base.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        var info = CGImageAlphaInfo.noneSkipLast.rawValue
        if bits == 16 { info |= CGBitmapInfo.byteOrder16Little.rawValue }
        guard let ctx = CGContext(data: nil, width: base.width, height: base.height,
                                  bitsPerComponent: bits, bytesPerRow: 0, space: space,
                                  bitmapInfo: info) else { throw SignatureError.noPixels }
        // filePixels yields this exact layout. Copying keeps every sample
        // outside the signature unchanged, including low 16-bit detail.
        if base.bitsPerComponent == bits, base.bitsPerPixel == bits * 4,
           base.bitmapInfo.rawValue == info,
           let bytes = base.dataProvider?.data,
           let source = CFDataGetBytePtr(bytes), let destination = ctx.data,
           CFDataGetLength(bytes) >= base.bytesPerRow * base.height {
            for row in 0..<base.height {
                memcpy(destination.advanced(by: row * ctx.bytesPerRow),
                       source.advanced(by: row * base.bytesPerRow), base.width * bits / 2)
            }
        } else {
            ctx.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        }
        let rect = rect(settings: settings,
                        photoSize: CGSize(width: base.width, height: base.height),
                        signatureSize: CGSize(width: signature.width, height: signature.height))
        let destination = CGRect(x: rect.minX, y: CGFloat(base.height) - rect.maxY,
                                 width: rect.width, height: rect.height)
        ctx.interpolationQuality = .high
        ctx.setBlendMode(.normal)
        ctx.setAlpha(alpha)
        ctx.draw(signature, in: destination)
        guard let image = ctx.makeImage() else { throw SignatureError.noPixels }
        return image
    }

    static func composite(_ base: CGImage, settings: SignatureSettings,
                          assets: SignatureAssetStore = .shared) throws -> CGImage {
        guard settings.enabled else { return base }
        guard let asset = settings.asset else { throw SignatureError.missing("PNG") }
        return try composite(base, settings: settings, signature: assets.image(for: asset))
    }
}
