import Foundation
import CalendarCore

actor HolidayStub {
    var calls: [URLRequest] = []
    var manifest: Data
    var annual: Data
    var status = 200
    var conditional = false
    var retryAfter: String?
    init(manifest: Data, annual: Data) { self.manifest = manifest; self.annual = annual }
    func fail(_ code: Int = 503, retry: String? = nil) { status = code; retryAfter = retry }
    func recover() { status = 200 }
    func update(manifest: Data, annual: Data) { self.manifest = manifest; self.annual = annual }
    func useConditional() { conditional = true }
    func response(_ request: URLRequest) async throws -> (Data,HTTPURLResponse) {
        calls.append(request)
        try await Task.sleep(nanoseconds:20_000_000)
        let index = request.url!.lastPathComponent == "index.json"
        var code = status
        if conditional && index && request.value(forHTTPHeaderField:"If-None-Match") != nil && status == 200 { code = 304 }
        var headers = ["ETag":"test-index-v1"]
        if let retryAfter { headers["Retry-After"] = retryAfter }
        return (index ? manifest : annual,HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:nil,headerFields:headers)!)
    }
}

func holidayFixture(version: String = "2026.1", suffix: String = "") -> (index:Data,annual:Data) {
    let names = ["元旦","春节","清明节","劳动节","端午节","中秋节","国庆节"]
    let days = names.enumerated().map { i,name in
        ["date":String(format:"2026-%02d-01",i+1),"name":name+suffix,"isOffDay":true] as [String:Any]
    }
    let source = ["title":"测试公告","url":"https://www.gov.cn/notice","documentNumber":"测试号","publishedAt":"2025-11-04"]
    let annual = try! JSONSerialization.data(withJSONObject:["schemaVersion":1,"year":2026,"version":version,"status":"published","timeZone":"Asia/Shanghai","updatedAt":"2026-10-23","sources":[source],"days":days])
    let index = try! JSONSerialization.data(withJSONObject:["schemaVersion":1,"region":"CN","timeZone":"Asia/Shanghai","updatedAt":"2026-10-23","years":["2026":["version":version,"path":"years/2026.json","sha256":HolidayRepository.sha256(annual)]]])
    return (index,annual)
}

