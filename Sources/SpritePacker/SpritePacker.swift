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

    @Option(help: "Only process atlas or image keys containing this string.")
    var filter: String?

    mutating func run() async throws {
        let inputURL = URL(fileURLWithPath: inputDirectory).standardizedFileURL
        let outputURL = outputDirectory.map {
            URL(fileURLWithPath: $0).standardizedFileURL
        } ?? inputURL.appendingPathComponent("output", isDirectory: true)

        do {
            let summary = try await SpritePackingPipeline(mode: mode, filter: filter).run(
                input: inputURL,
                output: outputURL
            )
            let message = AttributedString(
                localized: "Generated ^[\(summary.atlasCount) atlas](inflect: true) and ^[\(summary.imageCount) standalone texture](inflect: true) in \(outputURL.path)"
            )
            print(String(message.characters))
        } catch {
            throw ValidationError(error.localizedDescription)
        }
    }
}
