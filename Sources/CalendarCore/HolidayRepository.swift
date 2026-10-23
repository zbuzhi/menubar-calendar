import Foundation
import CryptoKit

public struct HolidayYearRecord: Codable {
    public var year: Int
    public var entries: [String:Holiday] = [:]
    public var complete = false
    public var provider = ""
    public var sourceID: String?
    public var version: String?
    public var checksum: String?
    public var checkedAt: Date = .distantPast
    public var nextCheck: Date = .distantPast
    public var failures = 0
    public var outcome = "尚未检查"
    public var summary: String {
        let f = DateFormatter(); f.dateFormat = "M月d日"; f.timeZone = TimeZone(identifier:"Asia/Shanghai")
        let local = !entries.isEmpty && outcome == "暂时无法更新" ? " · 使用本地缓存" : ""
        let detail = complete ? " · \(version ?? provider)" : ""
        return "\(year)年 · \(outcome)\(detail)\(local) · \(f.string(from:nextCheck))再检查"
    }
}

public struct HolidayManifest: Codable {
    public struct Entry: Codable {
        public let version: String
        public let path: String
        public let sha256: String
    }
    public let schemaVersion: Int
    public let region: String
    public let timeZone: String
    public let updatedAt: String
    public let years: [String:Entry]
}
private struct HolidayIndexCache: Codable {
    var manifest: HolidayManifest?
    var checkedAt: Date = .distantPast
    var nextCheck: Date = .distantPast
    var failures = 0
    var etag: String?
    var lastModified: String?
}
private struct HolidayHTTPError: Error { var retryAfter: TimeInterval }