func checkHolidayRepository() async {
    let engine = CalendarEngine(), fixture = holidayFixture()
    let now = engine.date(2026,10,23)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("calendar-check-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at:root) }
    let stub = HolidayStub(manifest:fixture.index,annual:fixture.annual)
    let repository = HolidayRepository(directory:root,transport:{ try await stub.response($0) })
    async let first = repository.load(year:2026,now:now)
    async let second = repository.load(year:2026,now:now)
    async let missing = repository.load(year:2027,now:now)
    let (a,b,c) = await (first,second,missing)
    XCTAssertTrue(a.complete && b.complete && !c.complete)
    XCTAssertEqual(a.entries.count,7)
    XCTAssertEqual(a.version,"2026.1")
    XCTAssertEqual(a.nextCheck.timeIntervalSince(now),7 * 86400)
    XCTAssertEqual(await stub.calls.count,2) // shared index + one annual file, no missing-year request
    _ = await repository.load(year:2026,now:now.addingTimeInterval(10),force:true)
    XCTAssertEqual(await stub.calls.count,2)
    let reopened = HolidayRepository(directory:root,transport:{ try await stub.response($0) })
    _ = await reopened.load(year:2027,now:now.addingTimeInterval(86400))
    _ = await reopened.load(year:2026,now:now.addingTimeInterval(86400))
    _ = await reopened.load(year:2028,now:now)
    XCTAssertEqual(await stub.calls.count,2) // persisted positive + negative cache, far future skipped
    await stub.useConditional()
    let unchanged = await reopened.load(year:2026,now:now.addingTimeInterval(8 * 86400))
    XCTAssertEqual(unchanged.entries,a.entries)
    XCTAssertEqual(await stub.calls.count,3) // index 304, no annual download
    let calls = await stub.calls
    XCTAssertEqual(calls.last?.value(forHTTPHeaderField:"If-None-Match"),"test-index-v1")

    let changed = holidayFixture(version:"2026.2",suffix:"修订")
    // A fresh transport instance lets the changed index respond 200 instead of the fixture's 304.
    let update = HolidayStub(manifest:changed.index,annual:changed.annual)
    let updater = HolidayRepository(directory:root,transport:{ try await update.response($0) })
    let revision = await updater.load(year:2026,now:now.addingTimeInterval(16 * 86400))
    XCTAssertEqual(revision.version,"2026.2")
    XCTAssertTrue(revision.entries["2026-01-01"]?.name.contains("修订") == true)
    XCTAssertEqual(await update.calls.count,2)
    await update.fail()
    let stale = await updater.load(year:2026,now:now.addingTimeInterval(24 * 86400))
    XCTAssertEqual(stale.entries,revision.entries)
    XCTAssertEqual(stale.nextCheck.timeIntervalSince(stale.checkedAt),3600)
    let again = HolidayRepository(directory:root,transport:{ try await update.response($0) })
    _ = await again.load(year:2027,now:stale.checkedAt.addingTimeInterval(100))
    XCTAssertEqual(await update.calls.count,3) // global index error cooldown survives relaunch and year switch
    let twice = await updater.load(year:2026,now:stale.nextCheck.addingTimeInterval(1))
    XCTAssertEqual(twice.nextCheck.timeIntervalSince(twice.checkedAt),21600)
    let third = await updater.load(year:2026,now:twice.nextCheck.addingTimeInterval(1))
    XCTAssertEqual(third.nextCheck.timeIntervalSince(third.checkedAt),86400)
    let outside = await updater.load(year:1901,now:engine.date(1901,1,1))
    XCTAssertTrue(!outside.complete)

    let integrityRoot = root.appendingPathComponent("integrity")
    let corrupt = HolidayStub(manifest:fixture.index,annual:changed.annual)
    let integrity = HolidayRepository(directory:integrityRoot,transport:{ try await corrupt.response($0) })
    let rejected = await integrity.load(year:2026,now:now)
    XCTAssertTrue(!rejected.complete && rejected.entries.isEmpty) // SHA mismatch never saved as valid
    await corrupt.fail(429,retry:"7200")
    let throttled = await integrity.load(year:2026,now:now.addingTimeInterval(8 * 86400))
    XCTAssertEqual(throttled.nextCheck.timeIntervalSince(throttled.checkedAt),21600) // second failure's backoff exceeds Retry-After
    let emptyRoot = root.appendingPathComponent("rate-limit")
    let rateLimit = HolidayRepository(directory:emptyRoot,transport:{ try await corrupt.response($0) })
    let rate = await rateLimit.load(year:2026,now:now)
    XCTAssertEqual(rate.nextCheck.timeIntervalSince(rate.checkedAt),7200)

    var bad = try! JSONSerialization.jsonObject(with:fixture.annual) as! [String:Any]
    var days = bad["days"] as! [[String:Any]]
    days[0]["date"] = "2026-02-31"; bad["days"] = days
    let invalid = try! JSONSerialization.data(withJSONObject:bad)
    XCTAssertTrue((try? HolidayRepository.decode(invalid,year:2026,version:"2026.1")) == nil)
    XCTAssertTrue((try? HolidayRepository.decode(fixture.annual,year:2027,version:"2027.1")) == nil)
    bad["days"] = []; bad["status"] = "draft"
    XCTAssertTrue((try? HolidayRepository.decode(try! JSONSerialization.data(withJSONObject:bad),year:2026,version:"2026.1")) == nil)
    for mutation in ["path", "schemaVersion"] {
        var manifest = try! JSONSerialization.jsonObject(with:fixture.index) as! [String:Any]
        if mutation == "path" {
            var years = manifest["years"] as! [String:[String:Any]]
            years["2026"]!["path"] = "https://elsewhere.example/2026.json"
            manifest["years"] = years
        } else { manifest["schemaVersion"] = 99 }
        let invalidManifest = try! JSONSerialization.data(withJSONObject:manifest)
        let malformed = HolidayStub(manifest:invalidManifest,annual:fixture.annual)
        let validator = HolidayRepository(directory:root.appendingPathComponent(mutation),transport:{ try await malformed.response($0) })
        let refused = await validator.load(year:2026,now:now)
        XCTAssertTrue(!refused.complete)
        XCTAssertEqual(await malformed.calls.count,1)
    }
    let legacyRoot = root.appendingPathComponent("legacy")
    try! FileManager.default.createDirectory(at:legacyRoot,withIntermediateDirectories:true)
    var legacy = try! JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("2026.json"))) as! [String:Any]
    legacy["provider"] = "Timor"
    for key in ["sourceID", "version", "checksum"] { legacy.removeValue(forKey:key) }
    legacy["nextCheck"] = Date.distantFuture.timeIntervalSinceReferenceDate
    try! JSONSerialization.data(withJSONObject:legacy).write(to:legacyRoot.appendingPathComponent("2026.json"))
    let migrateStub = HolidayStub(manifest:fixture.index,annual:fixture.annual)
    let migrating = HolidayRepository(directory:legacyRoot,transport:{ try await migrateStub.response($0) })
    let migrated = await migrating.load(year:2026,now:now)
    XCTAssertEqual(migrated.provider,HolidayRepository.provider)
    XCTAssertEqual(migrated.version,"2026.1")
    XCTAssertEqual(await migrateStub.calls.count,2)
    print("Checked: shared GitHub index, durable cache, ETag 304, version upgrades, integrity, retries and unpublished years")
}

func checkBelowPlacement() {
    for screen in [CGRect(x:0,y:0,width:800,height:800),CGRect(x:-820,y:100,width:820,height:650)] {
        let placement = WorkspacePlacement(anchor:CGRect(x:screen.maxX-80,y:screen.maxY+4,width:60,height:24),visibleFrame:screen,calendarHeight:690,settings:true)
        XCTAssertEqual(placement.dock,.below)
        XCTAssertTrue(screen.contains(placement.frame))
        XCTAssertEqual(placement.calendarHeight+placement.settingsHeight+1,placement.frame.height)
        XCTAssertTrue(placement.settingsHeight >= 250)
        XCTAssertTrue(placement.settingsWidth >= 420)
    }
    let screen = CGRect(x:0,y:0,width:1440,height:875)
    let middle = WorkspacePlacement(anchor:CGRect(x:700,y:880,width:60,height:24),visibleFrame:screen,calendarHeight:690,settings:true)
    XCTAssertEqual(middle.dock,.right)
    print("Checked: narrow-screen below layout and larger-side placement")
}
