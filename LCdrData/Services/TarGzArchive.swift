import Foundation
import zlib

nonisolated struct TarHeader: Sendable {
    var path: String
    var mode: UInt16
    var size: UInt64
    var modificationDate: Date?
    var kind: Kind
    var linkPath: String

    enum Kind: Sendable {
        case file
        case directory
        case symlink
        case hardlink
        case ignored
    }

    var isDirectory: Bool {
        kind == .directory
    }
}

/// Streams a gzip-compressed tar. Listing and extraction never load the archive into one buffer.
nonisolated final class TarGzReader {
    private let source: GzipReader
    private var pendingPax: [String: String] = [:]
    private var globalPax: [String: String] = [:]
    private var pendingLongName: String?
    private var pendingLongLink: String?
    private var contentRemaining: UInt64 = 0
    private var paddingRemaining: UInt64 = 0

    init(url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        do {
            source = try GzipReader(handle: handle)
        } catch {
            try? handle.close()
            throw ArchiveServiceError.unreadable
        }
    }

    /// The next archive member. Special headers (pax, GNU long names) are consumed here.
    func next() throws -> TarHeader? {
        try discardRemainder()
        while true {
            guard let block = try readBlock() else { return nil }
            if block.allSatisfy({ $0 == 0 }) {
                return nil
            }
            guard checksumMatches(block) else { throw ArchiveServiceError.unreadable }
            let parsed = try parse(block)
            switch parsed.special {
            case .none:
                contentRemaining = parsed.header.size
                paddingRemaining = Self.padding(for: parsed.header.size)
                return parsed.header
            case .pax(let global):
                let records = parsePax(try readPayload(size: parsed.header.size))
                if global {
                    globalPax.merge(records) { _, new in new }
                } else {
                    pendingPax = records
                }
            case .longName:
                pendingLongName = cString(try readPayload(size: parsed.header.size))
            case .longLink:
                pendingLongLink = cString(try readPayload(size: parsed.header.size))
            }
        }
    }

    func discardBody() throws {
        try discardRemainder()
    }

    func copyContent(_ consume: (Data) throws -> Void) throws {
        var remaining = contentRemaining
        while remaining > 0 {
            let count = Int(min(remaining, 1024 * 1024))
            let chunk = try source.readExactly(count)
            try consume(chunk)
            remaining -= UInt64(chunk.count)
        }
        contentRemaining = 0
        try discardRemainder()
    }

    func readContent() throws -> Data {
        let count = contentRemaining
        guard count <= UInt64(Int.max) else { throw ArchiveServiceError.entryTooLarge("") }
        var data = Data()
        data.reserveCapacity(Int(count))
        var remaining = count
        while remaining > 0 {
            let chunkCount = Int(min(remaining, 1024 * 1024))
            data.append(try source.readExactly(chunkCount))
            remaining -= UInt64(chunkCount)
        }
        contentRemaining = 0
        try discardRemainder()
        return data
    }

    private func discardRemainder() throws {
        let total = contentRemaining + paddingRemaining
        if total > 0 {
            try source.skip(total)
        }
        contentRemaining = 0
        paddingRemaining = 0
    }

    private func readPayload(size: UInt64) throws -> Data {
        contentRemaining = size
        paddingRemaining = Self.padding(for: size)
        return try readContent()
    }

    private func readBlock() throws -> [UInt8]? {
        let data = try source.read(count: 512)
        if data.isEmpty { return nil }
        guard data.count == 512 else { throw ArchiveServiceError.unreadable }
        return [UInt8](data)
    }

    private struct Parsed {
        var header: TarHeader
        enum Special {
            case none
            case pax(global: Bool)
            case longName
            case longLink
        }
        var special: Special
    }

    private func parse(_ block: [UInt8]) throws -> Parsed {
        let name = cString(block[0..<100])
        let mode = UInt16(truncatingIfNeeded: parseNumber(block[100..<108]) ?? 0)
        let size = parseNumber(block[124..<136]) ?? 0
        let mtime = parseNumber(block[136..<148]).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let type = block[156]
        let link = cString(block[157..<257])
        let prefix = cString(block[345..<500])
        let rawPath = prefix.isEmpty ? name : prefix + "/" + name

        var header = TarHeader(
            path: normalize(rawPath),
            mode: mode,
            size: size,
            modificationDate: mtime,
            kind: kind(for: type, path: rawPath),
            linkPath: link
        )
        var special = Parsed.Special.none
        switch type {
        case UInt8(ascii: "x"):
            special = .pax(global: false)
        case UInt8(ascii: "g"):
            special = .pax(global: true)
        case UInt8(ascii: "L"):
            special = .longName
        case UInt8(ascii: "K"):
            special = .longLink
        default:
            applyOverrides(to: &header)
        }
        return Parsed(header: header, special: special)
    }

    private func applyOverrides(to header: inout TarHeader) {
        var records = globalPax
        records.merge(pendingPax) { _, new in new }
        pendingPax = [:]
        if let longName = pendingLongName {
            header.path = normalize(longName)
            pendingLongName = nil
        }
        if let longLink = pendingLongLink {
            header.linkPath = longLink
            pendingLongLink = nil
        }
        if let path = records["path"] {
            header.path = normalize(path)
        }
        if let link = records["linkpath"] {
            header.linkPath = link
        }
        if let size = records["size"].flatMap({ UInt64($0) }) ?? records["size"].flatMap(parseDecimal) {
            header.size = size
        }
        if let mtime = records["mtime"].flatMap(Double.init) {
            header.modificationDate = Date(timeIntervalSince1970: mtime)
        }
        if header.path.hasSuffix("/"), header.kind == .file {
            header.kind = .directory
        }
    }

    private func kind(for type: UInt8, path: String) -> TarHeader.Kind {
        switch type {
        case 0, UInt8(ascii: "0"):
            return path.hasSuffix("/") ? .directory : .file
        case UInt8(ascii: "5"):
            return .directory
        case UInt8(ascii: "2"):
            return .symlink
        case UInt8(ascii: "1"):
            return .hardlink
        default:
            return .ignored
        }
    }

    private func checksumMatches(_ block: [UInt8]) -> Bool {
        guard let stored = parseNumber(block[148..<156]) else { return false }
        var sum = 0
        for (index, byte) in block.enumerated() {
            sum += index >= 148 && index < 156 ? 0x20 : Int(byte)
        }
        return UInt64(sum) == stored
    }

    private func parseNumber(_ bytes: ArraySlice<UInt8>) -> UInt64? {
        guard let first = bytes.first else { return nil }
        if first == 0x80 || first == 0xFF {
            var value: UInt64 = 0
            for byte in bytes.dropFirst() {
                value = (value << 8) | UInt64(byte)
            }
            return value
        }
        let text = String(bytes: bytes, encoding: .utf8) ?? ""
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: " \0"))
        if trimmed.isEmpty { return 0 }
        return UInt64(trimmed, radix: 8)
    }

    private func parseDecimal(_ text: String) -> UInt64? {
        let whole = text.split(separator: ".").first.map(String.init) ?? text
        return UInt64(whole)
    }

    private func cString(_ bytes: ArraySlice<UInt8>) -> String {
        let end = bytes.firstIndex(of: 0) ?? bytes.endIndex
        let slice = bytes[bytes.startIndex..<end]
        return String(bytes: slice, encoding: .utf8)
            ?? String(bytes: slice, encoding: .isoLatin1)
            ?? ""
    }

    private func cString(_ data: Data) -> String {
        let bytes = [UInt8](data)
        return cString(bytes[...])
    }

    private func parsePax(_ data: Data) -> [String: String] {
        var records: [String: String] = [:]
        var index = data.startIndex
        while index < data.endIndex {
            guard let space = data[index...].firstIndex(of: UInt8(ascii: " ")) else { break }
            let lengthText = String(decoding: data[index..<space], as: UTF8.self)
            guard let length = Int(lengthText), length > 0 else { break }
            guard let end = data.index(index, offsetBy: length, limitedBy: data.endIndex) else { break }
            let body = data[data.index(after: space)..<end]
            let content = body.last == UInt8(ascii: "\n") ? body.dropLast() : body
            if let equals = content.firstIndex(of: UInt8(ascii: "=")) {
                let key = String(decoding: content[..<equals], as: UTF8.self)
                let value = String(decoding: content[content.index(after: equals)...], as: UTF8.self)
                if !key.isEmpty {
                    records[key] = value
                }
            }
            index = end
        }
        return records
    }

    private func normalize(_ path: String) -> String {
        var path = path.replacingOccurrences(of: "\0", with: "")
        while path.hasPrefix("./") {
            path.removeFirst(2)
        }
        if path == "." { return "" }
        while path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    private static func padding(for size: UInt64) -> UInt64 {
        let remainder = size % 512
        return remainder == 0 ? 0 : 512 - remainder
    }
}

