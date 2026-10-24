import AppKit
import SwiftUI

final class GrowingNoteTextView: NSTextView {
    var editingUndo: UndoManager?
    var commit: ((String) -> Void)?
    var didEnd: (() -> Void)?
    func commitText() { if hasMarkedText() { unmarkText() }; commit?(string) }
    override func resignFirstResponder() -> Bool {
        commitText()
        let accepted = super.resignFirstResponder()
        if accepted { didEnd?() }
        return accepted
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleMarkdownKey(event) || super.performKeyEquivalent(with:event)
    }
    func handleMarkdownKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command,.option,.control,.shift])
        guard flags == .command else { return false }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if let level = Int(key), (0...6).contains(level) { applyHeading(level); return true }
        switch key {
        case "b": wrapSelection(open:"**",close:"**")
        case "i": wrapSelection(open:"*",close:"*")
        case "u": wrapSelection(open:"<u>",close:"</u>")
        case "e", "`": wrapSelection(open:"`",close:"`")
        default:
            if event.keyCode == 50 { wrapSelection(open:"`",close:"`") } else { return false }
        }
        return true
    }
    private func replaceMarkdown(_ range: NSRange,with replacement: String,selection: NSRange) {
        guard isEditable else { return }
        insertText(replacement,replacementRange:range)
        setSelectedRange(selection)
    }
    private func wrapSelection(open: String,close: String) {
        commitText()
        let source = string as NSString, range = selectedRange()
        let left = open.utf16.count, right = close.utf16.count
        if range.location >= left, NSMaxRange(range) + right <= source.length,
           source.substring(with:NSRange(location:range.location - left,length:left)) == open,
           source.substring(with:NSRange(location:NSMaxRange(range),length:right)) == close {
            let selected = source.substring(with:range)
            replaceMarkdown(NSRange(location:range.location - left,length:range.length + left + right),with:selected,
                            selection:NSRange(location:range.location - left,length:range.length))
        } else {
            let selected = source.substring(with:range)
            replaceMarkdown(range,with:open + selected + close,selection:NSRange(location:range.location + left,length:range.length))
        }
    }
    private func applyHeading(_ level: Int) {
        commitText()
        let source = string as NSString, selection = selectedRange()
        var end = NSMaxRange(selection)
        if selection.length > 0, end > 0, source.substring(with:NSRange(location:end - 1,length:1)) == "\n" { end -= 1 }
        let lines = source.lineRange(for:NSRange(location:selection.location,length:max(0,end - selection.location)))
        let text = source.substring(with:lines)
        let prefix = level == 0 ? "" : String(repeating:"#",count:level) + " "
        let pieces = text.components(separatedBy:"\n")
        let active = level > 0 && pieces.filter { !$0.isEmpty }.allSatisfy { $0.hasPrefix(prefix) }
        let replacement = pieces.enumerated().map { index,line -> String in
            if index == pieces.count - 1 && line.isEmpty && text.hasSuffix("\n") { return "" }
            let stripped = line.replacingOccurrences(of:#"^#{1,6}\s+"#,with:"",options:.regularExpression)
            return (active ? "" : prefix) + stripped
        }.joined(separator:"\n")
        let change = replacement.utf16.count - lines.length
        let newSelection = selection.length == 0 ? NSRange(location:max(lines.location,min(lines.location + replacement.utf16.count,selection.location + change)),length:0) : NSRange(location:lines.location,length:replacement.utf16.count)
        replaceMarkdown(lines,with:replacement,selection:newSelection)
    }
    var geometryChanged: (() -> Void)?
    override var undoManager: UndoManager? { editingUndo }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        geometryChanged?()
    }
}

/// A single text view without an inner scroll view. The page scrolls as one document.
struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let undo: UndoManager
    var focus = false
    var ended: () -> Void = {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextView {
        let view = GrowingNoteTextView(frame:NSRect(x:0,y:0,width:360,height:30))
        view.editingUndo = undo; view.delegate = context.coordinator
        view.isRichText = false; view.allowsUndo = false; view.drawsBackground = false
        view.font = .systemFont(ofSize:13); view.textColor = .labelColor
        view.textContainerInset = NSSize(width:0,height:0)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 4
        view.defaultParagraphStyle = paragraph
        view.typingAttributes = [.font:NSFont.systemFont(ofSize:13),.paragraphStyle:paragraph]
        view.isVerticallyResizable = false; view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.heightTracksTextView = false
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.containerSize = NSSize(width:360,height:CGFloat.greatestFiniteMagnitude)
        view.commit = { [weak coordinator = context.coordinator] value in
            guard let coordinator, coordinator.parent.text != value else { return }
            coordinator.parent.text = value
        }
        view.didEnd = { [weak coordinator = context.coordinator] in
            DispatchQueue.main.async { coordinator?.parent.ended() }
        }
        view.string = text
        view.textStorage?.addAttribute(.paragraphStyle,value:paragraph,range:NSRange(location:0,length:view.string.utf16.count))
        view.setAccessibilityLabel("小记内容")
        view.geometryChanged = { [weak view, weak coordinator = context.coordinator] in
            if let view { coordinator?.measure(view) }
        }
        if focus { DispatchQueue.main.async { view.window?.makeFirstResponder(view) } }
        return view
    }
    func updateNSView(_ view: NSTextView, context: Context) {
        context.coordinator.parent = self
        if view.string != text && !view.hasMarkedText() {
            let selection = view.selectedRange()
            view.string = text
            view.setSelectedRange(NSRange(location:min(selection.location,text.utf16.count),length:0))
        }
        context.coordinator.measure(view)
    }
    func sizeThatFits(_ proposal: ProposedViewSize,nsView view: NSTextView,context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let measured = context.coordinator.measure(view,width:width)
        return CGSize(width:width,height:measured)
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        private var pendingHeight: CGFloat?
        private var updateScheduled = false
        var parent: NoteTextEditor
        init(_ parent: NoteTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            if !view.hasMarkedText(), parent.text != view.string { parent.text = view.string }; measure(view)
        }
        func textDidEndEditing(_ notification: Notification) {
            guard let view = notification.object as? GrowingNoteTextView else { return }; view.commitText()
        }
        @discardableResult func measure(_ view: NSTextView,width proposedWidth: CGFloat? = nil) -> CGFloat {
            let width = proposedWidth ?? view.bounds.width
            guard width.isFinite, width > 0, let container = view.textContainer, let layout = view.layoutManager else { return parent.height }
            container.widthTracksTextView = false
            container.containerSize = NSSize(width:width,height:CGFloat.greatestFiniteMagnitude)
            layout.ensureLayout(for:container)
            let size = max(ceil(layout.defaultLineHeight(for:view.font ?? .systemFont(ofSize:13))),ceil(max(layout.usedRect(for:container).maxY,layout.extraLineFragmentRect.maxY)))
            pendingHeight = size
            guard abs(parent.height - size) > 0.5 else { return size }
            guard !updateScheduled else { return size }; updateScheduled = true
            RunLoop.main.perform(inModes:[.common]) { [weak self] in
                guard let self else { return }; self.updateScheduled = false
                if let height = self.pendingHeight, abs(self.parent.height - height) > 0.5 { self.parent.height = height }
                self.pendingHeight = nil
            }
            return size
        }
    }
}
