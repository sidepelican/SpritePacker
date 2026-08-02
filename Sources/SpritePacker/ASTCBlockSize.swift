nonisolated(unsafe) private let regex = /[0-9]{1,2}x[0-9]{1,2}/

struct ASTCBlockSize: LosslessStringConvertible, Codable, Hashable, Sendable {
    init?(_ rawValue: String) {
        guard let _ = rawValue.wholeMatch(of: regex) else {
            return nil
        }
        description = rawValue
    }

    var description: String

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if let decoded = Self(rawValue) {
            self = decoded
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid ASTC block size format: '\(rawValue)'. Expected format is 'x' (e.g., '4x4', '10x8')."
                )
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        try description.encode(to: encoder)
    }

    static var `4x4`: Self {
        .init("4x4")!
    }

    static var `6x6`: Self {
        .init("6x6")!
    }

    static var `8x8`: Self {
        .init("8x8")!
    }
}
