import Foundation
import Subprocess

struct PipelineSummary: Equatable {
    var atlasCount: Int
    var imageCount: Int
}

struct SpritePackingPipeline {
    private var fileManager = FileManager.default
    var mode: SpritePackerMode
    init(mode: SpritePackerMode) {
        self.mode = mode
    }

    func run(input: URL, output: URL) async throws -> PipelineSummary {
        let config = try SpriteConfiguration.load(from: input)
        try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
        
        var atlasCount = 0
        for (key, blockSize) in config.atlases?.sorted(using: KeyPathComparator(\.key)) ?? [] {
            let directory = try safeInputURL(for: key, input: input)
            guard fileManager.isDirectory(atPath: directory.path) else {
                throw SpritePackerError.invalidConfiguration("Atlas directory '\(key)' does not exist")
            }

            let name = outputName(for: key)
            let images = try AtlasBuilder().loadImages(from: directory)
            guard !images.isEmpty else { continue }
            let packing = try ShelfPacker().pack(images.map {
                PackingItem(name: $0.name, size: $0.size)
            })
            let pngURL = output.appendingPathComponent("\(name).png")
            let plistURL = output.appendingPathComponent("\(name).plist")
            try AtlasBuilder().writeAtlas(images: images, packing: packing, to: pngURL)
            try PlistWriter().write(
                name: name,
                packing: packing,
                frameMetadata: Dictionary(
                    uniqueKeysWithValues: images.map { ($0.name, $0.frameMetadata) }
                ),
                textureFileName: mode.textureFileName(for: name),
                to: plistURL
            )
            try await encodeTexture(
                input: pngURL,
                name: name,
                outputDirectory: output,
                blockSize: blockSize
            )
            try fileManager.removeItem(at: pngURL)
            atlasCount += 1
        }

        var imageCount = 0
        for (key, blockSize) in config.images?.sorted(using: KeyPathComparator(\.key)) ?? [] {
            let sourceURL = try safeInputURL(for: key, input: input)
            guard fileManager.fileExists(atPath: sourceURL.path),
                  AtlasBuilder().loadImage(at: sourceURL) != nil else {
                throw SpritePackerError.unreadableImage(sourceURL.path)
            }
            let name = outputName(for: (key as NSString).deletingPathExtension)
            try await encodeTexture(
                input: sourceURL,
                name: name,
                outputDirectory: output,
                blockSize: blockSize
            )
            imageCount += 1
        }

        return PipelineSummary(atlasCount: atlasCount, imageCount: imageCount)
    }

    private func encodeTexture(
        input: URL,
        name: String,
        outputDirectory: URL,
        blockSize: ASTCBlockSize
    ) async throws {
        let astcURL = outputDirectory.appendingPathComponent("\(name).astc")
        try await encodeASTC(input: input, output: astcURL, blockSize: blockSize)
        guard mode.usesCCZ else { return }

        let cczURL = astcURL.appendingPathExtension("ccz")
        try CCZEncoder().encodeFile(at: astcURL, to: cczURL)
        try fileManager.removeItem(at: astcURL)
    }

    private func encodeASTC(input: URL, output: URL, blockSize: ASTCBlockSize) async throws {
        let result = try await Subprocess.run(
            .name("astcenc"),
            arguments: [
                "-cl",
                input.path,
                output.path,
                blockSize.rawValue,
                "-\(mode.astcencQuality)",
                "-yflip",
            ],
            output: .string(limit: 1_048_576),
            error: .string(limit: 1_048_576)
        )
        guard result.terminationStatus.isSuccess else {
            let status: Int32
            switch result.terminationStatus {
            case .exited(let code), .signaled(let code):
                status = code
            }
            throw SpritePackerError.astcencFailed(
                status,
                (result.standardError ?? "No error output")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private func safeInputURL(for relativePath: String, input: URL) throws -> URL {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else {
            throw SpritePackerError.invalidConfiguration("Paths must be non-empty and relative")
        }
        let candidate = input.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = input.standardizedFileURL.path
        guard candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") else {
            throw SpritePackerError.invalidConfiguration("Path '\(relativePath)' escapes the input directory")
        }
        return candidate
    }

    private func outputName(for relativePath: String) -> String {
        relativePath
            .split(separator: "/")
            .map(String.init)
            .joined(separator: "_")
    }
}

extension SpritePackerMode {
    fileprivate func textureFileName(for name: String) -> String {
        usesCCZ ? "\(name).astc.ccz" : "\(name).astc"
    }
}

extension FileManager {
    fileprivate func isDirectory(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
