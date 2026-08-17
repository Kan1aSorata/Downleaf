import Foundation

enum MarkdownTextEncoding: Equatable, Sendable {
    case utf8
    case utf8WithBOM
    case utf16LittleEndian
    case utf16BigEndian
    case isoLatin1
}

enum MarkdownLineEnding: String, Equatable, Sendable {
    case lf = "\n"
    case crlf = "\r\n"
    case cr = "\r"
}

struct MarkdownFileFormat: Equatable, Sendable {
    var encoding: MarkdownTextEncoding
    var lineEnding: MarkdownLineEnding

    static let standard = MarkdownFileFormat(encoding: .utf8, lineEnding: .lf)
}

enum MarkdownCodecError: LocalizedError {
    case unreadableText
    case unencodableText

    var errorDescription: String? {
        switch self {
        case .unreadableText:
            return "无法识别这个文稿的文本编码。"
        case .unencodableText:
            return "当前文本无法使用原文稿编码保存。"
        }
    }
}

enum MarkdownCodec {
    private static let utf8BOM = Data([0xEF, 0xBB, 0xBF])
    private static let utf16LEBOM = Data([0xFF, 0xFE])
    private static let utf16BEBOM = Data([0xFE, 0xFF])

    static func decode(_ data: Data) throws -> (text: String, format: MarkdownFileFormat) {
        let detected: (String, MarkdownTextEncoding)

        if data.starts(with: utf8BOM),
           let string = String(data: data.dropFirst(utf8BOM.count), encoding: .utf8) {
            detected = (string, .utf8WithBOM)
        } else if data.starts(with: utf16LEBOM),
                  let string = String(data: data.dropFirst(utf16LEBOM.count), encoding: .utf16LittleEndian) {
            detected = (string, .utf16LittleEndian)
        } else if data.starts(with: utf16BEBOM),
                  let string = String(data: data.dropFirst(utf16BEBOM.count), encoding: .utf16BigEndian) {
            detected = (string, .utf16BigEndian)
        } else if let string = String(data: data, encoding: .utf8) {
            detected = (string, .utf8)
        } else if looksLikeUTF16LittleEndian(data),
                  let string = String(data: data, encoding: .utf16LittleEndian) {
            detected = (string, .utf16LittleEndian)
        } else if looksLikeUTF16BigEndian(data),
                  let string = String(data: data, encoding: .utf16BigEndian) {
            detected = (string, .utf16BigEndian)
        } else if let string = String(data: data, encoding: .isoLatin1) {
            detected = (string, .isoLatin1)
        } else {
            throw MarkdownCodecError.unreadableText
        }

        let lineEnding = dominantLineEnding(in: detected.0)
        let normalized = detected.0
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        return (normalized, MarkdownFileFormat(encoding: detected.1, lineEnding: lineEnding))
    }

    static func encode(_ text: String, format: MarkdownFileFormat) throws -> Data {
        let denormalized = text.replacingOccurrences(of: "\n", with: format.lineEnding.rawValue)

        switch format.encoding {
        case .utf8:
            guard let data = denormalized.data(using: .utf8) else {
                throw MarkdownCodecError.unencodableText
            }
            return data
        case .utf8WithBOM:
            guard let data = denormalized.data(using: .utf8) else {
                throw MarkdownCodecError.unencodableText
            }
            return utf8BOM + data
        case .utf16LittleEndian:
            guard let data = denormalized.data(using: .utf16LittleEndian) else {
                throw MarkdownCodecError.unencodableText
            }
            return utf16LEBOM + stripUTF16BOM(from: data)
        case .utf16BigEndian:
            guard let data = denormalized.data(using: .utf16BigEndian) else {
                throw MarkdownCodecError.unencodableText
            }
            return utf16BEBOM + stripUTF16BOM(from: data)
        case .isoLatin1:
            guard let data = denormalized.data(using: .isoLatin1, allowLossyConversion: false) else {
                throw MarkdownCodecError.unencodableText
            }
            return data
        }
    }

    private static func dominantLineEnding(in text: String) -> MarkdownLineEnding {
        let crlfCount = text.components(separatedBy: "\r\n").count - 1
        let withoutCRLF = text.replacingOccurrences(of: "\r\n", with: "")
        let lfCount = withoutCRLF.filter { $0 == "\n" }.count
        let crCount = withoutCRLF.filter { $0 == "\r" }.count

        if crlfCount >= lfCount, crlfCount >= crCount, crlfCount > 0 {
            return .crlf
        }
        if crCount > lfCount, crCount > 0 {
            return .cr
        }
        return .lf
    }

    private static func looksLikeUTF16LittleEndian(_ data: Data) -> Bool {
        let bytes = Array(data.prefix(128))
        guard bytes.count >= 4 else { return false }
        let oddNulls = stride(from: 1, to: bytes.count, by: 2).filter { bytes[$0] == 0 }.count
        return oddNulls > bytes.count / 8
    }

    private static func looksLikeUTF16BigEndian(_ data: Data) -> Bool {
        let bytes = Array(data.prefix(128))
        guard bytes.count >= 4 else { return false }
        let evenNulls = stride(from: 0, to: bytes.count, by: 2).filter { bytes[$0] == 0 }.count
        return evenNulls > bytes.count / 8
    }

    private static func stripUTF16BOM(from data: Data) -> Data {
        if data.starts(with: utf16LEBOM) || data.starts(with: utf16BEBOM) {
            return Data(data.dropFirst(2))
        }
        return data
    }
}
