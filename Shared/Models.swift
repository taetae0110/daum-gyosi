import Foundation

struct School: Codable, Hashable {
    var office: String   // ATPT_OFCDC_SC_CODE
    var code: String     // SD_SCHUL_CODE
    var name: String
    var kind: String     // "초등학교" | "중학교" | "고등학교"
    var region: String   // LCTN_SC_NM
    var address: String  // ORG_RDNMA
}

struct TimetableEntry: Codable, Hashable { var period: Int; var subject: String }

struct Dish: Codable, Hashable { var name: String; var allergies: [Int] }

struct Meal: Codable, Hashable { var name: String; var dishes: [Dish]; var kcal: String }

struct BellSlot: Codable, Hashable, Identifiable {
    var period: Int
    var startMinute: Int  // 자정 기준 분 (08:30 = 510)
    var endMinute: Int
    var id: Int { period }
}

struct AppSettings: Codable {
    var school: School
    var grade: Int
    var classNm: String
    var bells: [BellSlot]
}

extension BellSlot {
    // 고등학교: 08:30 시작, 50분 수업, 10분 쉬는시간, 4교시 후 점심 60분, 7교시까지
    // 중학교:   08:40 시작, 45분 수업, 10분 쉬는시간, 4교시 후 점심 60분, 7교시까지
    // 초등학교: 08:40 시작, 40분 수업, 10분 쉬는시간, 4교시 후 점심 60분, 6교시까지
    static func defaultTemplate(kind: String) -> [BellSlot] {
        let start: Int, lesson: Int, count: Int
        switch kind {
        case "초등학교": start = 8 * 60 + 40; lesson = 40; count = 6
        case "중학교":   start = 8 * 60 + 40; lesson = 45; count = 7
        default:        start = 8 * 60 + 30; lesson = 50; count = 7  // 고등학교
        }
        var slots: [BellSlot] = []
        var t = start
        for p in 1...count {
            slots.append(BellSlot(period: p, startMinute: t, endMinute: t + lesson))
            t += lesson + (p == 4 ? 60 : 10)
        }
        return slots
    }
}
