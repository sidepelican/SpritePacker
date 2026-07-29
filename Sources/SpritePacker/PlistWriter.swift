import Foundation

struct PlistWriter {
    func write(
        name: String,
        packing: PackingResult,
        frameMetadata: [String: FrameMetadata],
        textureFileName: String,
        to url: URL
    ) throws {
        precondition(Set(packing.frames.keys) == Set(frameMetadata.keys))
        
        let frames: [String: Any] = Dictionary(
            uniqueKeysWithValues: packing.frames.map { filename, rect in
                let source = frameMetadata[filename]!
                // astcenc receives -yflip, so frame coordinates must refer to
                // the vertically mirrored location in the resulting texture.
                let textureY = packing.size.height - rect.y - rect.height
                let right = source.sourceSize.width
                    - source.trimRect.x - source.trimRect.width
                let bottom = source.sourceSize.height
                    - source.trimRect.y - source.trimRect.height
                let offsetX = source.trimRect.x - right
                let offsetY = bottom - source.trimRect.y
                let meta = [
                    "frame": "{{\(rect.x),\(textureY)},{\(rect.width),\(rect.height)}}",
                    "offset": "{\(half(offsetX)),\(half(offsetY))}",
                    "rotated": false,
                    "sourceSize": "{\(source.sourceSize.width),\(source.sourceSize.height)}",
                ]
                return (filename, meta)
            }
        )
        
        let plist: [String: Any] = [
            "frames": frames,
            "metadata": [
                "format": 2,
                "realTextureFileName": textureFileName,
                "size": "{\(packing.size.width),\(packing.size.height)}",
                "textureFileName": textureFileName,
            ],
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: url, options: .atomic)
    }

    private func half(_ numerator: Int) -> String {
        if numerator.isMultiple(of: 2) {
            return String(numerator / 2)
        }
        return String(format: "%.1f", Double(numerator) / 2)
    }
}
