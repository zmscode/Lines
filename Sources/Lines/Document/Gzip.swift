import Foundation

/// gzip, for .svgz files: SVG compressed with DEFLATE in a gzip wrapper
/// (RFC 1952). Foundation's `.zlib` algorithm is raw DEFLATE, so this adds
/// the header and the CRC-32 and length trailer.
enum Gzip {
	/// Whether data starts with gzip's magic number.
	static func isCompressed(_ data: Data) -> Bool {
		data.count >= 2 && data[data.startIndex] == 0x1f && data[data.startIndex + 1] == 0x8b
	}

	static func decompress(_ data: Data) throws -> Data {
		let bytes = [UInt8](data)
		// Header: magic, method (8 = DEFLATE), flags, mtime, extra flags, OS.
		guard bytes.count >= 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else {
			throw CocoaError(.fileReadCorruptFile)
		}
		let flags = bytes[3]
		var offset = 10
		if flags & 0x04 != 0 {  // FEXTRA
			guard offset + 2 <= bytes.count else { throw CocoaError(.fileReadCorruptFile) }
			offset += 2 + Int(bytes[offset]) + Int(bytes[offset + 1]) << 8
		}
		for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 {  // FNAME, FCOMMENT
			while offset < bytes.count && bytes[offset] != 0 { offset += 1 }
			offset += 1
		}
		if flags & 0x02 != 0 { offset += 2 }  // FHCRC
		guard offset < bytes.count - 8 else { throw CocoaError(.fileReadCorruptFile) }

		let deflated = Data(bytes[offset..<(bytes.count - 8)])
		let inflated = try (deflated as NSData).decompressed(using: .zlib) as Data
		let trailer = bytes.suffix(8).map(UInt32.init)
		let crc = trailer[0] | trailer[1] << 8 | trailer[2] << 16 | trailer[3] << 24
		guard crc == crc32(inflated) else { throw CocoaError(.fileReadCorruptFile) }
		return inflated
	}

	static func compress(_ data: Data) throws -> Data {
		let deflated = try (data as NSData).compressed(using: .zlib) as Data
		var out = Data([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 0xff])
		out.append(deflated)
		for value in [crc32(data), UInt32(truncatingIfNeeded: data.count)] {
			out.append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
		}
		return out
	}

	private static let table: [UInt32] = (0..<256).map { n in
		(0..<8).reduce(UInt32(n)) { c, _ in c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
	}

	static func crc32(_ data: Data) -> UInt32 {
		~data.reduce(~UInt32(0)) { c, byte in table[Int((c ^ UInt32(byte)) & 0xff)] ^ (c >> 8) }
	}
}
