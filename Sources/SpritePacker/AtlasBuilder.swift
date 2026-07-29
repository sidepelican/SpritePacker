import AppKit
import Foundation

struct LoadedImage {
    var name: String
    var image: NSImage
    var size: PixelSize {
        PixelSize(width: frameMetadata.trimRect.width, height: frameMetadata.trimRect.height)
    }
    var frameMetadata: FrameMetadata
}

struct FrameMetadata: Equatable {
    var sourceSize: PixelSize
    /// Visible pixel bounds in source-image coordinates, with a top-left origin.
    var trimRect: PixelRect
}

struct AtlasBuilder {
    private let extrusion = 1

    func loadImages(from directory: URL) throws -> [LoadedImage] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }

        var names = Set<String>()
        return try urls.compactMap { url in
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
                  let loaded = loadImage(at: url) else {
                return nil
            }
            guard names.insert(url.lastPathComponent).inserted else {
                throw SpritePackerError.duplicateFrameName(url.lastPathComponent)
            }
            return loaded
        }
    }

    func loadImage(at url: URL) -> LoadedImage? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ), cgImage.width > 0, cgImage.height > 0 else {
            return nil
        }
        guard let trimmed = trimTransparentEdges(of: cgImage) else { return nil }
        return LoadedImage(
            name: url.lastPathComponent,
            image: NSImage(
                cgImage: trimmed.image,
                size: NSSize(width: trimmed.rect.width, height: trimmed.rect.height)
            ),
            frameMetadata: FrameMetadata(
                sourceSize: PixelSize(width: cgImage.width, height: cgImage.height),
                trimRect: trimmed.rect
            )
        )
    }

    private func trimTransparentEdges(of source: CGImage) -> (image: CGImage, rect: PixelRect)? {
        let width = source.width
        let height = source.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        var normalizedImage: CGImage?

        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(alpha: .premultipliedLast, byteOrder: .order32Big)
            ) else {
                return
            }
            // Normalize all NSImage-backed formats to top-to-bottom RGBA pixels.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            normalizedImage = context.makeImage()
        }
        guard let normalizedImage else { return nil }

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[y * bytesPerRow + x * 4 + 3] != 0 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        // Keep a transparent 1x1 frame so fully transparent source images remain addressable.
        let pixelRect = maxX < minX
            ? PixelRect(x: 0, y: 0, width: 1, height: 1)
            : PixelRect(
                x: minX,
                y: minY,
                width: maxX - minX + 1,
                height: maxY - minY + 1
            )
        guard let cropped = normalizedImage.cropping(to: CGRect(
            x: pixelRect.x,
            y: pixelRect.y,
            width: pixelRect.width,
            height: pixelRect.height
        )) else {
            return nil
        }
        // CGContext bitmap rows are bottom-origin here, while TexturePacker
        // metadata expresses the trimmed source rectangle from the top edge.
        let metadataRect = PixelRect(
            x: pixelRect.x,
            y: height - pixelRect.y - pixelRect.height,
            width: pixelRect.width,
            height: pixelRect.height
        )
        return (cropped, metadataRect)
    }

    func writeAtlas(images: [LoadedImage], packing: PackingResult, to url: URL) throws {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: packing.size.width,
            pixelsHigh: packing.size.height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw SpritePackerError.cannotCreateBitmap
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: packing.size.width, height: packing.size.height))
        context.imageInterpolation = .none

        for loaded in images {
            guard let frame = packing.frames[loaded.name] else { continue }
            draw(image: loaded.image, frame: frame, atlasSize: packing.size)
            drawExtrusion(image: loaded.image, frame: frame, atlasSize: packing.size)
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw SpritePackerError.cannotEncodePNG
        }
        try data.write(to: url, options: .atomic)
    }

    private func draw(image: NSImage, frame: PixelRect, atlasSize: PixelSize) {
        draw(
            image: image,
            source: NSRect(x: 0, y: 0, width: frame.width, height: frame.height),
            destination: frame,
            atlasSize: atlasSize
        )
    }

    private func drawExtrusion(
        image: NSImage,
        frame: PixelRect,
        atlasSize: PixelSize
    ) {
        guard extrusion > 0 else { return }
        let e = extrusion
        let sourceWidth = frame.width
        let sourceHeight = frame.height

        if frame.y >= e {
            draw(
                image: image,
                source: NSRect(x: 0, y: sourceHeight - e, width: sourceWidth, height: e),
                destination: PixelRect(
                    x: frame.x, y: frame.y - e, width: frame.width, height: e
                ),
                atlasSize: atlasSize
            )
        }
        if frame.y + frame.height + e <= atlasSize.height {
            draw(
                image: image,
                source: NSRect(x: 0, y: 0, width: sourceWidth, height: e),
                destination: PixelRect(
                    x: frame.x, y: frame.y + frame.height, width: frame.width, height: e
                ),
                atlasSize: atlasSize
            )
        }
        if frame.x >= e {
            draw(
                image: image,
                source: NSRect(x: 0, y: 0, width: e, height: sourceHeight),
                destination: PixelRect(
                    x: frame.x - e, y: frame.y, width: e, height: frame.height
                ),
                atlasSize: atlasSize
            )
        }
        if frame.x + frame.width + e <= atlasSize.width {
            draw(
                image: image,
                source: NSRect(x: sourceWidth - e, y: 0, width: e, height: sourceHeight),
                destination: PixelRect(
                    x: frame.x + frame.width, y: frame.y, width: e, height: frame.height
                ),
                atlasSize: atlasSize
            )
        }

        let corners = [
            (
                source: NSRect(x: 0, y: sourceHeight - e, width: e, height: e),
                destination: PixelRect(
                    x: frame.x - e, y: frame.y - e, width: e, height: e
                )
            ),
            (
                source: NSRect(
                    x: sourceWidth - e, y: sourceHeight - e, width: e, height: e
                ),
                destination: PixelRect(
                    x: frame.x + frame.width, y: frame.y - e, width: e, height: e
                )
            ),
            (
                source: NSRect(x: 0, y: 0, width: e, height: e),
                destination: PixelRect(
                    x: frame.x - e, y: frame.y + frame.height, width: e, height: e
                )
            ),
            (
                source: NSRect(x: sourceWidth - e, y: 0, width: e, height: e),
                destination: PixelRect(
                    x: frame.x + frame.width,
                    y: frame.y + frame.height,
                    width: e,
                    height: e
                )
            ),
        ]
        for corner in corners
        where corner.destination.x >= 0
            && corner.destination.y >= 0
            && corner.destination.x + e <= atlasSize.width
            && corner.destination.y + e <= atlasSize.height {
            draw(
                image: image,
                source: corner.source,
                destination: corner.destination,
                atlasSize: atlasSize
            )
        }
    }

    private func draw(
        image: NSImage,
        source: NSRect,
        destination: PixelRect,
        atlasSize: PixelSize
    ) {
        // AppKit draws from the lower-left; packed coordinates start at top-left.
        let drawY = atlasSize.height - destination.y - destination.height
        image.draw(
            in: NSRect(
                x: destination.x,
                y: drawY,
                width: destination.width,
                height: destination.height
            ),
            from: source,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.none]
        )
    }
}
