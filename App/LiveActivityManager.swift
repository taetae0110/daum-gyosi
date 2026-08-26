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

    // 진단용 테스트: 가짜 세션을 직접 요청하고, 실패 지점을 사람이 읽을 수 있게 돌려준다
    func startTest(schoolName: String, mealLine: String?) async -> String {
        var lines: [String] = []

        if let url = Bundle.main.builtInPlugInsURL,
           let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil),
           items.contains(where: { $0.pathExtension == "appex" }) {
            lines.append("위젯 확장: 있음 ✓")
        } else {
            lines.append("위젯 확장: 없음 ✗ — 설치 도구가 확장을 빼고 서명함")
        }

        lines.append(ActivityAuthorizationInfo().areActivitiesEnabled
                     ? "Live Activity 허용: ON ✓"
                     : "Live Activity 허용: OFF ✗ — 설정 > 다음교시에서 켜기")

        let now = Date()
        let state = ClassActivityAttributes.ContentState(
            label: "3교시 수학",
            endDate: now.addingTimeInterval(900),
            nextLabel: "다음 · 영어",
            isBreak: false,
            mealLine: mealLine
        )
        do {
            for activity in Activity<ClassActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            _ = try Activity.request(
                attributes: ClassActivityAttributes(schoolName: schoolName),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            lines.append("시스템 요청: 성공 ✓")
            lines.append("→ 홈 화면으로 나가면 아일랜드에 표시됩니다")
        } catch {
            lines.append("시스템 요청: 실패 ✗")
            lines.append(error.localizedDescription)
        }
        return lines.joined(separator: "\n")
    }

    func endAll() {
        Task {
            for activity in Activity<ClassActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
