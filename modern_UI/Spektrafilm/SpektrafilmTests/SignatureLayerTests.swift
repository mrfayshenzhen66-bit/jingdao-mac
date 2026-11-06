// A signature is an output layer: transparent PNG pixels, final-photo
// coordinates and the output ICC all survive the trip to the written file.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@MainActor
final class SignatureLayerTests: XCTestCase {
    func testLayoutUsesFinalPhotoCoordinatesAcrossLandscapeAndPortrait() {
        var s = SignatureSettings()
        s.centerX = 0.75; s.centerY = 0.25; s.widthFraction = 0.2
        XCTAssertEqual(SignatureCompositor.rect(settings: s, photoSize: CGSize(width: 400, height: 300),
                        signatureSize: CGSize(width: 40, height: 20)),
                       CGRect(x: 260, y: 55, width: 80, height: 40))
        XCTAssertEqual(SignatureCompositor.rect(settings: s, photoSize: CGSize(width: 300, height: 400),
                        signatureSize: CGSize(width: 40, height: 20)),
                       CGRect(x: 195, y: 85, width: 60, height: 30))
    }

    func testLayoutStaysInsidePhotoEvenForTallAssetsAndOutOfRangeValues() {
        var s = SignatureSettings()
        s.centerX = -10; s.centerY = 5; s.widthFraction = 1
        let rect = SignatureCompositor.rect(settings: s, photoSize: CGSize(width: 400, height: 300),
                                             signatureSize: CGSize(width: 10, height: 100))
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 30, height: 300))
        s.centerX = .nan; s.centerY = .infinity; s.widthFraction = .nan
        let bounded = SignatureCompositor.rect(settings: s, photoSize: CGSize(width: 400, height: 300),
                                                signatureSize: CGSize(width: 40, height: 20))
        XCTAssertTrue(bounded.minX.isFinite && bounded.minY.isFinite && bounded.width.isFinite)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 400, height: 300).contains(bounded))
    }

    func testAlphaAndTopLeftPlacementPreserveUncovered16BitSamples() throws {
        let base = try SignatureTestFixture.base()
        let signature = try SignatureTestFixture.quadrants()
        let result = try SignatureCompositor.composite(base, settings: SignatureTestFixture.settings,
                                                       signature: signature)
        XCTAssertEqual(result.bitsPerComponent, 16)
        let pixels = try SignatureTestFixture.values(result)
        XCTAssertEqual(SignatureTestFixture.rgb(pixels, width: 400, x: 280, y: 65), [65535, 0, 0])
        XCTAssertEqual(SignatureTestFixture.rgb(pixels, width: 400, x: 280, y: 85), [0, 0, 65535])
        XCTAssertEqual(SignatureTestFixture.rgb(pixels, width: 400, x: 320, y: 85), [12345, 23456, 34567])
        XCTAssertEqual(SignatureTestFixture.rgb(pixels, width: 400, x: 11, y: 13), [12345, 23456, 34567])
        let halfGreen = SignatureTestFixture.rgb(pixels, width: 400, x: 320, y: 65)
        for (actual, expected) in zip(halfGreen, [6148, 44578, 17216]) {
            XCTAssertEqual(actual, expected, accuracy: 3, "PNG alpha must be premultiplied exactly once")
        }
    }

    func testLayerOpacityAndDisabledIdentity() throws {
        let base = try SignatureTestFixture.base()
        let signature = try SignatureTestFixture.quadrants()
        var settings = SignatureTestFixture.settings
        settings.enabled = false
        XCTAssertTrue(try SignatureCompositor.composite(base, settings: settings, signature: nil) === base)
        settings.enabled = true; settings.opacity = 0
        XCTAssertTrue(try SignatureCompositor.composite(base, settings: settings, signature: signature) === base)
        settings.opacity = 0.5
        let image = try SignatureCompositor.composite(base, settings: settings, signature: signature)
        let color = SignatureTestFixture.rgb(try SignatureTestFixture.values(image), width: 400, x: 280, y: 65)
        for (actual, expected) in zip(color, [38940, 11728, 17284]) {
            XCTAssertEqual(actual, expected, accuracy: 3)
        }
    }

    func testPNGProfileIsConvertedIntoOutputProfile() throws {
        let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let base = try SignatureTestFixture.base(space: p3)
        let result = try SignatureCompositor.composite(base, settings: SignatureTestFixture.settings,
                                                       signature: SignatureTestFixture.quadrants())
        let pixel = SignatureTestFixture.rgb(try SignatureTestFixture.values(result), width: 400, x: 280, y: 65)
        // Independent ColorSync CGColor conversion. Image conversion may
        // differ by ~11/65535 on macOS, while a missed conversion is thousands.
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 16,
                    bytesPerRow: 8, space: p3,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue))
        ctx.setFillColor(try XCTUnwrap(CGColor(colorSpace: SignatureTestFixture.sRGB, components: [1, 0, 0, 1])))
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let reference = SignatureTestFixture.rgb(try SignatureTestFixture.values(XCTUnwrap(ctx.makeImage())),
                                                  width: 1, x: 0, y: 0)
        for (actual, expected) in zip(pixel, reference) { XCTAssertEqual(actual, expected, accuracy: 32) }
        XCTAssertEqual(result.colorSpace?.name, p3.name)
        XCTAssertNotEqual(pixel, [65535, 0, 0], "sRGB code values must not simply acquire a P3 tag")
    }

    func testImportedAssetSurvivesMovingSourceAndNewImportDoesNotReplaceOldAsset() throws {
        let root = try SignatureTestFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SignatureAssetStore(directory: root.appending(path: "Assets"))
        let source = root.appending(path: "signature.png")
        try SignatureTestFixture.write(SignatureTestFixture.quadrants(), to: source, type: .png)
        let first = try store.importPNG(from: source)
        let second = try store.importPNG(from: source)
        XCTAssertNotEqual(first.id, second.id)
        try FileManager.default.moveItem(at: source, to: root.appending(path: "moved.png"))
        let reopened = SignatureAssetStore(directory: store.directory)
        XCTAssertEqual(try reopened.image(for: first).width, 40)
        XCTAssertEqual(try reopened.image(for: second).height, 20)
        XCTAssertThrowsError(try store.image(for: SignatureAsset(id: UUID(), name: "missing.png")))
        let invalid = root.appending(path: "invalid.png")
        try Data("not PNG".utf8).write(to: invalid)
        XCTAssertThrowsError(try store.importPNG(from: invalid))
    }

    func testRecipeRoundTripAndLegacyDefaults() throws {
        var recipe = ExportRecipe()
        recipe.signature = SignatureTestFixture.settings
        recipe.signature.asset = SignatureAsset(id: UUID(), name: "签名.png")
        let roundTrip = try JSONDecoder().decode(ExportRecipe.self, from: JSONEncoder().encode(recipe))
        XCTAssertEqual(roundTrip.signature, recipe.signature)
        let legacy = try JSONDecoder().decode(ExportRecipe.self, from: Data("{\"name\":\"old\"}".utf8))
        XCTAssertFalse(legacy.signature.enabled)
        XCTAssertThrowsError(try SignatureCompositor.composite(SignatureTestFixture.base(),
                    settings: recipe.signature, signature: nil), "An enabled missing asset cannot be silently omitted")
    }

    func testOversizeReadsAreRejectedForImportAndStoredAsset() throws {
        let root = try SignatureTestFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SignatureAssetStore(directory: root.appending(path: "Assets"))
        let source = root.appending(path: "oversize.png")
        XCTAssertTrue(FileManager.default.createFile(atPath: source.path, contents: nil))
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: 2 * 1024 * 1024 * 1024)
        try handle.close()
        XCTAssertThrowsError(try store.importPNG(from: source)) { error in
            guard case SignatureError.tooLarge = error else { return XCTFail("Wrong error: \(error)") }
        }
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let asset = SignatureAsset(id: UUID(), name: "oversize.png")
        try FileManager.default.moveItem(at: source, to: store.url(for: asset))
        XCTAssertThrowsError(try store.image(for: asset)) { error in
            guard case SignatureError.tooLarge = error else { return XCTFail("Wrong error: \(error)") }
        }
    }

    func test16BitTIFFReadbackRetainsCompositedPixels() throws {
        let root = try SignatureTestFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try SignatureCompositor.composite(SignatureTestFixture.base(),
                    settings: SignatureTestFixture.settings, signature: SignatureTestFixture.quadrants())
        let url = root.appending(path: "signed.tif")
        _ = try Exporter.write(result, to: url, format: .tiff)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let read = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(read.bitsPerComponent, 16)
        XCTAssertEqual(try SignatureTestFixture.values(read), SignatureTestFixture.values(result))
    }
}