nonisolated final class TarGzWriter {
    private let destination: GzipWriter
    private var entryBytesRemaining: UInt64 = 0

    init(url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        destination = try GzipWriter(handle: handle)
    }

    func writeFile(path: String, mode: UInt16, date: Date?, from source: URL) throws {
        let size = (try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?
            .uint64Value ?? 0
        try beginFile(path: path, mode: mode, date: date, size: size)
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        var remaining = size
        while remaining > 0 {
            let count = Int(min(remaining, 1024 * 1024))
            guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else {
                throw ArchiveServiceError.unreadable
            }
            try write(chunk)
            remaining -= UInt64(chunk.count)
        }
        guard remaining == 0 else { throw ArchiveServiceError.unreadable }
        try finishContent()
    }

    func writeDirectory(path: String, mode: UInt16, date: Date?) throws {
        try writeHeader(
            path: path.hasSuffix("/") ? path : path + "/",
            mode: mode == 0 ? 0o755 : mode,
            date: date,
            size: 0,
            type: UInt8(ascii: "5"),
            link: ""
        )
    }

    func writeSymlink(path: String, target: String, mode: UInt16, date: Date?) throws {
        try writeHeader(path: path, mode: mode, date: date, size: 0, type: UInt8(ascii: "2"), link: target)
    }

    func writeHardlink(path: String, target: String, mode: UInt16, date: Date?) throws {
        try writeHeader(path: path, mode: mode, date: date, size: 0, type: UInt8(ascii: "1"), link: target)
    }

    func beginFile(path: String, mode: UInt16, date: Date?, size: UInt64) throws {
        try writeHeader(
            path: path,
            mode: mode == 0 ? 0o644 : mode,
            date: date,
            size: size,
            type: UInt8(ascii: "0"),
            link: ""
        )
        entryBytesRemaining = size
    }

    func write(_ data: Data) throws {
        guard data.count <= entryBytesRemaining else { throw ArchiveServiceError.unreadable }
        try destination.write(data)
        entryBytesRemaining -= UInt64(data.count)
    }

    func finish() throws {
        try destination.write(Data(count: 1024))
        try destination.finish()
    }

    private var headerSize: UInt64 = 0

    private func padding(for size: UInt64) -> UInt64 {
        let remainder = size % 512
        return remainder == 0 ? 0 : 512 - remainder
    }

    private func writeHeader(
        path: String,
        mode: UInt16,
        date: Date?,
        size: UInt64,
        type: UInt8,
        link: String
    ) throws {
        headerSize = size
        let pathBytes = Data(path.utf8)
        if pathBytes.count > 100 || Data(link.utf8).count > 100 {
            try writePaxHeader(path: path, link: link, size: size)
        }
        var block = [UInt8](repeating: 0, count: 512)
        writeCString(pathBytes.count > 100 ? "pax" : path, into: &block, at: 0, length: 100)
        writeOctal(UInt64(mode), into: &block, at: 100, length: 8)
        writeOctal(0, into: &block, at: 108, length: 8)
        writeOctal(0, into: &block, at: 116, length: 8)
        writeOctal(size, into: &block, at: 124, length: 12)
        writeOctal(UInt64(date?.timeIntervalSince1970 ?? 0), into: &block, at: 136, length: 12)
        for index in 148..<156 { block[index] = 0x20 }
        block[156] = type
        writeCString(Data(link.utf8).count > 100 ? "" : link, into: &block, at: 157, length: 100)
        writeCString("ustar", into: &block, at: 257, length: 6)
        block[263] = UInt8(ascii: "0")
        block[264] = UInt8(ascii: "0")
        let sum = block.reduce(0) { $0 + Int($1) }
        writeOctal(UInt64(sum), into: &block, at: 148, length: 8)
        try destination.write(Data(block))
    }

    private func writePaxHeader(path: String, link: String, size: UInt64) throws {
        var records = Data()
        records.append(paxRecord("path", path))
        if Data(link.utf8).count > 100 {
            records.append(paxRecord("linkpath", link))
        }
        if size > 0o77777777777 {
            records.append(paxRecord("size", String(size)))
        }
        var block = [UInt8](repeating: 0, count: 512)
        writeCString("PaxHeader", into: &block, at: 0, length: 100)
        writeOctal(0o644, into: &block, at: 100, length: 8)
        writeOctal(UInt64(records.count), into: &block, at: 124, length: 12)
        for index in 148..<156 { block[index] = 0x20 }
        block[156] = UInt8(ascii: "x")
        writeCString("ustar", into: &block, at: 257, length: 6)
        block[263] = UInt8(ascii: "0")
        block[264] = UInt8(ascii: "0")
        let sum = block.reduce(0) { $0 + Int($1) }
        writeOctal(UInt64(sum), into: &block, at: 148, length: 8)
        try destination.write(Data(block))
        try destination.write(records)
        let pad = padding(for: UInt64(records.count))
        if pad > 0 {
            try destination.write(Data(count: Int(pad)))
        }
    }

    func finishContent() throws {
        guard entryBytesRemaining == 0 else { throw ArchiveServiceError.unreadable }
        let pad = padding(for: headerSize)
        if pad > 0 {
            try destination.write(Data(count: Int(pad)))
        }
        headerSize = 0
    }

    private func paxRecord(_ key: String, _ value: String) -> Data {
        let suffix = Data(" \(key)=\(value)\n".utf8)
        var digits = 1
        while true {
            let total = digits + suffix.count
            if String(total).count == digits {
                return Data(String(total).utf8) + suffix
            }
            digits = String(total).count
        }
    }

    private func writeCString(_ text: String, into block: inout [UInt8], at offset: Int, length: Int) {
        writeCString(Data(text.utf8), into: &block, at: offset, length: length)
    }

    private func writeCString(_ data: Data, into block: inout [UInt8], at offset: Int, length: Int) {
        let count = min(data.count, length - 1)
        for (index, byte) in data.prefix(count).enumerated() {
            block[offset + index] = byte
        }
    }

    private func writeOctal(_ value: UInt64, into block: inout [UInt8], at offset: Int, length: Int) {
        let digits = String(value, radix: 8)
        let width = length - 1
        let padded = String(repeating: "0", count: max(0, width - digits.count)) + digits
        let shown = padded.suffix(width)
        for (index, character) in shown.enumerated() {
            block[offset + index] = character.asciiValue ?? 0
        }
    }
}

nonisolated final class GzipReader {
    private let handle: FileHandle
    private var stream = z_stream()
    private let input: UnsafeMutablePointer<UInt8>
    private let output: UnsafeMutablePointer<UInt8>
    private var pending = Data()
    private var exhausted = false
    private var streamEnded = false
    private static let chunk = 1024 * 1024

    init(handle: FileHandle) throws {
        self.handle = handle
        input = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.chunk)
        output = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.chunk)
        stream.next_in = input
        stream.avail_in = 0
        stream.next_out = output
        stream.avail_out = 0
        let status = inflateInit2_(&stream, 15 + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else {
            input.deallocate()
            output.deallocate()
            try? handle.close()
            throw ArchiveServiceError.unreadable
        }
    }

    deinit {
        inflateEnd(&stream)
        input.deallocate()
        output.deallocate()
        try? handle.close()
    }

    func read(count: Int) throws -> Data {
        var result = Data()
        result.reserveCapacity(count)
        while result.count < count {
            if pending.isEmpty {
                try fill()
            }
            if pending.isEmpty { break }
            let take = min(count - result.count, pending.count)
            result.append(pending.prefix(take))
            pending.removeFirst(take)
        }
        return result
    }

    func readExactly(_ count: Int) throws -> Data {
        let data = try read(count: count)
        guard data.count == count else { throw ArchiveServiceError.unreadable }
        return data
    }

    /// Discards inflated bytes without copying them into a `Data`. Listing a tar.gz
    /// has to walk every header, and the file bodies between headers are what dominate.
    func skip(_ count: UInt64) throws {
        var remaining = count
        if !pending.isEmpty {
            let take = min(remaining, UInt64(pending.count))
            if take == UInt64(pending.count) {
                pending.removeAll(keepingCapacity: true)
            } else {
                pending.removeFirst(Int(take))
            }
            remaining -= take
        }
        while remaining > 0 {
            let produced = try inflateChunk()
            if produced == 0 { throw ArchiveServiceError.unreadable }
            if UInt64(produced) > remaining {
                let start = Int(remaining)
                pending.append(output.advanced(by: start), count: produced - start)
                return
            }
            remaining -= UInt64(produced)
        }
    }

    private func fill() throws {
        guard !streamEnded else { return }
        while pending.isEmpty && !streamEnded {
            let produced = try inflateChunk()
            if produced > 0 {
                pending.append(output, count: produced)
            } else {
                break
            }
        }
    }

    /// Inflates one chunk into `output` and returns how many bytes were produced.
    private func inflateChunk() throws -> Int {
        if streamEnded { return 0 }
        if stream.avail_in == 0 && !exhausted {
            let data = try handle.read(upToCount: Self.chunk) ?? Data()
            if data.isEmpty {
                exhausted = true
            } else {
                data.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress else { return }
                    input.update(from: base.assumingMemoryBound(to: UInt8.self), count: data.count)
                }
                stream.next_in = input
                stream.avail_in = uInt(data.count)
            }
        }
        let sourceRemaining = stream.avail_in
        stream.next_out = output
        stream.avail_out = uInt(Self.chunk)
        let status = inflate(&stream, exhausted ? Z_FINISH : Z_NO_FLUSH)
        let produced = Self.chunk - Int(stream.avail_out)
        if status == Z_STREAM_END {
            streamEnded = true
        } else if status != Z_OK && status != Z_BUF_ERROR {
            throw ArchiveServiceError.unreadable
        } else if produced == 0 && stream.avail_in == sourceRemaining {
            if exhausted {
                streamEnded = true
            } else {
                throw ArchiveServiceError.unreadable
            }
        }
        return produced
    }
}

