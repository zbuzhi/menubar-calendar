import Foundation

public enum NoteCompletionFilter: String, CaseIterable {
    case all, incomplete, completed
    public var title: String {
        switch self { case .all: return "全部状态"; case .incomplete: return "未完成"; case .completed: return "已完成" }
    }
    public func matches(_ entry: NoteEntry) -> Bool {
        self == .all || entry.isCompleted == (self == .completed)
    }
}

public struct NoteQuery {
    public var range: NoteDateRange
    public var tagID: UUID?
    public var text: String
    public var completion: NoteCompletionFilter
    public init(range: NoteDateRange,tagID: UUID? = nil,text: String = "",completion: NoteCompletionFilter = .all) {
        self.range = range; self.tagID = tagID; self.text = text; self.completion = completion
    }
    public var terms: [String] { text.split(whereSeparator:\.isWhitespace).map(String.init) }
    public var hasContentFilters: Bool { !terms.isEmpty || completion != .all }
    public func entries(in document: NoteDocument,preserving editingID: UUID? = nil,preservingIDs: Set<UUID> = []) -> [NoteEntry] {
        let words = terms
        return document.displayEntries(tagID:tagID).filter { entry in
            guard range.contains(entry.date) else { return false }
            // Editing a search result must not remove its text view while the user is typing.
            if entry.id == editingID { return true }
            // Keep a just-toggled row briefly for feedback, while still honoring its search terms.
            return (completion.matches(entry) || preservingIDs.contains(entry.id)) && words.allSatisfy { entry.text.localizedStandardContains($0) }
        }
    }
}