/// A shared small index, conditional HTTP, versioned annual files and durable offline cache.
public actor HolidayRepository {
    public static let sourceURL = URL(string:"https://github.com/zbuzhi/calendar-holidays")!
    public static let baseURL = URL(string:"https://raw.githubusercontent.com/zbuzhi/calendar-holidays/main/")!
    public static let provider = "自维护 GitHub 仓库"
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data,HTTPURLResponse)
    private let directory: URL
    private let transport: Transport
    private var records: [Int:HolidayYearRecord] = [:]
    private var inFlight: [Int:Task<HolidayYearRecord,Never>] = [:]
    private var indexCache: HolidayIndexCache?
    private var indexTask: Task<HolidayIndexCache,Error>?

    public init(directory: URL? = nil, transport: Transport? = nil) {
        self.directory = directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("com.perpetualcalendar.mac/holidays",isDirectory:true)
        if let transport { self.transport = transport } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 16
            config.httpCookieStorage = nil; config.urlCredentialStorage = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            let session = URLSession(configuration:config)
            self.transport = { request in
                let (data,response) = try await session.data(for:request)
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                return (data,http)
            }
        }
    }
    private func save<T:Encodable>(_ value: T, name: String) throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        try JSONEncoder().encode(value).write(to:directory.appendingPathComponent(name),options:.atomic)
    }
    private func read(_ year: Int) -> HolidayYearRecord {
        if let record = records[year] { return record }
        let url = directory.appendingPathComponent("\(year).json")
        if let data = try? Data(contentsOf:url), data.count <= 512_000,
           var record = try? JSONDecoder().decode(HolidayYearRecord.self,from:data), record.year == year {
            // Retain legacy data offline, but check the new source on its first use.
            if record.sourceID != Self.sourceURL.absoluteString { record.nextCheck = .distantPast; record.version = nil; record.checksum = nil }
            records[year] = record; return record
        }
        return HolidayYearRecord(year:year)
    }
    public func cachedRecords() -> [HolidayYearRecord] {
        let files = (try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)) ?? []
        for file in files where file.pathExtension == "json" {
            if let year = Int(file.deletingPathExtension().lastPathComponent), (2007...2100).contains(year) { _ = read(year) }
        }
        return Array(records.values)
    }
    public func load(year: Int, now: Date = Date(), force: Bool = false) async -> HolidayYearRecord {
        if let pending = inFlight[year] { return await pending.value }
        var old = read(year)
        let currentYear = CalendarEngine().calendar.component(.year,from:now)
        guard year >= 2007 && year <= currentYear + 1 else {
            old.outcome = "尚未到发布年份或超出数据范围"; return old
        }
        if now < old.nextCheck && (!force || now.timeIntervalSince(old.checkedAt) < 60) { return old }
        let task = Task { await self.fetch(old:old,now:now,force:force) }
        inFlight[year] = task
        var record = await task.value
        records[year] = record
        do { try save(record,name:"\(year).json") }
        catch { record.outcome += "（缓存写入失败）"; records[year] = record }
        inFlight[year] = nil
        return record
    }
    private func readIndex() -> HolidayIndexCache {
        if let indexCache { return indexCache }
        if let data = try? Data(contentsOf:directory.appendingPathComponent("index-v1.json")), data.count <= 256_000,
           let value = try? JSONDecoder().decode(HolidayIndexCache.self,from:data) {
            // Validate disk cache with the same constraints as network input.
            if let manifest = value.manifest, (try? Self.validate(manifest)) == nil { return HolidayIndexCache() }
            indexCache = value; return value
        }
        return HolidayIndexCache()
    }
    private func loadIndex(now: Date, force: Bool) async throws -> HolidayIndexCache {
        if let indexTask { return try await indexTask.value }
        let old = readIndex()
        if now < old.nextCheck && (!force || now.timeIntervalSince(old.checkedAt) < 60) {
            // A stale index is useful for cached dates but must not label a new year unpublished.
            guard old.failures == 0, old.manifest != nil else { throw HolidayHTTPError(retryAfter:old.nextCheck.timeIntervalSince(now)) }
            return old
        }
        let transport = self.transport
        let task = Task<HolidayIndexCache,Error> {
            var request = Self.request("index.json")
            if let tag = old.etag { request.setValue(tag,forHTTPHeaderField:"If-None-Match") }
            if let modified = old.lastModified { request.setValue(modified,forHTTPHeaderField:"If-Modified-Since") }
            let (data,response) = try await transport(request)
            var fresh = old
            if response.statusCode == 304 {
                guard old.manifest != nil else { throw URLError(.cannotParseResponse) }
            } else {
                try Self.check(response,data:data,limit:128_000,now:now)
                let manifest = try JSONDecoder().decode(HolidayManifest.self,from:data)
                try Self.validate(manifest)
                fresh.manifest = manifest
                fresh.etag = response.value(forHTTPHeaderField:"ETag")
                fresh.lastModified = response.value(forHTTPHeaderField:"Last-Modified")
            }
            fresh.checkedAt = now; fresh.nextCheck = now.addingTimeInterval(7 * 86400); fresh.failures = 0
            return fresh
        }
        indexTask = task
        do {
            let fresh = try await task.value
            indexCache = fresh; indexTask = nil
            try? save(fresh,name:"index-v1.json")
            return fresh
        } catch {
            var failed = old
            failed.checkedAt = now; failed.failures = min(100,old.failures + 1)
            failed.nextCheck = now.addingTimeInterval(Self.backoff(failed.failures,error:error))
            indexCache = failed; indexTask = nil
            try? save(failed,name:"index-v1.json")
            throw error
        }
    }
    private func fetch(old: HolidayYearRecord, now: Date, force: Bool) async -> HolidayYearRecord {
        var result = old
        result.checkedAt = now
        result.sourceID = Self.sourceURL.absoluteString
        do {
            let cache = try await loadIndex(now:now,force:force)
            guard let entry = cache.manifest?.years[String(old.year)] else {
                result.outcome = "仓库尚未发布该年安排"; result.failures = 0
                result.nextCheck = cache.nextCheck
                return result // Preserve any previously cached data if an entry was withdrawn.
            }
            if old.complete, old.provider == Self.provider, old.version == entry.version, old.checksum == entry.sha256 {
                result.outcome = "已是最新"; result.failures = 0; result.nextCheck = cache.nextCheck
                return result
            }
            // A content hash in the URL avoids a cached older file racing the newer index.
            var components = URLComponents(url:Self.baseURL.appendingPathComponent(entry.path),resolvingAgainstBaseURL:false)!
            components.queryItems = [URLQueryItem(name:"sha256",value:entry.sha256)]
            var request = URLRequest(url:components.url!); request.timeoutInterval = 12
            request.setValue("application/json",forHTTPHeaderField:"Accept")
            let (data,response) = try await transport(request)
            try Self.check(response,data:data,limit:512_000,now:now)
            guard Self.sha256(data) == entry.sha256 else { throw URLError(.cannotDecodeContentData) }
            let entries = try Self.decode(data,year:old.year,version:entry.version)
            result.entries = entries; result.complete = true; result.provider = Self.provider
            result.version = entry.version; result.checksum = entry.sha256
            result.failures = 0; result.outcome = "已更新"; result.nextCheck = cache.nextCheck
        } catch {
            result.failures = min(100,old.failures + 1); result.outcome = "暂时无法更新"
            result.nextCheck = now.addingTimeInterval(Self.backoff(result.failures,error:error))
        }
        return result
    }
    private static func request(_ path: String) -> URLRequest {
        var r = URLRequest(url:baseURL.appendingPathComponent(path)); r.timeoutInterval = 12
        r.setValue("application/json",forHTTPHeaderField:"Accept")
        return r
    }
    private static func backoff(_ failures: Int, error: Error) -> TimeInterval {
        let delay: [TimeInterval] = [3600,21600,86400]
        return max(delay[min(max(0,failures - 1),2)],(error as? HolidayHTTPError)?.retryAfter ?? 0)
    }
    private static func check(_ response: HTTPURLResponse, data: Data, limit: Int, now: Date) throws {
        guard response.statusCode == 200 else {
            var retry: TimeInterval = 0
            if [429,503].contains(response.statusCode), let value = response.value(forHTTPHeaderField:"Retry-After") {
                if let seconds = Double(value), seconds.isFinite { retry = min(30 * 86400,max(0,seconds)) }
                else {
                    let f = DateFormatter(); f.locale = Locale(identifier:"en_US_POSIX"); f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                    if let date = f.date(from:value) { retry = min(30 * 86400,max(0,date.timeIntervalSince(now))) }
                }
            }
            throw HolidayHTTPError(retryAfter:retry)
        }
        guard data.count <= limit else { throw URLError(.dataLengthExceedsMaximum) }
    }
    public static func sha256(_ data: Data) -> String { SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() }
    private static func validDate(_ value: String) -> Bool {
        let parts = value.split(separator:"-").compactMap { Int($0) }
        guard value.count == 10, parts.count == 3, (1900...2100).contains(parts[0]), (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return false }
        let engine = CalendarEngine()
        return engine.key(engine.date(parts[0],parts[1],parts[2])) == value
    }
    private static func validVersion(_ version: String, year: Int) -> Bool {
        version.range(of:"^\(year)\\.[1-9][0-9]{0,8}$",options:.regularExpression) != nil
    }
    private static func validate(_ manifest: HolidayManifest) throws {
        guard manifest.schemaVersion == 1, manifest.region == "CN", manifest.timeZone == "Asia/Shanghai",
              validDate(manifest.updatedAt), manifest.years.count <= 94 else { throw URLError(.cannotParseResponse) }
        for (key,entry) in manifest.years {
            guard let year = Int(key), String(year) == key, (2007...2100).contains(year),
                  validVersion(entry.version,year:year), entry.path == "years/\(year).json",
                  entry.sha256.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil else { throw URLError(.cannotParseResponse) }
        }
    }
    public static func isComplete(_ entries: [String:Holiday]) -> Bool {
        let names = entries.values.filter { $0.status == .rest }.map(\.name).joined(separator:" ")
        return ["元旦","春节","清明","劳动","端午","中秋","国庆"].allSatisfy { names.contains($0) }
    }
    public static func decode(_ data: Data, year: Int, version: String) throws -> [String:Holiday] {
        struct Dataset: Decodable {
            var schemaVersion: Int; var year: Int; var version: String; var status: String
            var timeZone: String; var updatedAt: String; var sources: [Source]; var days: [Item]
            struct Source: Decodable { var title: String; var url: String; var documentNumber: String; var publishedAt: String }
            struct Item: Decodable { var date: String; var name: String; var isOffDay: Bool }
        }
        let parsed = try JSONDecoder().decode(Dataset.self,from:data)
        guard parsed.schemaVersion == 1, parsed.year == year, parsed.version == version, validVersion(version,year:year),
              parsed.status == "published", parsed.timeZone == "Asia/Shanghai", validDate(parsed.updatedAt),
              !parsed.sources.isEmpty, parsed.days.count <= 400 else { throw URLError(.cannotParseResponse) }
        for source in parsed.sources {
            guard let url = URLComponents(string:source.url), url.scheme == "https", url.host?.hasSuffix(".gov.cn") == true,
                  url.user == nil, url.password == nil, !source.title.isEmpty, !source.documentNumber.isEmpty,
                  validDate(source.publishedAt) else { throw URLError(.cannotParseResponse) }
        }
        var result: [String:Holiday] = [:]
        for item in parsed.days {
            guard validDate(item.date), item.date.hasPrefix("\(year)-") || item.date.hasPrefix("\(year-1)-12-"),
                  !item.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, item.name.count <= 60,
                  result[item.date] == nil else { throw URLError(.cannotParseResponse) }
            result[item.date] = Holiday(name:item.name,status:item.isOffDay ? .rest : .work)
        }
        guard isComplete(result) else { throw URLError(.cannotParseResponse) }
        return result
    }
}
