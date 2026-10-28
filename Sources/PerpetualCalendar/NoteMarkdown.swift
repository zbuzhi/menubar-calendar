import AppKit
import SwiftUI

/// Deliberately text-only Markdown: no web view, scripts, remote images or extra dependencies.
enum NoteMarkdown {
    enum Kind { case paragraph, heading, list, quote, code, rule }
    struct Block: Identifiable {
        let id: Int
        let kind: Kind
        let text: String
        var level = 0
        var sourceStart = 0
        var renderedPrefixLength = 0
        var sourcePrefixLength = 0
    }
    static func inline(_ text: String) -> AttributedString {
        let begin = "\u{F0000}", end = "\u{F0001}"
        let source = text.replacingOccurrences(of:"<u>",with:begin).replacingOccurrences(of:"</u>",with:end)
        let parsed = (try? AttributedString(markdown:source,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))) ?? AttributedString(source)
        guard source != text else { return parsed }
        var result = AttributedString(), depth = 0
        for run in parsed.runs {
            var segment = ""
            func flush() {
                guard !segment.isEmpty else { return }
                var part = AttributedString(segment,attributes:run.attributes)
                if depth > 0 { part.underlineStyle = .single }
                result.append(part); segment = ""
            }
            for character in parsed[run.range].characters {
                if String(character) == begin || String(character) == end {
                    if run.inlinePresentationIntent?.contains(.code) == true {
                        segment += String(character) == begin ? "<u>" : "</u>"
                    } else {
                        flush(); depth = String(character) == begin ? depth + 1 : max(0,depth - 1)
                    }
                } else { segment.append(character) }
            }
            flush()
        }
        return result
    }
    static func blocks(_ source: String) -> [Block] {
        var result: [Block] = [], buffer: [String] = [], code: [String] = []
        var fenced = false, offset = 0, bufferStart = 0, codeStart = 0
        func append(_ kind: Kind,_ text: String,_ start: Int,_ level: Int = 0,_ renderedPrefix: Int = 0,_ sourcePrefix: Int = 0) {
            result.append(Block(id:result.count,kind:kind,text:text,level:level,sourceStart:start,renderedPrefixLength:renderedPrefix,sourcePrefixLength:sourcePrefix))
        }
        func flush() { if !buffer.isEmpty { append(.paragraph,buffer.joined(separator:"\n"),bufferStart); buffer = [] } }
        for line in source.components(separatedBy:"\n") {
            let lineStart = offset; offset += line.utf16.count + 1
            let clean = line.trimmingCharacters(in:.whitespacesAndNewlines)
            let trim = clean.isEmpty ? 0 : (line as NSString).range(of:clean).location
            let cleanStart = lineStart + trim
            if clean.hasPrefix("```") {
                flush()
                if fenced { append(.code,code.joined(separator:"\n"),codeStart); code = [] }
                else { codeStart = offset }
                fenced.toggle(); continue
            }
            if fenced { code.append(line); continue }
            if clean.isEmpty { flush(); continue }
            if clean == "---" || clean == "***" { flush(); append(.rule,"",cleanStart); continue }
            let hashes = clean.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), clean.dropFirst(hashes).first == " " {
                flush(); append(.heading,String(clean.dropFirst(hashes + 1)),cleanStart + hashes + 1,hashes); continue
            }
            if clean.hasPrefix("> ") { flush(); append(.quote,String(clean.dropFirst(2)),cleanStart + 2); continue }
            if clean.hasPrefix("- ") || clean.hasPrefix("* ") || clean.hasPrefix("+ ") {
                flush()
                let content = String(clean.dropFirst(2))
                if content.hasPrefix("[ ] ") { append(.list,"☐ " + content.dropFirst(4),cleanStart,0,2,6) }
                else if content.lowercased().hasPrefix("[x] ") { append(.list,"☑ " + content.dropFirst(4),cleanStart,0,2,6) }
                else { append(.list,"• " + content,cleanStart,0,2,2) }
                continue
            }
            if clean.range(of:#"^\d+\.\s+"#,options:.regularExpression) != nil { flush(); append(.list,clean,cleanStart); continue }
            if buffer.isEmpty { bufferStart = lineStart }
            buffer.append(line)
        }
        flush(); if fenced { append(.code,code.joined(separator:"\n"),codeStart) }
        return result
    }
    static func sourceCaret(in block: Block,renderedOffset: Int) -> Int {
        let local = block.kind == .code ? min(max(0,renderedOffset),block.text.utf16.count) : inlineSourceOffset(renderedOffset,in:block.text)
        let adjusted = local >= block.renderedPrefixLength ? local - block.renderedPrefixLength + block.sourcePrefixLength : 0
        return block.sourceStart + adjusted
    }

    /// Use Markdown source positions, rather than matching repeated words across the whole note.
    static func inlineSourceOffset(_ renderedOffset: Int,in text: String) -> Int {
        let begin = "\u{F0000}", end = "\u{F0001}"
        var source = text, origins = Array(0...text.utf16.count)
        for (tag,marker) in [("<u>",begin),("</u>",end)] {
            let value = source as NSString
            let matches = (try? NSRegularExpression(pattern:NSRegularExpression.escapedPattern(for:tag)).matches(in:source,range:NSRange(location:0,length:value.length))) ?? []
            for match in matches.reversed() {
                let start = origins[match.range.location]
                source = (source as NSString).replacingCharacters(in:match.range,with:marker)
                origins.replaceSubrange(match.range.location..<NSMaxRange(match.range),with:Array(repeating:start,count:marker.utf16.count))
            }
        }
        guard let parsed = try? AttributedString(markdown:source,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace,appliesSourcePositionAttributes:true)) else { return min(max(0,renderedOffset),text.utf16.count) }
        var offsets: [Int] = [], finalOffset = 0
        var lineOffsets = [0]
        for line in source.components(separatedBy:"\n").dropLast() { lineOffsets.append(lineOffsets.last! + line.utf8.count + 1) }
        let bytes = source.utf8
        struct Token { let character: Character; let start: Int; let end: Int }
        func tokens(_ range: NSRange,code: Bool) -> [Token] {
            let fragment = (source as NSString).substring(with:range)
            let characters = Array(fragment)
            var result: [Token] = [], index = 0, position = range.location
            while index < characters.count {
                let character = characters[index]
                if !code, character == "\\", index + 1 < characters.count,
                   characters[index + 1].unicodeScalars.allSatisfy({ CharacterSet.punctuationCharacters.union(.symbols).contains($0) }) {
                    position += 1; index += 1
                    let escaped = characters[index], length = String(escaped).utf16.count
                    result.append(Token(character:escaped,start:position,end:position + length)); position += length; index += 1; continue
                }
                if !code, character == "&", let closing = characters[index...].prefix(12).firstIndex(of:";") {
                    let entity = String(characters[index...closing])
                    let decoded: String?
                    switch entity {
                    case "&amp;": decoded = "&"
                    case "&lt;": decoded = "<"
                    case "&gt;": decoded = ">"
                    case "&quot;": decoded = "\""
                    case "&apos;", "&#39;": decoded = "'"
                    default:
                        if entity.hasPrefix("&#"), entity.hasSuffix(";") {
                            let digits = String(entity.dropFirst(entity.lowercased().hasPrefix("&#x") ? 3 : 2).dropLast())
                            decoded = UInt32(digits,radix:entity.lowercased().hasPrefix("&#x") ? 16 : 10).flatMap(UnicodeScalar.init).map(String.init)
                        } else {
                            let value = try? AttributedString(markdown:entity,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))
                            decoded = value.map { String($0.characters) }.flatMap { $0 == entity ? nil : $0 }
                        }
                    }
                    if let decoded {
                        for value in decoded { result.append(Token(character:value,start:position,end:position + entity.utf16.count)) }
                        position += entity.utf16.count; index = closing + 1; continue
                    }
                }
                let length = String(character).utf16.count
                result.append(Token(character:character,start:position,end:position + length)); position += length; index += 1
            }
            return result
        }
        for run in parsed.runs {
            guard let position = run.markdownSourcePosition,
                  lineOffsets.indices.contains(position.startLine - 1), lineOffsets.indices.contains(position.endLine - 1) else { continue }
            let lower = lineOffsets[position.startLine - 1] + position.startColumn - 1
            let upper = lineOffsets[position.endLine - 1] + position.endColumn
            guard lower >= 0, upper >= lower, upper <= bytes.count,
                  let start = String.Index(bytes.index(bytes.startIndex,offsetBy:lower),within:source),
                  let endIndex = String.Index(bytes.index(bytes.startIndex,offsetBy:upper),within:source) else { continue }
            let range = NSRange(start..<endIndex,in:source), isCode = run.inlinePresentationIntent?.contains(.code) == true
            let candidates = tokens(range,code:isCode)
            var cursor = 0
            for character in parsed[run.range].characters {
                guard let match = candidates[cursor...].firstIndex(where:{ $0.character == character || ($0.character.isWhitespace && character.isWhitespace) }) else { continue }
                let token = candidates[match]; cursor = match + 1
                if String(character) == begin || String(character) == end {
                    if !isCode { continue }
                    let literal = String(character) == begin ? "<u>" : "</u>"
                    let originalStart = origins[token.start], originalEnd = origins[token.end]
                    offsets.append(contentsOf:(0..<literal.utf16.count).map { min(originalEnd,originalStart + $0) }); finalOffset = originalEnd
                } else {
                    let count = String(character).utf16.count
                    let originalStart = origins[token.start], originalEnd = origins[token.end]
                    offsets.append(contentsOf:(0..<count).map { count == originalEnd - originalStart ? originalStart + $0 : originalStart })
                    finalOffset = originalEnd
                }
            }
        }
        offsets.append(finalOffset)
        return offsets[min(max(0,renderedOffset),offsets.count - 1)]
    }
    static func attributedInline(_ text: String,font base: NSFont,color: NSColor = .black) -> NSAttributedString {
        let parsed = inline(text), result = NSMutableAttributedString(string:"")
        for run in parsed.runs {
            var font = base
            let intent = run.inlinePresentationIntent
            if intent?.contains(.code) == true { font = .monospacedSystemFont(ofSize:base.pointSize,weight:.regular) }
            if intent?.contains(.stronglyEmphasized) == true { font = NSFontManager.shared.convert(font,toHaveTrait:.boldFontMask) }
            var attributes: [NSAttributedString.Key:Any] = [.font:font,.foregroundColor:color]
            // CJK system fonts often have no italic face. An explicit slant also covers fallback glyphs.
            if intent?.contains(.emphasized) == true { attributes[.obliqueness] = 0.2 }
            if intent?.contains(.code) == true { attributes[.backgroundColor] = NSColor.secondaryLabelColor.withAlphaComponent(0.12) }
            if intent?.contains(.strikethrough) == true { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if run.underlineStyle != nil { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { attributes[.link] = link; attributes[.foregroundColor] = NSColor.systemBlue }
            result.append(NSAttributedString(string:String(parsed[run.range].characters),attributes:attributes))
        }
        return result
    }
    static func highlighting(_ text: NSAttributedString,query: String) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString:text)
        let source = text.string as NSString
        for term in query.split(whereSeparator:\.isWhitespace) {
            var remaining = NSRange(location:0,length:source.length)
            while remaining.length > 0 {
                let match = source.range(of:String(term),options:[.caseInsensitive,.diacriticInsensitive],range:remaining)
                guard match.location != NSNotFound else { break }
                result.addAttribute(.backgroundColor,value:NSColor.controlAccentColor.withAlphaComponent(0.2),range:match)
                remaining = NSRange(location:NSMaxRange(match),length:source.length - NSMaxRange(match))
            }
        }
        return result
    }
    /// Keep the source and selection intact while giving complete inline markers a live preview.
    static func styleEditor(_ view: NSTextView) {
        guard !view.hasMarkedText(), let storage = view.textStorage else { return }
        let selection = view.selectedRanges
        let source = view.string as NSString, full = NSRange(location:0,length:source.length)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 4
        let base: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:13),.foregroundColor:NSColor.labelColor,.paragraphStyle:paragraph]
        storage.beginEditing()
        storage.setAttributes(base,range:full)
        if let parsed = try? AttributedString(markdown:view.string,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace,appliesSourcePositionAttributes:true)) {
            // Markdown columns count UTF-8 bytes, including for Chinese and emoji.
            let lines = view.string.components(separatedBy:"\n")
            var lineOffsets = [0]
            for line in lines.dropLast() { lineOffsets.append(lineOffsets.last! + line.utf8.count + 1) }
            let bytes = view.string.utf8
            storage.addAttribute(.foregroundColor,value:NSColor.tertiaryLabelColor,range:full)
            for run in parsed.runs {
                guard let position = run.markdownSourcePosition,
                      lineOffsets.indices.contains(position.startLine - 1), lineOffsets.indices.contains(position.endLine - 1) else { continue }
                let lower = lineOffsets[position.startLine - 1] + position.startColumn - 1
                let upper = lineOffsets[position.endLine - 1] + position.endColumn
                guard lower >= 0, upper >= lower, upper <= bytes.count,
                      let start = String.Index(bytes.index(bytes.startIndex,offsetBy:lower),within:view.string),
                      let end = String.Index(bytes.index(bytes.startIndex,offsetBy:upper),within:view.string) else { continue }
                let range = NSRange(start..<end,in:view.string), intent = run.inlinePresentationIntent
                var attributes: [NSAttributedString.Key:Any] = [.foregroundColor:NSColor.labelColor]
                if intent?.contains(.code) == true {
                    attributes[.font] = NSFont.monospacedSystemFont(ofSize:13,weight:.regular)
                    attributes[.backgroundColor] = NSColor.secondaryLabelColor.withAlphaComponent(0.12)
                } else {
                    if intent?.contains(.stronglyEmphasized) == true { attributes[.font] = NSFont.boldSystemFont(ofSize:13) }
                    if intent?.contains(.emphasized) == true { attributes[.obliqueness] = 0.2 }
                }
                if intent?.contains(.strikethrough) == true { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                storage.addAttributes(attributes,range:range)
            }
        }
        for block in blocks(view.string) where block.kind == .heading {
            let line = source.lineRange(for:NSRange(location:min(block.sourceStart,source.length),length:0))
            let size: CGFloat = block.level == 1 ? 18 : block.level == 2 ? 16 : 14
            var fonts: [(NSRange,NSFont)] = []
            storage.enumerateAttribute(.font,in:line) { value,range,_ in
                let existing = value as? NSFont ?? .systemFont(ofSize:13)
                let bold = NSFontManager.shared.traits(of:existing).contains(.boldFontMask)
                let font = existing.isFixedPitch ? NSFont.monospacedSystemFont(ofSize:size,weight:bold ? .bold : .regular) : .systemFont(ofSize:size,weight:bold ? .bold : .semibold)
                fonts.append((range,font))
            }
            for (range,font) in fonts { storage.addAttribute(.font,value:font,range:range) }
            storage.addAttribute(.foregroundColor,value:NSColor.tertiaryLabelColor,range:NSRange(location:line.location,length:max(0,block.sourceStart - line.location)))
        }
        storage.endEditing()
        view.typingAttributes = base
        if view.selectedRanges != selection { view.selectedRanges = selection }
    }
}

