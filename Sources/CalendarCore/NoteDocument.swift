import Foundation

public struct NoteTag: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var color: String?
    public init(id: UUID = UUID(), name: String, color: String? = nil) { self.id = id; self.name = name; self.color = color }
}

public struct NoteEntry: Codable, Equatable, Identifiable {
    public var id: UUID
    /// Civil date in Asia/Shanghai; deliberately independent of timestamp time zones.
    public var date: String
    public var text: String
    public var tagIDs: [UUID]
    public var dueMinutes: Int?
    public var isCompleted: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public init(id: UUID = UUID(), date: String, text: String = "", tagIDs: [UUID] = [],
                isCompleted: Bool = false, dueMinutes: Int? = nil, now: Date = Date()) {
        self.id = id; self.date = date; self.text = text; self.tagIDs = tagIDs
        self.dueMinutes = dueMinutes; self.isCompleted = isCompleted; createdAt = now; updatedAt = now
    }
}

public struct NoteDocument: Codable, Equatable {
    public static let currentVersion = 3
    public var schemaVersion = currentVersion
    public var tags: [NoteTag]
    /// Array order is the stable display order. Entries may belong to multiple tags.
    public var entries: [NoteEntry]
    public init(tags: [NoteTag] = [NoteTag(name:"工作",color:"blue"), NoteTag(name:"生活",color:"green"), NoteTag(name:"学习",color:"orange"), NoteTag(name:"个人",color:"purple")], entries: [NoteEntry] = []) {
        self.tags = tags; self.entries = entries
    }
    public static func migrate(_ legacy: [String: String]) -> NoteDocument {
        var document = NoteDocument()
        document.entries = legacy.sorted { $0.key < $1.key }.filter { !$0.value.isEmpty }.map {
            NoteEntry(date: $0.key, text: $0.value)
        }
        return document
    }
    public static func decode(_ data: Data) throws -> NoteDocument {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var document = try decoder.decode(NoteDocument.self, from: data)
        try document.validate()
        if document.schemaVersion == 2 {
            let colors = ["工作":"blue","生活":"green","学习":"orange","个人":"purple"]
            for i in document.tags.indices where document.tags[i].color == nil { document.tags[i].color = colors[document.tags[i].name] ?? "blue" }
        }
        document.schemaVersion = currentVersion
        return document
    }
    public func validate() throws {
        guard (2...Self.currentVersion).contains(schemaVersion) else { throw CocoaError(.coderReadCorrupt) }
        let ids = Set(tags.map(\.id))
        guard ids.count == tags.count, Set(entries.map(\.id)).count == entries.count,
              entries.allSatisfy({ Set($0.tagIDs).isSubset(of:ids) && ($0.dueMinutes == nil || (0..<1440).contains($0.dueMinutes!)) }) else { throw CocoaError(.coderReadCorrupt) }
    }
    public func encoded(pretty: Bool = true) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }
    /// Removing a category never deletes its text. Optional transfer replaces only this association.
    public mutating func removeTag(_ id: UUID, transferringTo destination: UUID? = nil) {
        guard destination != id, destination == nil || tags.contains(where:{ $0.id == destination }) else { return }
        tags.removeAll { $0.id == id }
        for i in entries.indices where entries[i].tagIDs.contains(id) {
            entries[i].tagIDs.removeAll { $0 == id }
            if let destination, !entries[i].tagIDs.contains(destination) { entries[i].tagIDs.append(destination) }
            entries[i].updatedAt = Date()
        }
    }
    public mutating func moveTag(_ id: UUID, over target: UUID) {
        guard id != target, let source = tags.firstIndex(where:{ $0.id == id }),
              let destination = tags.firstIndex(where:{ $0.id == target }) else { return }
        let tag = tags.remove(at:source)
        tags.insert(tag,at:min(destination,tags.count))
    }
    public static func timeProgress(for entry: NoteEntry, now: Date, engine: CalendarEngine = CalendarEngine()) -> Double? {
        guard !entry.isCompleted, engine.key(now) == entry.date, let minutes = entry.dueMinutes else { return nil }
        let start = engine.calendar.startOfDay(for:now)
        let due = start.addingTimeInterval(Double(minutes) * 60)
        let created = entry.createdAt
        guard due > created else { return now >= due ? 1 : 0 }
        return min(1,max(0,now.timeIntervalSince(created) / due.timeIntervalSince(created)))
    }
    public func exportEntries(from start: String? = nil,through end: String? = nil,tagIDs: Set<UUID>,includeUntagged: Bool) -> [NoteEntry] {
        displayEntries().filter { entry in
            (start == nil || entry.date >= start!) && (end == nil || entry.date <= end!) &&
            (entry.tagIDs.isEmpty ? includeUntagged : !tagIDs.isDisjoint(with:entry.tagIDs)) &&
            !entry.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
        }
    }
    public static func isEmptyDraft(_ entry: NoteEntry) -> Bool {
        entry.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && entry.tagIDs.isEmpty && entry.dueMinutes == nil && !entry.isCompleted
    }
    public func cleaned() -> NoteDocument { var copy = self; copy.entries.removeAll(where:Self.isEmptyDraft); return copy }
    public func displayEntries(date: String? = nil,tagID: UUID? = nil) -> [NoteEntry] {
        entries(date:date,tagID:tagID).enumerated().sorted { lhs,rhs in
            if lhs.element.date != rhs.element.date { return lhs.element.date < rhs.element.date }
            let left = lhs.element.dueMinutes ?? Int.max, right = rhs.element.dueMinutes ?? Int.max
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
    }
    public func entries(date: String? = nil, tagID: UUID? = nil) -> [NoteEntry] {
        entries.filter { (date == nil || $0.date == date) && (tagID == nil || $0.tagIDs.contains(tagID!)) }
    }
}

public enum NoteSwipe {
    public static let revealDistance: CGFloat = 76
    public static func shouldConfirmDelete(_ distance: CGFloat) -> Bool { distance <= -revealDistance }
}

public enum NoteProgressTint {
    /// Muted initially; transitions continuously through orange to red near the deadline.
    public static func rgb(_ progress: Double) -> RGBColor {
        let p = min(1,max(0,progress))
        let start = RGBColor(0.56,0.62,0.68), orange = RGBColor(0.94,0.57,0.22), red = RGBColor(0.88,0.24,0.23)
        let a = p < 0.65 ? start : orange, b = p < 0.65 ? orange : red
        let t = p < 0.65 ? p / 0.65 : (p - 0.65) / 0.35
        return RGBColor(a.red + (b.red - a.red) * t,a.green + (b.green - a.green) * t,a.blue + (b.blue - a.blue) * t)
    }
}
