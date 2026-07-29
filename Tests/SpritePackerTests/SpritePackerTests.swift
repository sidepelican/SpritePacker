import AppKit
import CZlib
import Foundation
import Testing
@testable import SpritePacker

@Test func decodesConfiguration() throws {
    let data = Data(#"""
    {
      "atlases": { "characters/player": "6x6" },
      "images": { "logo.png": "4x4" }
    }
    """#.utf8)
    let configuration = try SpriteConfiguration.load(fromJSONData: data)
    #expect(configuration.atlases == ["characters/player": .`6x6`])
    #expect(configuration.images == ["logo.png": .`4x4`])
}

@Test func cczEncoderWritesCocos2dCompatibleHeaderAndZlibPayload() throws {
    let original = Data(repeating: 0x5A, count: 4_096)
    let ccz = try CCZEncoder().encode(original)

    #expect(Array(ccz.prefix(4)) == [0x43, 0x43, 0x5A, 0x21])
    #expect(readBigEndianUInt16(ccz, at: 4) == 0)
    #expect(readBigEndianUInt16(ccz, at: 6) == 2)
    #expect(readBigEndianUInt32(ccz, at: 8) == 0)
    #expect(readBigEndianUInt32(ccz, at: 12) == UInt32(original.count))

    var inflated = [UInt8](repeating: 0, count: original.count)
    var inflatedLength = uLongf(inflated.count)
    let payload = Data(ccz.dropFirst(16))
    let status = payload.withUnsafeBytes { compressed in
        inflated.withUnsafeMutableBytes { destination in
            uncompress(
                destination.bindMemory(to: Bytef.self).baseAddress,
                &inflatedLength,
                compressed.bindMemory(to: Bytef.self).baseAddress,
                uLong(compressed.count)
            )
        }
    }
    #expect(status == Z_OK)
    #expect(Data(inflated.prefix(Int(inflatedLength))) == original)
}

@Test func shelfPackingUsesPowerOfTwoDimensionsAndPadding() throws {
    let items = [
        PackingItem(name: "wide.png", size: PixelSize(width: 70, height: 20)),
        PackingItem(name: "square.png", size: PixelSize(width: 30, height: 30)),
        PackingItem(name: "small.png", size: PixelSize(width: 20, height: 10)),
    ]
    let result = try ShelfPacker(padding: 2).pack(items)
    #expect(result.size == PixelSize(width: 102, height: 32))
    #expect(result.frames.count == items.count)
    assertFramesAreValid(result, padding: 2)
}

@Test func maxRectsFillsSpaceThatWouldBeWastedByShelves() throws {
    let items = [
        PackingItem(name: "large.png", size: PixelSize(width: 60, height: 60)),
        PackingItem(name: "wide.png", size: PixelSize(width: 60, height: 30)),
        PackingItem(name: "small-a.png", size: PixelSize(width: 30, height: 30)),
        PackingItem(name: "small-b.png", size: PixelSize(width: 30, height: 30)),
    ]

    let result = try ShelfPacker(padding: 2).pack(items)

    // A height-sorted shelf at width 64 needs a 64x256 atlas for this set.
    #expect(result.size.width * result.size.height < 64 * 128)
    assertFramesAreValid(result, padding: 2)
}

@Test func multipleMaxRectsStrategiesAvoidGreedyFragmentation() throws {
    let sizes = [(24, 30), (22, 11), (19, 30), (23, 27), (10, 21)]
    let items = sizes.enumerated().map {
        PackingItem(
            name: "item-\($0.offset)",
            size: PixelSize(width: $0.element.0, height: $0.element.1)
        )
    }

    let result = try ShelfPacker(padding: 2).pack(items)

    // Best Short Side Fit alone fragments this case and misses 64x64.
    #expect(result.size.width * result.size.height < 64 * 64)
    assertFramesAreValid(result, padding: 2)
}

@Test func finalAtlasIsCroppedToTheMenuFixtureUsageBounds() throws {
    let sizes = [
        (69, 57), (71, 72), (79, 80), (71, 72), (79, 80), (75, 78),
        (88, 88), (50, 72), (62, 85), (50, 72), (62, 85), (62, 64),
        (48, 76), (60, 88), (68, 68), (82, 82), (49, 68), (63, 79),
        (80, 84), (93, 92), (64, 62), (64, 64), (74, 78), (86, 88),
    ]
    let items = sizes.enumerated().map {
        PackingItem(
            name: "menu-\($0.offset)",
            size: PixelSize(width: $0.element.0, height: $0.element.1)
        )
    }

    let result = try ShelfPacker(padding: 2).pack(items)

    #expect(result.size.width * result.size.height < 512 * 512)
    #expect(!result.size.width.isPowerOfTwo || !result.size.height.isPowerOfTwo)
    assertFramesAreValid(result, padding: 2)
}

@Test func plistHasCocos2dFormatTwoMetadata() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("ui.plist")
    let packing = PackingResult(
        size: PixelSize(width: 128, height: 64),
        frames: ["button.png": PixelRect(x: 2, y: 4, width: 20, height: 10)]
    )

    try PlistWriter().write(
        name: "ui",
        packing: packing,
        frameMetadata: ["button.png": .init(sourceSize: .init(width: 128, height: 64), trimRect: .init(x: 0, y: 0, width: 128, height: 64))],
        textureFileName: "ui.astc",
        to: url
    )
    let plist = try #require(
        PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
            as? [String: Any]
    )
    let metadata = try #require(plist["metadata"] as? [String: Any])
    let frames = try #require(plist["frames"] as? [String: Any])
    let button = try #require(frames["button.png"] as? [String: Any])

    #expect(metadata["format"] as? Int == 2)
    #expect(metadata["textureFileName"] as? String == "ui.astc")
    #expect(metadata["realTextureFileName"] as? String == "ui.astc")
    #expect(metadata["size"] as? String == "{128,64}")
    #expect(button["frame"] as? String == "{{2,50},{20,10}}")
}

@Test func transparentEdgesAreTrimmedAndRestoredByPlistMetadata() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let imageURL = directory.appendingPathComponent("trimmed.png")
    try makeImageData(
        width: 6,
        height: 8,
        fileType: .png,
        opaquePixels: { (1...2).contains($0) && (1...3).contains($1) }
    ).write(to: imageURL)

    let loaded = try #require(AtlasBuilder().loadImage(at: imageURL))
    #expect(loaded.size == PixelSize(width: 2, height: 3))
    #expect(loaded.frameMetadata.sourceSize == PixelSize(width: 6, height: 8))
    #expect(loaded.frameMetadata.trimRect == PixelRect(x: 1, y: 1, width: 2, height: 3))

    let plistURL = directory.appendingPathComponent("trimmed.plist")
    let packing = PackingResult(
        size: PixelSize(width: 2, height: 4),
        frames: ["trimmed.png": PixelRect(x: 0, y: 0, width: 2, height: 3)]
    )
    try PlistWriter().write(
        name: "trimmed",
        packing: packing,
        frameMetadata: ["trimmed.png": loaded.frameMetadata],
        textureFileName: "trimmed.astc",
        to: plistURL
    )
    let plist = try #require(
        PropertyListSerialization.propertyList(
            from: Data(contentsOf: plistURL),
            format: nil
        ) as? [String: Any]
    )
    let frames = try #require(plist["frames"] as? [String: Any])
    let frame = try #require(frames["trimmed.png"] as? [String: Any])
    #expect(frame["frame"] as? String == "{{0,1},{2,3}}")
    #expect(frame["sourceSize"] as? String == "{6,8}")
    #expect(frame["offset"] as? String == "{-1,1.5}")
}

@Test func atlasLoaderAcceptsAnyFormatSupportedByNSImage() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let tiffURL = directory.appendingPathComponent("sprite.tiff")
    try makeImageData(
        width: 3,
        height: 2,
        fileType: .tiff,
        opaquePixels: { _, _ in true }
    ).write(to: tiffURL)
    try Data("not an image".utf8).write(to: directory.appendingPathComponent("notes.txt"))

    let images = try AtlasBuilder().loadImages(from: directory)

    #expect(images.count == 1)
    #expect(images.first?.name == "sprite.tiff")
    #expect(images.first?.size == PixelSize(width: 3, height: 2))
}

@Test func atlasExtrudesFrameEdgesIntoThePadding() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let sourceURL = directory.appendingPathComponent("source.png")
    try makeImageData(
        width: 2,
        height: 2,
        fileType: .png,
        opaquePixels: { _, _ in true }
    ).write(to: sourceURL)
    let source = try #require(AtlasBuilder().loadImage(at: sourceURL))
    let atlasURL = directory.appendingPathComponent("atlas.png")
    try AtlasBuilder().writeAtlas(
        images: [source],
        packing: PackingResult(
            size: PixelSize(width: 4, height: 4),
            frames: ["source.png": PixelRect(x: 1, y: 1, width: 2, height: 2)]
        ),
        to: atlasURL
    )

    let atlas = try #require(AtlasBuilder().loadImage(at: atlasURL))
    #expect(atlas.size == PixelSize(width: 4, height: 4))
}

private func makeImageData(
    width: Int,
    height: Int,
    fileType: NSBitmapImageRep.FileType,
    opaquePixels: (_ x: Int, _ y: Int) -> Bool
) throws -> Data {
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
    for y in 0..<height {
        for x in 0..<width where opaquePixels(x, y) {
            let index = y * bytesPerRow + x * 4
            pixels[index] = 255
            pixels[index + 3] = 255
        }
    }
    let image = try pixels.withUnsafeMutableBytes { buffer in
        let context = try #require(CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        return try #require(context.makeImage())
    }
    return try #require(
        NSBitmapImageRep(cgImage: image).representation(using: fileType, properties: [:])
    )
}

private func assertFramesAreValid(
    _ result: PackingResult,
    padding: Int,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let values = Array(result.frames.values)
    for frame in values {
        #expect(frame.x >= 0 && frame.y >= 0, sourceLocation: sourceLocation)
        #expect(
            frame.x + frame.width <= result.size.width
                && frame.y + frame.height <= result.size.height,
            sourceLocation: sourceLocation
        )
    }
    for leftIndex in values.indices {
        for rightIndex in values.indices where rightIndex > leftIndex {
            let left = values[leftIndex]
            let right = values[rightIndex]
            let separated = left.x + left.width + padding <= right.x
                || right.x + right.width + padding <= left.x
                || left.y + left.height + padding <= right.y
                || right.y + right.height + padding <= left.y
            #expect(separated, sourceLocation: sourceLocation)
        }
    }
}

extension Int {
    fileprivate var isPowerOfTwo: Bool {
        self > 0 && (self & (self - 1)) == 0
    }
}

private func readBigEndianUInt16(_ data: Data, at offset: Int) -> UInt16 {
    UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
}

private func readBigEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
    UInt32(data[offset]) << 24
        | UInt32(data[offset + 1]) << 16
        | UInt32(data[offset + 2]) << 8
        | UInt32(data[offset + 3])
}
