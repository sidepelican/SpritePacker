import ArgumentParser
import Foundation

enum SpritePackerMode: String, CaseIterable, ExpressibleByArgument {
    case preview
    case release

    var astcencQuality: String {
        switch self {
        case .preview:
            "fast"
        case .release:
            "exhaustive"
        }
    }

    var usesCCZ: Bool { self == .release }
}

@main
struct SpritePacker: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "SpritePacker",
        abstract: "Build Cocos2d-x sprite atlases and ASTC textures."
    )

    @Argument(help: "Directory containing sprite.json and the source image files or subdirectories.")
    var inputDirectory: String

    @Option(name: [.short, .long], help: "Destination directory. Defaults to <input>/output.")
    var outputDirectory: String?

    @Option(
        name: [.short, .long],
        help: "Compression mode: preview uses astcenc -fast; release uses -exhaustive."
    )
    var mode: SpritePackerMode = .release

    mutating func run() async throws {
        let inputURL = URL(fileURLWithPath: inputDirectory).standardizedFileURL
        let outputURL = outputDirectory.map {
            URL(fileURLWithPath: $0).standardizedFileURL
        } ?? inputURL.appendingPathComponent("output", isDirectory: true)

        do {
            let summary = try await SpritePackingPipeline(mode: mode).run(
                input: inputURL,
                output: outputURL
            )
            print("Generated \(summary.atlasCount) atlas(es) and \(summary.imageCount) standalone texture(s) in \(outputURL.path)")
        } catch {
            throw ValidationError(error.localizedDescription)
        }
    }
}
