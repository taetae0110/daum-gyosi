import Foundation

struct DaySessions: Hashable {
    struct Session: Hashable {
        var label: String     // "3교시 수학" | "쉬는시간" | "점심시간"
        var start: Date
        var end: Date
        var isBreak: Bool
        var period: Int?      // 수업이면 교시 번호, 아니면 nil
    }

    var sessions: [Session]   // 시간순, 수업/쉬는시간 교차

    func current(at now: Date) -> Session? {
        sessions.first { $0.start <= now && now < $0.end }
    }

    func next(after now: Date) -> Session? {
        sessions.first { $0.start > now }
    }
}

func makeDaySessions(entries: [TimetableEntry], bells: [BellSlot], on day: Date, calendar: Calendar) -> DaySessions {
    let dayStart = calendar.startOfDay(for: day)

    // 시간표가 종 템플릿보다 긴 학교(8교시 등)는 마지막 교시 패턴으로 종 시간을 연장한다
    var extended = bells.sorted { $0.period < $1.period }
    if let maxPeriod = entries.map(\.period).max(), let last = extended.last, maxPeriod > last.period {
        var prev = last
        for period in (last.period + 1)...maxPeriod {
            let length = max(prev.endMinute - prev.startMinute, 1)
            let slot = BellSlot(period: period,
                                startMinute: prev.endMinute + 10,
                                endMinute: prev.endMinute + 10 + length)
            extended.append(slot)
            prev = slot
        }
    }
    let bellByPeriod = Dictionary(extended.map { ($0.period, $0) }, uniquingKeysWith: { first, _ in first })

    func date(atMinute minute: Int) -> Date? {
        calendar.date(byAdding: .minute, value: minute, to: dayStart)
    }

    var classes: [DaySessions.Session] = []
    for entry in entries.sorted(by: { $0.period < $1.period }) {
        // 종 시간이 없는 교시는 표시할 수 없으므로 버린다
        guard let bell = bellByPeriod[entry.period],
              let start = date(atMinute: bell.startMinute),
              let end = date(atMinute: bell.endMinute),
              start < end else { continue }
        classes.append(DaySessions.Session(label: "\(entry.period)교시 \(entry.subject)",
                                           start: start, end: end,
                                           isBreak: false, period: entry.period))
    }

    var sessions: [DaySessions.Session] = []
    for cls in classes {
        // 이 시점의 last는 항상 직전 수업 (쉬는시간 append 직후 바로 수업을 append하므로)
        if let prev = sessions.last, prev.end < cls.start {
            let gap = cls.start.timeIntervalSince(prev.end)
            sessions.append(DaySessions.Session(label: gap > 20 * 60 ? "점심시간" : "쉬는시간",
                                                start: prev.end, end: cls.start,
                                                isBreak: true, period: nil))
        }
        sessions.append(cls)
    }
    return DaySessions(sessions: sessions)
}
