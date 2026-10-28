import AppKit
import SwiftUI

final class NoteEditAnchor {
    private weak var scrollView: NSScrollView?
    private let origin: NSPoint?
    init(view: NSView) { scrollView = view.enclosingScrollView; origin = scrollView?.contentView.bounds.origin }
    func restore() {
        guard let scrollView, let origin else { return }
        let clip = scrollView.contentView
        let target = clip.constrainBoundsRect(NSRect(origin:origin,size:clip.bounds.size)).origin
        clip.scroll(to:target); scrollView.reflectScrolledClipView(clip)
    }
}

final class GrowingNoteTextView: NSTextView {
    private var textInputDepth = 0
    var isProcessingTextInput: Bool { textInputDepth > 0 }
    // Input methods temporarily clear marked text before finishing the replacement and caret.
    // Keep SwiftUI refreshes from writing an older binding snapshot into that transaction.
    override func insertText(_ insertString: Any,replacementRange: NSRange) {
        textInputDepth += 1
        defer { textInputDepth -= 1 }
        super.insertText(insertString,replacementRange:replacementRange)
    }
    override func setMarkedText(_ string: Any,selectedRange: NSRange,replacementRange: NSRange) {
        textInputDepth += 1
        defer { textInputDepth -= 1 }
        super.setMarkedText(string,selectedRange:selectedRange,replacementRange:replacementRange)
    }
    var editingUndo: UndoManager?
    var commit: ((String) -> Void)?
    var didEnd: (() -> Void)?
    var continueWriting: (() -> Void)?
    var windowReady: (() -> Void)?
    private(set) var continuing = false
    func resetContinuation() { continuing = false }
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
        if event.keyCode == 36 || event.keyCode == 76 {
            guard !event.isARepeat, !continuing else { return true }
            commitText(); continuing = true; continueWriting?(); return true
        }
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
    override func didChangeText() { continuing = false; super.didChangeText() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window != nil { windowReady?() } }
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
    var initialCaretOffset: Int? = nil
    var activation: NoteEditAnchor? = nil
    var caretChanged: (Int) -> Void = { _ in }
    var continueWriting: () -> Void = {}
    var editEnded: (NoteEditAnchor) -> Void = { _ in }
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
        view.didEnd = { [weak view, weak coordinator = context.coordinator] in
            if let view, let coordinator, coordinator.active, !view.continuing {
                coordinator.parent.editEnded(NoteEditAnchor(view:view))
            }
            DispatchQueue.main.async { if let coordinator, coordinator.active { coordinator.parent.ended() } }
        }
        view.continueWriting = { [weak coordinator = context.coordinator] in
            guard let coordinator, coordinator.active else { return }
            coordinator.parent.continueWriting()
        }
        view.windowReady = { [weak view, weak coordinator = context.coordinator] in
            if let view { coordinator?.requestFocus(view) }
        }
        view.string = text
        view.textStorage?.addAttribute(.paragraphStyle,value:paragraph,range:NSRange(location:0,length:view.string.utf16.count))
        context.coordinator.style(view)
        view.setAccessibilityLabel("小记内容")
        view.geometryChanged = { [weak view, weak coordinator = context.coordinator] in
            if let view { coordinator?.measure(view) }
        }
        context.coordinator.requestFocus(view)
        return view
    }
    func updateNSView(_ view: NSTextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.synchronizeText(view)
        context.coordinator.style(view)
        context.coordinator.measure(view)
        context.coordinator.requestFocus(view)
    }
    static func dismantleNSView(_ view: NSTextView,coordinator: Coordinator) {
        coordinator.active = false
        if let view = view as? GrowingNoteTextView {
            view.commit = nil; view.didEnd = nil; view.continueWriting = nil; view.windowReady = nil; view.geometryChanged = nil
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize,nsView view: NSTextView,context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let measured = context.coordinator.measure(view,width:width)
        return CGSize(width:width,height:measured)
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        private var pendingHeight: CGFloat?
        private var updateScheduled = false
        private var styledText: String?
        private var styleScheduled = false
        var active = true
        private var focused = false
        var parent: NoteTextEditor
        init(_ parent: NoteTextEditor) { self.parent = parent }
        func synchronizeText(_ view: NSTextView) {
            let text = parent.text
            guard view.string != text, !view.hasMarkedText(),
                  (view as? GrowingNoteTextView)?.isProcessingTextInput != true else { return }
            let selection = view.selectedRange()
            view.string = text
            (view as? GrowingNoteTextView)?.resetContinuation()
            view.setSelectedRange(NSRange(location:min(selection.location,text.utf16.count),length:0))
        }
        func requestFocus(_ view: NSTextView) {
            guard parent.focus, !focused else { return }
            DispatchQueue.main.async { [weak self,weak view] in
                guard let self, self.active, self.parent.focus, !self.focused, let view, let window = view.window else { return }
                self.focused = true
                let caret = min(max(0,self.parent.initialCaretOffset ?? view.string.utf16.count),view.string.utf16.count)
                view.setSelectedRange(NSRange(location:caret,length:0))
                window.makeFirstResponder(view)
                self.parent.activation?.restore()
                DispatchQueue.main.async { [weak self,weak view] in
                    guard let self, self.active, let view, view.window?.firstResponder === view else { return }
                    self.parent.activation?.restore()
                }
            }
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard active, let view = notification.object as? NSTextView, view.window?.firstResponder === view else { return }
            parent.caretChanged(view.selectedRange().location)
        }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            if !view.hasMarkedText(), parent.text != view.string { parent.text = view.string }
            style(view); measure(view)
        }
        func style(_ view: NSTextView) {
            guard !view.hasMarkedText(), styledText != view.string else { return }
            if (view as? GrowingNoteTextView)?.isProcessingTextInput == true {
                guard !styleScheduled else { return }
                styleScheduled = true
                DispatchQueue.main.async { [weak self,weak view] in
                    guard let self else { return }
                    self.styleScheduled = false
                    guard self.active, let view else { return }
                    self.style(view); self.measure(view)
                }
                return
            }
            styledText = view.string
            NoteMarkdown.styleEditor(view)
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
