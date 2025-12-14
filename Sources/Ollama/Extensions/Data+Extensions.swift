import Foundation

#if canImport(RegexBuilder)
import RegexBuilder
#endif

extension Data {
    #if canImport(RegexBuilder)
    /// Regex pattern for data URLs (macOS 13.0+ / iOS 16.0+)
    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    @inline(__always) private static var dataURLRegex:
        Regex<(Substring, Substring, Substring?, Substring)>
    {
        Regex {
            "data:"
            Capture {
                ZeroOrMore(.reluctant) {
                    CharacterClass.anyOf(",;").inverted
                }
            }
            Optionally {
                ";charset="
                Capture {
                    OneOrMore(.reluctant) {
                        CharacterClass.anyOf(",;").inverted
                    }
                }
            }
            Optionally { ";base64" }
            ","
            Capture {
                ZeroOrMore { .any }
            }
        }
    }
    #endif

    /// NSRegularExpression pattern for data URLs (macOS 12.0+ fallback)
    private static var dataURLPattern: String {
        "^data:([^,;]*)(?:;charset=([^,;]+))?(?:;base64)?,(.*)$"
    }

    /// Checks if a given string is a valid data URL.
    ///
    /// - Parameter string: The string to check.
    /// - Returns: `true` if the string is a valid data URL, otherwise `false`.
    /// - SeeAlso: [RFC 2397](https://www.rfc-editor.org/rfc/rfc2397.html)
    public static func isDataURL(string: String) -> Bool {
        #if canImport(RegexBuilder)
        if #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
            return string.wholeMatch(of: dataURLRegex) != nil
        }
        #endif

        // Fallback for macOS 12.0+
        guard let regex = try? NSRegularExpression(pattern: dataURLPattern, options: []) else {
            return false
        }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.firstMatch(in: string, options: [], range: range) != nil
    }

    /// Parses a data URL string into its MIME type and data components.
    ///
    /// - Parameter string: The data URL string to parse.
    /// - Returns: A tuple containing the MIME type and decoded data, or `nil` if parsing fails.
    /// - SeeAlso: [RFC 2397](https://www.rfc-editor.org/rfc/rfc2397.html)
    public static func parseDataURL(_ string: String) -> (mimeType: String, data: Data)? {
        #if canImport(RegexBuilder)
        if #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
            guard let match = string.wholeMatch(of: dataURLRegex) else {
                return nil
            }

            // Extract components using strongly typed captures
            let (_, mediatype, charset, encodedData) = match.output

            let isBase64 = string.contains(";base64,")

            // Process MIME type
            var mimeType = mediatype.isEmpty ? "text/plain" : String(mediatype)
            if let charset = charset, !charset.isEmpty, mimeType.starts(with: "text/") {
                mimeType += ";charset=\(charset)"
            }

            // Decode data
            let decodedData: Data
            if isBase64 {
                guard let base64Data = Data(base64Encoded: String(encodedData)) else { return nil }
                decodedData = base64Data
            } else {
                guard
                    let percentDecodedData = String(encodedData).removingPercentEncoding?.data(
                        using: .utf8)
                else { return nil }
                decodedData = percentDecodedData
            }

            return (mimeType: mimeType, data: decodedData)
        }
        #endif

        // Fallback for macOS 12.0+
        guard let regex = try? NSRegularExpression(pattern: dataURLPattern, options: []) else {
            return nil
        }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = regex.firstMatch(in: string, options: [], range: range) else {
            return nil
        }

        // Extract components from NSRegularExpression match
        guard match.numberOfRanges >= 4 else { return nil }
        
        let mediatypeRange = Range(match.range(at: 1), in: string) ?? string.startIndex..<string.startIndex
        let mediatype = String(string[mediatypeRange])
        
        let charset: String?
        if match.range(at: 2).location != NSNotFound,
           let charsetRange = Range(match.range(at: 2), in: string)
        {
            charset = String(string[charsetRange])
        } else {
            charset = nil
        }
        
        guard let encodedDataRange = Range(match.range(at: 3), in: string) else {
            return nil
        }
        let encodedData = String(string[encodedDataRange])

        let isBase64 = string.contains(";base64,")

        // Process MIME type
        var mimeType = mediatype.isEmpty ? "text/plain" : mediatype
        if let charset = charset, !charset.isEmpty, mimeType.starts(with: "text/") {
            mimeType += ";charset=\(charset)"
        }

        // Decode data
        let decodedData: Data
        if isBase64 {
            guard let base64Data = Data(base64Encoded: encodedData) else { return nil }
            decodedData = base64Data
        } else {
            guard
                let percentDecodedData = encodedData.removingPercentEncoding?.data(
                    using: .utf8)
            else { return nil }
            decodedData = percentDecodedData
        }

        return (mimeType: mimeType, data: decodedData)
    }

    /// Encodes the data as a data URL string with an optional MIME type.
    ///
    /// - Parameter mimeType: The MIME type of the data. If `nil`, "text/plain" will be used.
    /// - Returns: A data URL string representation of the data.
    /// - SeeAlso: [RFC 2397](https://www.rfc-editor.org/rfc/rfc2397.html)
    public func dataURLEncoded(mimeType: String? = nil) -> String {
        let base64Data = self.base64EncodedString()
        return "data:\(mimeType ?? "text/plain");base64,\(base64Data)"
    }
}
