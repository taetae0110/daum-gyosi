import ActivityKit
import Foundation

struct ClassActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var label: String        // "3교시 수학" | "점심시간" | "쉬는시간"
        var endDate: Date
        var nextLabel: String    // "다음 · 영어" | "오늘 일과 끝"
        var isBreak: Bool
        var mealLine: String?    // 확장 뷰 급식 한 줄
    }
    var schoolName: String
}
