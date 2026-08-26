import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    // ponytail: 전환 갱신은 앱 포그라운드 시점뿐 — 서버 푸시로 업그레이드 전까지의 한계
    func sync(day: DaySessions, schoolName: String, mealLine: String?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let now = Date()

        // "다음"은 항상 다음 수업 — 쉬는시간을 다음으로 안내하지 않는다
        let upcomingClass = day.sessions.first { $0.start > now && !$0.isBreak }

        let state: ClassActivityAttributes.ContentState
        if let cur = day.current(at: now) {
            state = ClassActivityAttributes.ContentState(
                label: cur.label,
                endDate: cur.end,
                nextLabel: upcomingClass.map(nextText) ?? "오늘 일과 끝",
                isBreak: cur.isBreak,
                mealLine: mealLine
            )
        } else if let first = day.sessions.first, now < first.start {
            state = ClassActivityAttributes.ContentState(
                label: "등교 전",
                endDate: first.start,
                nextLabel: nextText(first),
                isBreak: true,
                mealLine: mealLine
            )
        } else {
            // 일과 종료 또는 빈 하루
            endAll()
            return
        }

        Task {
            let content = ActivityContent(state: state, staleDate: state.endDate)
            if let activity = Activity<ClassActivityAttributes>.activities.first {
                await activity.update(content)
            } else {
                do {
                    _ = try Activity.request(
                        attributes: ClassActivityAttributes(schoolName: schoolName),
                        content: content,
                        pushType: nil
                    )
                } catch {
                    // 권한 거부/시스템 제한 시 조용히 무시
                }
            }
        }
    }

    private func nextText(_ s: DaySessions.Session) -> String {
        // "3교시 수학" → "수학" (과목에 공백이 있어도 유지)
        if s.period != nil {
            let parts = s.label.split(separator: " ").dropFirst()
            if !parts.isEmpty {
                return "다음 · " + parts.joined(separator: " ")
            }
        }
        return "다음 · " + s.label
    }

    func endAll() {
        Task {
            for activity in Activity<ClassActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