nonisolated final class GzipWriter {
    private let handle: FileHandle
    private var stream = z_stream()
    private let input: UnsafeMutablePointer<UInt8>
    private let output: UnsafeMutablePointer<UInt8>
    private static let chunk = 64 * 1024

    init(handle: FileHandle) throws {
        self.handle = handle
        input = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.chunk)
        output = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.chunk)
        let status = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            15 + 16,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard status == Z_OK else {
            input.deallocate()
            output.deallocate()
            try? handle.close()
            throw ArchiveServiceError.unreadable
        }
    }

    deinit {
        deflateEnd(&stream)
        input.deallocate()
        output.deallocate()
        try? handle.close()
    }

    func write(_ data: Data) throws {
        guard !data.isEmpty else { return }
        var offset = 0
        while offset < data.count {
            let count = min(Self.chunk, data.count - offset)
            data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                input.update(from: base.advanced(by: offset).assumingMemoryBound(to: UInt8.self), count: count)
            }
            stream.next_in = input
            stream.avail_in = uInt(count)
            try pump(flush: Z_NO_FLUSH)
            offset += count
        }
    }

    func finish() throws {
        stream.next_in = input
        stream.avail_in = 0
        try pump(flush: Z_FINISH)
        try handle.close()
    }

    private func pump(flush: Int32) throws {
        var spins = 0
        repeat {
            stream.next_out = output
            stream.avail_out = uInt(Self.chunk)
            let status = deflate(&stream, flush)
            let produced = Self.chunk - Int(stream.avail_out)
            if produced > 0 {
                try handle.write(contentsOf: Data(bytes: output, count: produced))
            }
            if status == Z_STREAM_END { return }
            if status != Z_OK && status != Z_BUF_ERROR {
                throw ArchiveServiceError.unreadable
            }
            spins += 1
            if spins > 10_000 { throw ArchiveServiceError.unreadable }
        } while stream.avail_in > 0 || flush == Z_FINISH
    }
}
