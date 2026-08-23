import Foundation

/// A metadata header found at the head of a document, located as a single
/// span of the original source.
struct FrontmatterSpan {
    /// The header including both fence lines, with no trailing newline —
    /// byte-identical to what the document's blank-line block splitter
    /// produces for a header with no blank lines of its own, so block
    /// content fingerprints (bookmarks) and block indices (scroll
    /// restoration) are unchanged for the common case.
    let block: String

    /// Index into the original string of the first character after the
    /// closing fence's line break; `endIndex` when the closing fence is
    /// the last line of the file. Always on a `Character` boundary.
    let bodyStart: String.Index
}

/// Locate a metadata header at the very top of `raw`: YAML between `---`
/// fences (or ended by YAML's `...` document terminator), or TOML between
/// `+++` fences. Returns nil when there isn't one.
///
/// The header has to be recognized before markdown parsing because
/// CommonMark has its own reading of it: the opening `---` is a thematic
/// break, the metadata lines are a paragraph, and the closing `---` then
/// underlines that paragraph as a setext heading. Handing the whole header
/// back as one span lets the caller keep it intact as a single block, no
/// matter how many blank lines sit inside it.
///
/// Recognition is deliberately narrow:
///
/// - **Byte 0 only.** Line 1 must be the opening fence and nothing else —
///   no leading or trailing spaces, no blank line above it. Every
///   frontmatter consumer requires this, and it is what stops a `---` in
///   the middle of a document from being read as metadata.
/// - **Exact closers.** A closing fence is a line that is *exactly* `---`
///   or `...` (YAML) or `+++` (TOML), so an indented `  ---` inside a
///   folded value does not end the header. No closer anywhere → not
///   frontmatter.
/// - **Content guard, YAML only.** `---` is also a legal thematic break,
///   so a document that opens with a horizontal rule and has another one
///   further down would otherwise be swallowed whole. Every top-level line
///   between YAML fences therefore has to look like YAML (see
///   `looksLikeYAMLHeaderLine`). `+++` has no meaning in CommonMark at all,
///   so TOML is accepted on its fences alone — which also avoids rejecting
///   multi-line TOML arrays, whose closing `]` and `[table]` headers sit at
///   column 0 and look nothing like YAML.
///
/// False negatives are cheap and false positives are not: a rejected
/// candidate renders exactly as it would with no frontmatter support at
/// all, which is also what GitHub does with a header it cannot parse.
func frontmatterSpan(in raw: String) -> FrontmatterSpan? {
    guard let opening = physicalLine(of: raw, at: raw.startIndex) else { return nil }

    let closers: Set<String>
    let guardContent: Bool
    switch String(opening.text) {
    case "---":
        closers = ["---", "..."]
        guardContent = true
    case "+++":
        closers = ["+++"]
        guardContent = false
    default:
        return nil
    }

    var cursor = opening.nextStart
    while let line = physicalLine(of: raw, at: cursor) {
        if closers.contains(String(line.text)) {
            return FrontmatterSpan(
                // The trim mirrors the block splitter's per-block trim, so a
                // CRLF file's closing fence loses its `\r` here exactly as it
                // would there.
                block: String(raw[raw.startIndex..<line.textEnd])
                    .trimmingCharacters(in: .newlines),
                bodyStart: line.nextStart
            )
        }
        if guardContent && !looksLikeYAMLHeaderLine(line.text) { return nil }
        cursor = line.nextStart
    }
    return nil
}

/// True if `line` is shaped like a line of a YAML mapping. Applied only to
/// lines that start at column 0: an indented line is a continuation of the
/// one above it — a folded scalar's text, a nested mapping, a sequence item
/// — and can hold anything at all.
private func looksLikeYAMLHeaderLine(_ line: Substring) -> Bool {
    guard let first = line.first else { return true }
    switch first {
    case " ", "\t":  // blank-but-not-empty, or a continuation
        return true
    case "#":        // comment
        return true
    default:
        break
    }
    if line == "-" || line.hasPrefix("- ") { return true }  // sequence item
    return isMappingKeyLine(line)
}

/// True if `line` contains a `:` followed by a space, a tab, or the end of
/// the line. That is YAML's own rule for what separates a key from a value,
/// and it is the whole point of the check: `type:` and `summary: >-` are
/// mappings, while `http://example.com` and a prose sentence are not.
private func isMappingKeyLine(_ line: Substring) -> Bool {
    var searchFrom = line.startIndex
    while let colon = line[searchFrom...].firstIndex(of: ":") {
        let after = line.index(after: colon)
        if after == line.endIndex { return true }
        if line[after] == " " || line[after] == "\t" { return true }
        searchFrom = after
    }
    return false
}

/// One physical line of `raw`, plus the two indices the scanner needs:
/// where the text ends (at the line break) and where the next line begins.
private struct PhysicalLine {
    /// Line content with any trailing `\r` dropped, so the exact-match
    /// fence tests and the shape test never have to think about CRLF.
    let text: Substring
    let textEnd: String.Index
    let nextStart: String.Index
}

/// Read the line starting at `start`, or nil at end of input.
///
/// The scan runs over the unicode scalar view: in a CRLF file `\r\n` is a
/// single `Character`, so searching the `Character` view for `\n` finds no
/// line breaks whatsoever. Slicing the string at a scalar index between the
/// `\r` and the `\n` is well defined and leaves the `\r` on the line, which
/// is also where `components(separatedBy: "\n")` leaves it.
private func physicalLine(of raw: String, at start: String.Index) -> PhysicalLine? {
    guard start < raw.endIndex else { return nil }
    let scalars = raw.unicodeScalars
    var end = start
    while end < raw.endIndex, scalars[end] != "\n" {
        end = scalars.index(after: end)
    }
    var text = raw[start..<end]
    if text.last == "\r" { text = text.dropLast() }
    return PhysicalLine(
        text: text,
        textEnd: end,
        nextStart: end < raw.endIndex ? scalars.index(after: end) : raw.endIndex
    )
}
