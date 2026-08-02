import Foundation

struct SpriteConfiguration: Decodable, Equatable {
    var atlases: [String: ASTCBlockSize]?
    var images: [String: ASTCBlockSize]?

    static func load(from inputDirectory: URL) throws -> Self {
        let url = inputDirectory.appendingPathComponent("sprite.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SpritePackerError.missingConfiguration(url.path)
        }
        return try load(fromJSONData: Data(contentsOf: url))
    }
    
    static func load(fromJSONData jsonData: Data) throws -> Self {
        do {
            let decoder = JSONDecoder()
            decoder.allowsJSON5 = true
            return try decoder.decode(Self.self, from: jsonData)
        } catch {
            throw SpritePackerError.invalidConfiguration("\(error)")
        }
    }

    func filtered(containing filter: String?) -> Self {
        guard let filter else { return self }
        return Self(
            atlases: atlases?.filter { $0.key.contains(filter) },
            images: images?.filter { $0.key.contains(filter) }
        )
    }
}

enum SpritePackerError: LocalizedError {
    case missingConfiguration(String)
    case invalidConfiguration(String)
    case invalidBlockSize(String)
    case unreadableImage(String)
    case imageTooLarge(String)
    case cannotCreateBitmap
    case cannotEncodePNG
    case duplicateFrameName(String)
    case astcencFailed(Int32, String)
    case cczInputTooLarge
    case cczCompressionFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration(let path):
            "sprite.json was not found at \(path)"
        case .invalidConfiguration(let message):
            "Invalid sprite.json: \(message)"
        case .invalidBlockSize(let size):
            "Invalid ASTC block size '\(size)'; expected values such as 4x4 or 6x6"
        case .unreadableImage(let path):
            "NSImage could not read the image at \(path)"
        case .imageTooLarge(let name):
            "Image '\(name)' cannot fit within the maximum atlas size"
        case .cannotCreateBitmap:
            "Could not create the atlas bitmap"
        case .cannotEncodePNG:
            "Could not encode the atlas as PNG"
        case .duplicateFrameName(let name):
            "Duplicate frame filename '\(name)' in an atlas"
        case .astcencFailed(let status, let message):
            "astcenc failed with exit code \(status): \(message)"
        case .cczInputTooLarge:
            "The ASTC file is too large for the 32-bit CCZ length field"
        case .cczCompressionFailed(let status):
            "CCZ zlib compression failed with status \(status)"
        }
    }
}