enum SignatureTestFixture {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    static var settings: SignatureSettings {
        var s = SignatureSettings()
        s.enabled = true; s.centerX = 0.75; s.centerY = 0.25
        s.widthFraction = 0.2; s.opacity = 1
        return s
    }

    static func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "spk-signature-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func base(width: Int = 400, height: Int = 300, space: CGColorSpace = sRGB) throws -> CGImage {
        var pixels = [UInt16](repeating: 65535, count: width * height * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = 12345; pixels[i + 1] = 23456; pixels[i + 2] = 34567
        }
        let data = pixels.withUnsafeBytes { Data($0) }
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 16,
                    bitsPerPixel: 64, bytesPerRow: width * 8, space: space,
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue),
                    provider: XCTUnwrap(CGDataProvider(data: data as CFData)), decode: nil,
                    shouldInterpolate: false, intent: .defaultIntent))
    }

    static func quadrants() throws -> CGImage {
        var pixels = [UInt8](repeating: 0, count: 40 * 20 * 4)
        for y in 0..<20 {
            for x in 0..<40 {
                let i = (y * 40 + x) * 4
                if x < 20 { pixels[i + (y < 10 ? 0 : 2)] = 255; pixels[i + 3] = 255 }
                else if y < 10 { pixels[i + 1] = 128; pixels[i + 3] = 128 }
            }
        }
        return try XCTUnwrap(CGImage(width: 40, height: 20, bitsPerComponent: 8, bitsPerPixel: 32,
                    bytesPerRow: 160, space: sRGB,
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData)), decode: nil,
                    shouldInterpolate: false, intent: .defaultIntent))
    }

    static func write(_ image: CGImage, to url: URL, type: UTType) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    static func values(_ image: CGImage) throws -> [UInt16] {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
                    bitsPerComponent: 16, bytesPerRow: image.width * 8,
                    space: image.colorSpace ?? sRGB,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let ptr = try XCTUnwrap(ctx.data).bindMemory(to: UInt16.self, capacity: image.width * image.height * 4)
        return Array(UnsafeBufferPointer(start: ptr, count: image.width * image.height * 4))
    }

    static func rgb(_ pixels: [UInt16], width: Int, x: Int, y: Int) -> [Int] {
        let i = (y * width + x) * 4
        return (0..<3).map { Int(pixels[i + $0]) }
    }
}
