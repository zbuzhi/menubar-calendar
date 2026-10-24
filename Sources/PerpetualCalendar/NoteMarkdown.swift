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
        var fenced = false
        func append(_ kind: Kind,_ text: String,_ level: Int = 0) { result.append(Block(id:result.count,kind:kind,text:text,level:level)) }
        func flush() { if !buffer.isEmpty { append(.paragraph,buffer.joined(separator:"\n")); buffer = [] } }
        for line in source.components(separatedBy:.newlines) {
            let clean = line.trimmingCharacters(in:.whitespaces)
            if clean.hasPrefix("```") { flush(); if fenced { append(.code,code.joined(separator:"\n")); code = [] }; fenced.toggle(); continue }
            if fenced { code.append(line); continue }
            if clean.isEmpty { flush(); continue }
            if clean == "---" || clean == "***" { flush(); append(.rule,""); continue }
            let hashes = clean.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), clean.dropFirst(hashes).first == " " {
                flush(); append(.heading,String(clean.dropFirst(hashes + 1)),hashes); continue
            }
            if clean.hasPrefix("> ") { flush(); append(.quote,String(clean.dropFirst(2))); continue }
            if clean.hasPrefix("- ") || clean.hasPrefix("* ") || clean.hasPrefix("+ ") {
                flush()
                var content = String(clean.dropFirst(2))
                if content.hasPrefix("[ ] ") { content = "☐ " + content.dropFirst(4) }
                else if content.lowercased().hasPrefix("[x] ") { content = "☑ " + content.dropFirst(4) }
                else { content = "• " + content }
                append(.list,content); continue
            }
            if clean.range(of:#"^\d+\.\s+"#,options:.regularExpression) != nil { flush(); append(.list,clean); continue }
            buffer.append(line)
        }
        flush(); if fenced { append(.code,code.joined(separator:"\n")) }
        return result
    }
    static func attributedInline(_ text: String,font base: NSFont,color: NSColor = .black) -> NSAttributedString {
        let parsed = inline(text), result = NSMutableAttributedString(string:"")
        for run in parsed.runs {
            var font = base
            let intent = run.inlinePresentationIntent
            if intent?.contains(.code) == true { font = .monospacedSystemFont(ofSize:base.pointSize - 1,weight:.regular) }
            if intent?.contains(.stronglyEmphasized) == true { font = NSFontManager.shared.convert(font,toHaveTrait:.boldFontMask) }
            if intent?.contains(.emphasized) == true { font = NSFontManager.shared.convert(font,toHaveTrait:.italicFontMask) }
            var attributes: [NSAttributedString.Key:Any] = [.font:font,.foregroundColor:color]
            if intent?.contains(.strikethrough) == true { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if run.underlineStyle != nil { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { attributes[.link] = link; attributes[.foregroundColor] = NSColor.systemBlue }
            result.append(NSAttributedString(string:String(parsed[run.range].characters),attributes:attributes))
        }
        return result
    }
}

struct NoteMarkdownView: View {
    let text: String
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            ForEach(NoteMarkdown.blocks(text)) { block in
                switch block.kind {
                case .heading:
                    Text(NoteMarkdown.inline(block.text)).font(.system(size:block.level == 1 ? 18 : block.level == 2 ? 16 : 14,weight:.semibold))
                        .padding(.top,3)
                case .quote:
                    HStack(alignment:.top,spacing:9) {
                        RoundedRectangle(cornerRadius:1).fill(.secondary.opacity(0.22)).frame(width:2)
                        Text(NoteMarkdown.inline(block.text)).foregroundStyle(.secondary)
                    }.fixedSize(horizontal:false,vertical:true)
                case .code:
                    Text(block.text).font(.system(size:12,design:.monospaced)).padding(8)
                        .frame(maxWidth:.infinity,alignment:.leading).background(.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:5))
                case .rule: Divider().opacity(0.4)
                case .paragraph,.list: Text(NoteMarkdown.inline(block.text))
                }
            }
        }.font(.system(size:13)).lineSpacing(4).frame(maxWidth:.infinity,alignment:.leading)
            .fixedSize(horizontal:false,vertical:true)
    }
}
