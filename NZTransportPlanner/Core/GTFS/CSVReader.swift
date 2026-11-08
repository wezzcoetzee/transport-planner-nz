import Foundation

/// Minimal streaming RFC 4180 reader. Handles quoted fields, escaped quotes and CRLF, and never loads the whole file.
struct CSVReader: Sequence, IteratorProtocol {
    private let handle: FileHandle
    private var buffer = Data()
    private var exhausted = false
    private let chunkSize = 1 << 20
    let header: [String]

    init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        var tmp = Self(handle: handle)
        header = tmp.nextRow()?.map { $0.trimmingCharacters(in: .init(charactersIn: "\u{FEFF} ")) } ?? []
        buffer = tmp.buffer
        exhausted = tmp.exhausted
    }

    private init(handle: FileHandle) { self.handle = handle; header = [] }

    func index(of column: String) -> Int? { header.firstIndex(of: column) }

    mutating func next() -> [String]? { nextRow() }

    private mutating func fill() {
        guard !exhausted else { return }
        let chunk = handle.readData(ofLength: chunkSize)
        if chunk.isEmpty { exhausted = true } else { buffer.append(chunk) }
    }

    private mutating func nextRow() -> [String]? {
        var fields: [String] = []
        var field = Data()
        var inQuotes = false
        var sawAnything = false
        var i = 0

        while true {
            if i >= buffer.count {
                buffer.removeAll(keepingCapacity: true); i = 0
                fill()
                if buffer.isEmpty {
                    guard sawAnything else { return nil }
                    fields.append(String(decoding: field, as: UTF8.self))
                    return fields
                }
            }
            let byte = buffer[buffer.startIndex + i]
            i += 1
            sawAnything = true
            if inQuotes {
                if byte == UInt8(ascii: "\"") {
                    // Peek for escaped quote
                    if i >= buffer.count { let keep = buffer.suffix(from: buffer.startIndex + i); buffer = Data(keep); i = 0; fill() }
                    if i < buffer.count, buffer[buffer.startIndex + i] == UInt8(ascii: "\"") {
                        field.append(byte); i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(byte)
                }
            } else {
                switch byte {
                case UInt8(ascii: "\""): inQuotes = true
                case UInt8(ascii: ","): fields.append(String(decoding: field, as: UTF8.self)); field.removeAll(keepingCapacity: true)
                case UInt8(ascii: "\r"): break
                case UInt8(ascii: "\n"):
                    fields.append(String(decoding: field, as: UTF8.self))
                    buffer = Data(buffer.suffix(from: buffer.startIndex + i))
                    if fields.count == 1 && fields[0].isEmpty { return nextRow() } // blank line
                    return fields
                default: field.append(byte)
                }
            }
        }
    }
}
