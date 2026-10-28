import Foundation
import CalendarCore

func checkNoteQueries() {
    let engine = CalendarEngine(), today = engine.date(2026,10,27)
    let day = NoteDateRange(scope:.day,anchor:today,from:today,through:today,engine:engine)
    let all = NoteDateRange(scope:.all,anchor:today,from:today,through:today,engine:engine)
    let tag = NoteTag(name:"工作"), otherTag = NoteTag(name:"生活")
    let current = NoteEntry(date:"2026-10-27",text:"中文 项目 Café",tagIDs:[tag.id])
    let completed = NoteEntry(date:"2026-10-27",text:"项目 CAFE",tagIDs:[tag.id],isCompleted:true)
    let history = NoteEntry(date:"2026-09-30",text:"项目 cafe",tagIDs:[tag.id])
    let other = NoteEntry(date:"2026-10-27",text:"项目 cafe",tagIDs:[otherTag.id])
    let document = NoteDocument(tags:[tag,otherTag],entries:[current,completed,history,other])
    var query = NoteQuery(range:day,tagID:tag.id,text:"  项目   CAFE \n")
    XCTAssertEqual(query.entries(in:document).map(\.id),[current.id,completed.id])
    query.completion = .incomplete
    XCTAssertEqual(query.entries(in:document).map(\.id),[current.id])
    XCTAssertEqual(query.entries(in:document,preservingIDs:[completed.id]).map(\.id),[current.id,completed.id])
    XCTAssertEqual(query.entries(in:document,preservingIDs:[]).map(\.id),[current.id])
    query.completion = .completed
    XCTAssertEqual(query.entries(in:document).map(\.id),[completed.id])
    XCTAssertEqual(query.entries(in:document,preservingIDs:[current.id]).map(\.id),[current.id,completed.id])
    // Temporary completion feedback must not pull in notes from another date or tag.
    XCTAssertEqual(query.entries(in:document,preservingIDs:[history.id,other.id]).map(\.id),[completed.id])
    query.text = "中文"
    XCTAssertEqual(query.entries(in:document,preservingIDs:[current.id,completed.id]).map(\.id),[current.id])
    query.text = "  项目   CAFE \n"
    query.range = all; query.completion = .incomplete
    XCTAssertEqual(query.entries(in:document).map(\.id),[history.id,current.id])
    query.text = "没有匹配的文字"
    XCTAssertTrue(query.entries(in:document).isEmpty)
    XCTAssertEqual(query.entries(in:document,preserving:current.id).map(\.id),[current.id])
    // Keeping an editor must not bypass the selected date or tag.
    query.range = day
    XCTAssertTrue(query.entries(in:document,preserving:history.id).isEmpty)
    XCTAssertTrue(query.entries(in:document,preserving:other.id).isEmpty)
    query.text = " \n "; query.completion = .all
    XCTAssertTrue(!query.hasContentFilters)

    let september = NoteDateRange(scope:.custom,anchor:today,from:engine.date(2026,9,1),through:engine.date(2026,9,30),engine:engine)
    let insertion = september.insertionDate(anchor:today,now:today,engine:engine)
    XCTAssertEqual(engine.key(insertion),"2026-09-30")
    XCTAssertTrue(september.contains(engine.key(insertion)))
    XCTAssertEqual(engine.key(day.insertionDate(anchor:engine.date(2026,1,1),now:today,engine:engine)),"2026-10-27")
    XCTAssertEqual(engine.key(all.insertionDate(anchor:engine.date(2026,1,1),now:today,engine:engine)),"2026-10-27")
    let bounds = september.dateBounds(engine:engine)!
    XCTAssertTrue(bounds.contains(engine.date(2026,9,30,hour:23,minute:59,second:59)))
    XCTAssertTrue(!bounds.contains(engine.date(2026,10,1)))
    XCTAssertNil(all.dateBounds(engine:engine))
    let next = NoteDateScope.day.shiftedAnchor(today,by:1,calendar:engine.calendar)!
    let nextRange = NoteDateRange(scope:.day,anchor:next,from:today,through:today,engine:engine)
    XCTAssertEqual(nextRange.start,"2026-10-28"); XCTAssertEqual(nextRange.end,"2026-10-28")
    print("Checked: note search, completion feedback, tag/date intersections, editor preservation and insertion date bounds")
}
