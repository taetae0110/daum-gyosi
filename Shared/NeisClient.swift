import Foundation

enum NeisError: Error { case api(code: String, message: String); case badResponse }

final class NeisClient {
    static let shared = NeisClient()
    private init() {}

    private static let base = "https://open.neis.go.kr/hub/"
    private static let key = (Bundle.main.object(forInfoDictionaryKey: "NEIS_KEY") as? String) ?? ""

    private static let ymdFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return f
    }()
    static func ymd(_ date: Date) -> String { ymdFormatter.string(from: date) }

    // 메뉴명 자체의 괄호("유부초밥(덕)")는 숫자·점만 매칭해 배제
    private static let allergyRegex = try! NSRegularExpression(pattern: "\\(([0-9.]+)\\)")

    private func str(_ v: Any?) -> String { (v as? String) ?? "" }

    // 성공 봉투: {엔드포인트명: [{head}, {row}]}. 실패/빈결과: 루트 {RESULT: {CODE}} (HTTP는 항상 200)
    private func call(_ endpoint: String, _ params: [String: String]) async throws -> [[String: Any]] {
        var comps = URLComponents(string: Self.base + endpoint)!
        var items = [URLQueryItem(name: "Type", value: "json"),
                     URLQueryItem(name: "pSize", value: "100")]
        if !Self.key.isEmpty { items.append(URLQueryItem(name: "KEY", value: Self.key)) }
        for (k, v) in params { items.append(URLQueryItem(name: k, value: v)) }
        comps.queryItems = items
        guard let url = comps.url else { throw NeisError.badResponse }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NeisError.badResponse
        }
        if let envelope = body[endpoint] as? [[String: Any]] {
            guard envelope.count >= 2, let rows = envelope[1]["row"] as? [[String: Any]] else {
                throw NeisError.badResponse
            }
            return rows
        }
        let result = body["RESULT"] as? [String: Any]
        let code = str(result?["CODE"])
        if code == "INFO-200" { return [] }  // 주말/미업로드/잘못된 필터 — 전부 빈 결과
        throw NeisError.api(code: code.isEmpty ? "?" : code, message: str(result?["MESSAGE"]))
    }

    func searchSchools(name: String, kind: String?) async throws -> [School] {
        var p = ["SCHUL_NM": name]
        if let kind { p["SCHUL_KND_SC_NM"] = kind }
        return try await call("schoolInfo", p).map { r in
            School(office: str(r["ATPT_OFCDC_SC_CODE"]),
                   code: str(r["SD_SCHUL_CODE"]),
                   name: str(r["SCHUL_NM"]),
                   kind: str(r["SCHUL_KND_SC_NM"]),
                   region: str(r["LCTN_SC_NM"]),
                   address: str(r["ORG_RDNMA"]))  // null 가능 → ""
        }
        // 시간표 엔드포인트가 없는 학교종류(특수학교 등)는 선택 자체를 막는다
        .filter { ["초등학교", "중학교", "고등학교"].contains($0.kind) }
    }

    func timetable(school: School, ymd: String, grade: Int, classNm: String) async throws -> [TimetableEntry] {
        let endpoint: String
        switch school.kind {
        case "초등학교": endpoint = "elsTimetable"
        case "중학교":   endpoint = "misTimetable"
        default:        endpoint = "hisTimetable"
        }
        // AY/SEM은 보내지 않는다 — 틀리면 조용히 빈 결과가 된다
        let rows = try await call(endpoint, [
            "ATPT_OFCDC_SC_CODE": school.office,
            "SD_SCHUL_CODE": school.code,
            "ALL_TI_YMD": ymd,
            "GRADE": String(grade),
            "CLASS_NM": classNm,
        ])
        return rows
            .map { TimetableEntry(period: Int(str($0["PERIO"])) ?? 0, subject: str($0["ITRT_CNTNT"])) }
            .sorted { $0.period < $1.period }
    }

    func meals(school: School, ymd: String) async throws -> [Meal] {
        let rows = try await call("mealServiceDietInfo", [
            "ATPT_OFCDC_SC_CODE": school.office,
            "SD_SCHUL_CODE": school.code,
            "MLSV_YMD": ymd,
        ])
        return rows.map { r in
            let dishes: [Dish] = str(r["DDISH_NM"]).components(separatedBy: "<br/>").compactMap { seg in
                let s = seg.trimmingCharacters(in: .whitespacesAndNewlines)
                if s.isEmpty { return nil }
                let ns = s as NSString
                let full = NSRange(location: 0, length: ns.length)
                var allergies: [Int] = []
                if let m = Self.allergyRegex.firstMatch(in: s, range: full) {
                    allergies = ns.substring(with: m.range(at: 1))
                        .split(separator: ".")
                        .compactMap { Int($0) }
                }
                let name = Self.allergyRegex
                    .stringByReplacingMatches(in: s, range: full, withTemplate: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return Dish(name: name, allergies: allergies)
            }
            return Meal(name: str(r["MMEAL_SC_NM"]), dishes: dishes, kcal: str(r["CAL_INFO"]))
        }
    }
}
