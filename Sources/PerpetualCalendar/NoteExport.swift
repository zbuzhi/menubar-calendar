import AppKit
import CoreText
import UniformTypeIdentifiers
import CalendarCore

/// All export layout uses frameworks already present in macOS; no browser or PDF dependency.
@MainActor enum NoteExport {
    enum Format { case pdf, markdown, json }
    static func save(_ document: NoteDocument,format: Format,title: String,state: AppState) {
        let panel = NSSavePanel()
        let ext: String
        switch format {
        case .pdf: ext = "pdf"; panel.allowedContentTypes = [.pdf]
        case .markdown: ext = "md"; panel.allowedContentTypes = [UTType(filenameExtension:"md") ?? .plainText]
        case .json: ext = "json"; panel.allowedContentTypes = [.json]
        }
        panel.nameFieldStringValue = "\(AppBrand.noteExportName)-\(title).\(ext)"
        guard NoteSaveDialog.run(panel) == .OK, let url = panel.url else { return }
        do {
            let data: Data
            switch format {
            case .pdf: data = try pdf(document,title:title)
            case .markdown: data = Data(markdown(document,title:title).utf8)
            case .json: data = try document.encoded()
            }
            try data.write(to:url,options:.atomic); state.message("小记已导出")
        } catch { state.message("导出失败：\(error.localizedDescription)") }
    }
    private static func groups(_ document: NoteDocument) -> [(String,[NoteEntry])] {
        var result: [(String,[NoteEntry])] = []
        let ids = Set(document.tags.map(\.id))
        let entries = document.entries.filter { !$0.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }
        let untagged = entries.filter { $0.tagIDs.first(where:{ ids.contains($0) }) == nil }
        if !untagged.isEmpty { result.append(("未归类",untagged)) }
        for tag in document.tags {
            let notes = entries.filter { $0.tagIDs.first(where:{ ids.contains($0) }) == tag.id }
            if !notes.isEmpty { result.append((tag.name,notes)) }
        }
        return result
    }
    private static func metadata(_ entry: NoteEntry,document: NoteDocument) -> String {
        var parts = [entry.date,entry.isCompleted ? "已完成" : "待完成"]
        if let minutes = entry.dueMinutes { parts.append(String(format:"预计 %02d:%02d",minutes / 60,minutes % 60)) }
        let tags = document.tags.filter { entry.tagIDs.contains($0.id) }.map(\.name)
        if tags.count > 1 { parts.append(tags.joined(separator:" / ")) }
        return parts.joined(separator:" · ")
    }
    static func markdown(_ document: NoteDocument,title: String) -> String {
        var result = "# \(title)\n\n"
        for (name,entries) in groups(document) {
            result += "## \(name)\n\n"
            for entry in entries {
                result += "### \(metadata(entry,document:document))\n\n\(entry.text)\n\n---\n\n"
            }
        }
        return result
    }
    static func pdf(_ document: NoteDocument,title: String) throws -> Data {
        let content = NSMutableAttributedString(string:"")
        func append(_ text: NSAttributedString,before: CGFloat = 0,after: CGFloat = 8) {
            let line = NSMutableAttributedString(attributedString:text)
            line.append(NSAttributedString(string:"\n"))
            let style = NSMutableParagraphStyle(); style.lineSpacing = 5
            style.paragraphSpacingBefore = before; style.paragraphSpacing = after
            line.addAttribute(.paragraphStyle,value:style,range:NSRange(location:0,length:line.length))
            content.append(line)
        }
        func plain(_ text: String,_ size: CGFloat,_ weight: NSFont.Weight = .regular,_ color: NSColor = .black) -> NSAttributedString {
            NSAttributedString(string:text,attributes:[.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color])
        }
        append(plain(title,25,.semibold),after:6)
        let count = document.entries.filter { !$0.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }.count
        append(plain("\(count) 条记录 · 日历小记",10,.regular,.gray),after:22)
        for (name,entries) in groups(document) {
            append(plain(name,15,.semibold,NSColor(calibratedRed:0.2,green:0.35,blue:0.5,alpha:1)),before:14,after:12)
            for entry in entries {
                append(plain(metadata(entry,document:document),9,.medium,.gray),before:8,after:7)
                for block in NoteMarkdown.blocks(entry.text) {
                    switch block.kind {
                    case .heading:
                        append(NoteMarkdown.attributedInline(block.text,font:.systemFont(ofSize:block.level == 1 ? 18 : 15,weight:.semibold)),before:5,after:8)
                    case .code:
                        append(NSAttributedString(string:block.text,attributes:[.font:NSFont.monospacedSystemFont(ofSize:10,weight:.regular),.foregroundColor:NSColor(calibratedWhite:0.3,alpha:1)]),after:10)
                    case .quote:
                        append(NoteMarkdown.attributedInline("│ " + block.text,font:.systemFont(ofSize:11),color:.gray),after:8)
                    case .rule:
                        append(plain("────────────────────────────────",9,.regular,NSColor(calibratedWhite:0.82,alpha:1)),after:10)
                    case .paragraph,.list:
                        append(NoteMarkdown.attributedInline(block.text,font:.systemFont(ofSize:11.5)),after:block.kind == .list ? 4 : 9)
                    }
                }
                append(plain("",4),after:7)
            }
        }
        let framesetter = CTFramesetterCreateWithAttributedString(content)
        let body = CGRect(x:52,y:60,width:491,height:712)
        let path = CGPath(rect:body,transform:nil)
        var ranges: [CFRange] = [], offset = 0
        while offset < content.length {
            let frame = CTFramesetterCreateFrame(framesetter,CFRange(location:offset,length:0),path,nil)
            let range = CTFrameGetVisibleStringRange(frame)
            guard range.length > 0 else { throw CocoaError(.fileWriteUnknown) }
            ranges.append(range); offset += range.length
        }
        let data = NSMutableData()
        var media = CGRect(x:0,y:0,width:595,height:842)
        guard let consumer = CGDataConsumer(data:data), let context = CGContext(consumer:consumer,mediaBox:&media,
                [kCGPDFContextTitle as String:title,kCGPDFContextCreator as String:AppBrand.name] as CFDictionary) else { throw CocoaError(.fileWriteUnknown) }
        func draw(_ text: NSAttributedString,x: CGFloat,y: CGFloat) {
            context.textMatrix = .identity
            context.textPosition = CGPoint(x:x,y:y); CTLineDraw(CTLineCreateWithAttributedString(text),context)
        }
        for (index,range) in ranges.enumerated() {
            context.beginPDFPage(nil)
            context.setFillColor(NSColor.white.cgColor); context.fill(media)
            draw(plain("日历  /  小记",9,.medium,.gray),x:52,y:802)
            context.setStrokeColor(NSColor(calibratedWhite:0.88,alpha:1).cgColor)
            context.setLineWidth(0.5); context.move(to:CGPoint(x:52,y:788)); context.addLine(to:CGPoint(x:543,y:788)); context.strokePath()
            context.textMatrix = .identity
            CTFrameDraw(CTFramesetterCreateFrame(framesetter,range,path,nil),context)
            draw(plain("本机记录 · \(count) 条",8,.regular,.gray),x:52,y:32)
            draw(plain("\(index + 1) / \(ranges.count)",8,.regular,.gray),x:515,y:32)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}