/// AppKit preserves synthetic CJK italics and inline backgrounds that SwiftUI Text drops.
struct NoteInlineText: NSViewRepresentable {
    let text: String
    var size: CGFloat = 13
    var weight: NSFont.Weight = .regular
    var secondary = false
    var lineLimit = 0
    var searchText = ""
    var verbatim = false
    var activated: ((Int,NoteEditAnchor) -> Void)? = nil

    final class Label: NSTextField {
        var activated: ((Int,NoteEditAnchor) -> Void)?
        override func hitTest(_ point: NSPoint) -> NSView? { activated == nil ? nil : super.hitTest(point) }
        override func mouseDown(with event: NSEvent) {
            guard let activated else { super.mouseDown(with:event); return }
            let storage = NSTextStorage(attributedString:attributedStringValue), layout = NSLayoutManager()
            let rect = cell?.titleRect(forBounds:bounds) ?? bounds
            let container = NSTextContainer(containerSize:NSSize(width:max(1,rect.width),height:.greatestFiniteMagnitude))
            container.lineFragmentPadding = 0; container.maximumNumberOfLines = maximumNumberOfLines
            container.lineBreakMode = lineBreakMode
            storage.addLayoutManager(layout); layout.addTextContainer(container); layout.ensureLayout(for:container)
            let location = convert(event.locationInWindow,from:nil)
            let point = NSPoint(x:location.x - rect.minX,y:location.y - rect.minY)
            let offset: Int
            if storage.length == 0 || layout.numberOfGlyphs == 0 { offset = 0 }
            else if point.y > layout.usedRect(for:container).maxY { offset = storage.length }
            else {
                var fraction: CGFloat = 0
                let glyph = min(layout.numberOfGlyphs - 1,layout.glyphIndex(for:point,in:container,fractionOfDistanceThroughGlyph:&fraction))
                let range = layout.characterRange(forGlyphRange:NSRange(location:glyph,length:1),actualGlyphRange:nil)
                offset = fraction >= 0.5 ? NSMaxRange(range) : range.location
            }
            activated(offset,NoteEditAnchor(view:self))
        }
    }
    func makeNSView(context: Context) -> Label {
        let label = Label(wrappingLabelWithString:"")
        label.isSelectable = false
        label.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        return label
    }
    func updateNSView(_ label: Label,context: Context) {
        label.activated = activated
        let rendered = verbatim ? NSAttributedString(string:text,attributes:[.font:NSFont.monospacedSystemFont(ofSize:size,weight:weight),.foregroundColor:NSColor.labelColor]) : NoteMarkdown.attributedInline(text,font:.systemFont(ofSize:size,weight:weight),color:secondary ? .secondaryLabelColor : .labelColor)
        let attributed = NSMutableAttributedString(attributedString:NoteMarkdown.highlighting(rendered,query:searchText))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.lineBreakMode = lineLimit == 1 ? .byTruncatingTail : .byWordWrapping
        attributed.addAttribute(.paragraphStyle,value:paragraph,range:NSRange(location:0,length:attributed.length))
        label.maximumNumberOfLines = lineLimit
        label.lineBreakMode = paragraph.lineBreakMode
        if !label.attributedStringValue.isEqual(to:attributed) { label.attributedStringValue = attributed }
    }
    func sizeThatFits(_ proposal: ProposedViewSize,nsView label: Label,context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0, let cell = label.cell else { return nil }
        let measured = cell.cellSize(forBounds:NSRect(x:0,y:0,width:width,height:.greatestFiniteMagnitude))
        return CGSize(width:width,height:ceil(measured.height))
    }
}

