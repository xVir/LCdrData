import AppKit
import Foundation

/// Builds a syntax-colored `AttributedString` for KDL source (comments, strings, booleans, numbers, node names).
enum KDLSyntaxHighlighter {

    static func attributedString(from source: String) -> AttributedString {
        let ns = source as NSString
        let length = ns.length
        let base = NSMutableAttributedString(
            string: source,
            attributes: [
                .foregroundColor: NSColor.textColor,
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            ]
        )

        func addForeground(_ color: NSColor, _ range: NSRange) {
            guard range.location != NSNotFound, range.length > 0,
                  range.location + range.length <= length else { return }
            base.addAttribute(.foregroundColor, value: color, range: range)
        }

        enumerate(#"//[^\n]*"#, in: source) { addForeground(.secondaryLabelColor, $0) }

        enumerate(#"/\*[\s\S]*?\*/"#, in: source) { addForeground(.secondaryLabelColor, $0) }

        enumerate(#""([^"\\]|\\.)*""#, in: source) { addForeground(.systemGreen, $0) }

        enumerate("#(true|false|null)\\b", in: source) { addForeground(.systemPurple, $0) }

        enumerate(#"(?<![\w#])-?\d+(\.\d+)?([eE][+-]?\d+)?\b"#, in: source) { addForeground(.systemOrange, $0) }

        enumerateNodeNames(in: source, addForeground: addForeground)

        return AttributedString(base)
    }

    private static let identifier = #"[a-zA-Z_][a-zA-Z0-9_.-]*"#

    private static func enumerateNodeNames(
        in string: String,
        addForeground: (NSColor, NSRange) -> Void
    ) {
        let pattern = "(?m)^[ \\t]*(\\([^\\)]+\\))?[ \\t]*(" + identifier + ")(?=\\s*\\{)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let full = NSRange(location: 0, length: (string as NSString).length)
        regex.enumerateMatches(in: string, options: [], range: full) { result, _, _ in
            guard let result, result.numberOfRanges >= 3 else { return }
            let nameRange = result.range(at: 2)
            addForeground(.systemTeal, nameRange)
        }
    }

    private static func enumerate(_ pattern: String, in string: String, block: (NSRange) -> Void) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let full = NSRange(location: 0, length: (string as NSString).length)
        regex.enumerateMatches(in: string, options: [], range: full) { result, _, _ in
            guard let r = result?.range, r.location != NSNotFound else { return }
            block(r)
        }
    }
}
