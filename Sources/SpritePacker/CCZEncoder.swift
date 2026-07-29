import CZlib
import Foundation

struct CCZEncoder {
    func encode(_ input: Data) throws -> Data {
        guard input.count <= UInt32.max else {
            throw SpritePackerError.cczInputTooLarge
        }

        var compressed = [UInt8](
            repeating: 0,
            count: Int(compressBound(uLong(input.count)))
        )
        var compressedLength = uLongf(compressed.count)
        let status = input.withUnsafeBytes { source in
            compressed.withUnsafeMutableBytes { destination in
                compress2(
                    destination.bindMemory(to: Bytef.self).baseAddress,
                    &compressedLength,
                    source.bindMemory(to: Bytef.self).baseAddress,
                    uLong(input.count),
                    Z_BEST_COMPRESSION
                )
            }
        }
        guard status == Z_OK else {
            throw SpritePackerError.cczCompressionFailed(status)
        }

        var result = Data()
        result.reserveCapacity(16 + Int(compressedLength))
        result.append(contentsOf: [0x43, 0x43, 0x5A, 0x21]) // CCZ!
        appendBigEndian(UInt16(0), to: &result) // CCZ_COMPRESSION_ZLIB
        appendBigEndian(UInt16(2), to: &result)
        appendBigEndian(UInt32(0), to: &result)
        appendBigEndian(UInt32(input.count), to: &result)
        result.append(contentsOf: compressed.prefix(Int(compressedLength)))
        return result
    }

    func encodeFile(at inputURL: URL, to outputURL: URL) throws {
        try encode(Data(contentsOf: inputURL)).write(to: outputURL, options: .atomic)
    }

    private func appendBigEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }
}