struct NoteMarkdownView: View {
    let text: String
    var searchText = ""
    var activated: ((Int,NoteEditAnchor) -> Void)? = nil
    private func activation(for block: NoteMarkdown.Block) -> ((Int,NoteEditAnchor) -> Void)? {
        guard let activated else { return nil }
        return { offset,anchor in activated(NoteMarkdown.sourceCaret(in:block,renderedOffset:offset),anchor) }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            ForEach(NoteMarkdown.blocks(text)) { block in
                switch block.kind {
                case .heading:
                    NoteInlineText(text:block.text,size:block.level == 1 ? 18 : block.level == 2 ? 16 : 14,weight:.semibold,searchText:searchText,activated:activation(for:block))
                        .padding(.top,3)
                case .quote:
                    HStack(alignment:.top,spacing:9) {
                        RoundedRectangle(cornerRadius:1).fill(.secondary.opacity(0.22)).frame(width:2)
                        NoteInlineText(text:block.text,secondary:true,searchText:searchText,activated:activation(for:block))
                    }.fixedSize(horizontal:false,vertical:true)
                case .code:
                    NoteInlineText(text:block.text,size:12,searchText:searchText,verbatim:true,activated:activation(for:block)).padding(8)
                        .frame(maxWidth:.infinity,alignment:.leading).background(.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:5))
                case .rule: Divider().opacity(0.4)
                case .paragraph,.list: NoteInlineText(text:block.text,searchText:searchText,activated:activation(for:block))
                }
            }
        }.font(.system(size:13)).lineSpacing(4).frame(maxWidth:.infinity,alignment:.leading)
            .fixedSize(horizontal:false,vertical:true)
    }
}
