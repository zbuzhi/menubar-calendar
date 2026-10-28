import Foundation
import CalendarCore

func checkNoteActions() {
    let engine = CalendarEngine(), now = engine.date(2026,10,27)
    let tag = NoteTag(name:"工作")
    let first = NoteEntry(date:"2026-10-26",text:"第一条",tagIDs:[tag.id],isCompleted:true,dueMinutes:18 * 60,now:now)
    let second = NoteEntry(date:"2026-10-26",text:"第二条",now:now)
    let third = NoteEntry(date:"2026-10-26",text:"第三条",now:now)
    var document = NoteDocument(tags:[tag],entries:[first,second,third])
    let receipt = NoteDeletion(document:document,ids:[first.id,third.id])
    document.entries.removeAll { $0.id != second.id }
    document.entries[0].text = "删除后继续编辑第二条"
    let fourth = NoteEntry(date:"2026-10-27",text:"新追加的记录",now:now)
    document.entries.append(fourth)
    XCTAssertEqual(receipt.missingCount(in:document),2)
    receipt.restore(into:&document)
    XCTAssertEqual(document.entries.map(\.id),[first.id,second.id,third.id,fourth.id])
    XCTAssertEqual(document.entries[1].text,"删除后继续编辑第二条")
    XCTAssertEqual(document.entries[0],first)
    XCTAssertEqual(receipt.missingCount(in:document),0)
    receipt.restore(into:&document)
    XCTAssertEqual(document.entries.count,4)

    // Removing a tag after deletion must not reintroduce an invalid reference on restore.
    let taggedReceipt = NoteDeletion(document:document,ids:[first.id])
    document.entries.removeAll { $0.id == first.id }
    document.removeTag(tag.id)
    taggedReceipt.restore(into:&document)
    XCTAssertEqual(document.entries.first(where:{ $0.id == first.id })?.tagIDs,[])
    XCTAssertTrue((try? document.validate()) != nil)

    let changed = now.addingTimeInterval(120)
    let target = engine.date(2027,1,1)
    let original = document.entries.first(where:{ $0.id == first.id })!
    XCTAssertEqual(document.reschedule([first.id,second.id],to:target,engine:engine,now:changed),2)
    let moved = document.entries.first(where:{ $0.id == first.id })!
    XCTAssertEqual(moved.date,"2027-01-01"); XCTAssertEqual(moved.updatedAt,changed)
    XCTAssertEqual(moved.text,original.text); XCTAssertEqual(moved.createdAt,original.createdAt)
    XCTAssertEqual(moved.tagIDs,original.tagIDs); XCTAssertEqual(moved.dueMinutes,original.dueMinutes)
    XCTAssertEqual(moved.isCompleted,original.isCompleted)
    XCTAssertEqual(document.entries.first(where:{ $0.id == third.id })?.date,"2026-10-26")
    XCTAssertEqual(document.reschedule([first.id],to:target,engine:engine,now:changed.addingTimeInterval(60)),0)
    XCTAssertEqual(document.entries.first(where:{ $0.id == first.id })?.updatedAt,changed)
    let nextCreatedAt = changed.addingTimeInterval(60)
    let following = document.continuation(after:first.id,now:nextCreatedAt)!
    XCTAssertEqual(following.date,"2027-01-01")
    XCTAssertEqual(following.tagIDs,moved.tagIDs)
    XCTAssertEqual(following.text,""); XCTAssertTrue(!following.isCompleted); XCTAssertNil(following.dueMinutes)
    XCTAssertEqual(following.createdAt,nextCreatedAt); XCTAssertEqual(following.updatedAt,nextCreatedAt)
    XCTAssertTrue(following.id != first.id)
    let emptyTagged = NoteEntry(date:"2026-10-27",text:" \n ",tagIDs:[tag.id])
    XCTAssertNil(NoteDocument(tags:[tag],entries:[emptyTagged]).continuation(after:emptyTagged.id))
    XCTAssertNil(document.continuation(after:UUID()))

    let day = NoteDateRange(scope:.day,anchor:now,from:now,through:now,engine:engine)
    XCTAssertEqual(day.title(scope:.day,anchor:now,now:now,engine:engine),"10月27日")
    let historic = engine.date(2025,10,27)
    XCTAssertEqual(day.title(scope:.day,anchor:historic,now:now,engine:engine),"2025年10月27日")
    let crossYear = engine.date(2027,1,1)
    let week = NoteDateRange(scope:.week,anchor:crossYear,from:now,through:now,engine:engine)
    XCTAssertEqual(week.title(scope:.week,anchor:crossYear,now:now,engine:engine),"2026/12/28–2027/01/03")
    let sameYear = NoteDateRange(scope:.week,anchor:now,from:now,through:now,engine:engine)
    XCTAssertEqual(sameYear.title(scope:.week,anchor:now,now:now,engine:engine),"10/26–11/01")
    // Moving horizontally from the date to any native button must have no dead zone.
    for width: CGFloat in [38,50,94,139] {
        let bounds = CGRect(x:6,y:0,width:width,height:28)
        for x in stride(from:25.0,through:Double(width + 85),by:1) {
            XCTAssertTrue(NoteDateNavigationRegion.contains(CGPoint(x:x,y:14),titleBounds:bounds,expanded:true))
        }
        for offset: CGFloat in [23,49,75] {
            XCTAssertTrue(NoteDateNavigationRegion.contains(CGPoint(x:width + offset,y:14),titleBounds:bounds,expanded:true))
        }
        XCTAssertTrue(!NoteDateNavigationRegion.contains(CGPoint(x:25,y:37),titleBounds:bounds,expanded:true))
        XCTAssertTrue(!NoteDateNavigationRegion.contains(CGPoint(x:width + 30,y:14),titleBounds:bounds,expanded:false))
    }
    print("Checked: selective deletion recovery, stable order, rescheduling metadata and year-aware date titles")
}
