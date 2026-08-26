import SwiftUI

struct TodayView: View {
    @ObservedObject private var store = SettingsStore.shared
    @Environment(\.scenePhase) private var scenePhase

    private enum LoadState {
        case loading
        case loaded(day: DaySessions, entries: [TimetableEntry], sourceYmd: String, meals: [Meal])
        case empty
    }

    @State private var state: LoadState = .loading
    @State private var showSettingsDialog = false
    @State private var tomorrowExpanded = false
    @State private var tomorrowLoading = false
    @State private var tomorrowEntries: [TimetableEntry]?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 EEEE"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        if let settings = store.settings {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(Self.dateFormatter.string(from: Date()))
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        switch state {
                        case .loading:
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                        case .empty:
                            emptyCard
                        case .loaded(let day, _, let sourceYmd, let meals):
                            timetableCard(day: day, sourceYmd: sourceYmd)
                            mealCard(meals: meals)
                            tomorrowSection(settings: settings)
                        }
                    }
                    .padding()
                }
                .refreshable { await load(settings: settings) }
                .navigationTitle(settings.school.name)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showSettingsDialog = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
                .confirmationDialog("설정", isPresented: $showSettingsDialog, titleVisibility: .visible) {
                    Button("아일랜드 테스트 (15분)") {
                        startIslandTest(settings: settings)
                    }
                    Button("학교 다시 설정", role: .destructive) {
                        LiveActivityManager.shared.endAll()  // 이전 학교의 아일랜드가 남지 않게
                        store.reset()
                    }
                    Button("취소", role: .cancel) {}
                } message: {
                    Text("학교·학년·반과 교시 시간을 처음부터 다시 설정합니다.")
                }
            }
            .task { await load(settings: settings) }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    Task { await load(settings: settings) }
                }
            }
        } else {
            EmptyView()
        }
    }

    // MARK: - 시간표 카드

    private func timetableCard(day: DaySessions, sourceYmd: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if sourceYmd != NeisClient.ymd(Date()) {
                Label(pastLabel(sourceYmd), systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let current = day.current(at: context.date)
                VStack(spacing: 4) {
                    ForEach(day.sessions.filter { !$0.isBreak }, id: \.self) { session in
                        sessionRow(session, now: context.date, isCurrent: session == current)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func sessionRow(_ session: DaySessions.Session, now: Date, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            Text("\(session.period ?? 0)")
                .font(.headline)
                .frame(width: 32, height: 32)
                .background(Circle().fill(isCurrent ? Color.accentColor : Color(uiColor: .systemGray4)))
                .foregroundColor(isCurrent ? .white : .primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(subjectText(session))
                    .font(isCurrent ? .headline : .body)
                Text("\(Self.timeFormatter.string(from: session.start))–\(Self.timeFormatter.string(from: session.end))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isCurrent, now < session.end {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("남은 시간")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(timerInterval: now...session.end, countsDown: true)
                        .font(.headline.monospacedDigit())
                        .foregroundColor(.accentColor)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isCurrent ? Color.accentColor.opacity(0.15) : Color.clear)
        )
    }

    private func subjectText(_ session: DaySessions.Session) -> String {
        guard let period = session.period else { return session.label }
        let prefix = "\(period)교시 "
        return session.label.hasPrefix(prefix) ? String(session.label.dropFirst(prefix.count)) : session.label
    }

    private func pastLabel(_ ymd: String) -> String {
        guard ymd.count == 8,
              let month = Int(ymd.dropFirst(4).prefix(2)),
              let dayNum = Int(ymd.suffix(2)) else { return "지난 시간표" }
        return "지난 시간표 (\(month)/\(dayNum))"
    }

    // MARK: - 급식 카드

    @ViewBuilder
    private func mealCard(meals: [Meal]) -> some View {
        if let lunch = meals.first(where: { $0.name == "중식" }) ?? meals.first {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("급식", systemImage: "fork.knife")
                        .font(.headline)
                    Spacer()
                    Text(lunch.kcal)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                ForEach(lunch.dishes, id: \.self) { dish in
                    dishText(dish)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
        }
    }

    private func dishText(_ dish: Dish) -> Text {
        var text = Text(dish.name).font(.subheadline)
        if !dish.allergies.isEmpty {
            text = text + Text(" " + dish.allergies.map(String.init).joined(separator: "."))
                .font(.caption2)
                .foregroundColor(.gray)
        }
        return text
    }

    // MARK: - 내일 시간표

    private func tomorrowSection(settings: AppSettings) -> some View {
        DisclosureGroup(isExpanded: $tomorrowExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                if tomorrowLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else if let entries = tomorrowEntries, !entries.isEmpty {
                    let bellByPeriod = Dictionary(settings.bells.map { ($0.period, $0) },
                                                  uniquingKeysWith: { first, _ in first })
                    ForEach(entries.sorted(by: { $0.period < $1.period }), id: \.self) { entry in
                        HStack(spacing: 10) {
                            Text("\(entry.period)")
                                .font(.subheadline)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(Color(uiColor: .systemGray5)))
                            Text(entry.subject)
                                .font(.subheadline)
                            Spacer()
                            if let bell = bellByPeriod[entry.period] {
                                Text("\(minuteText(bell.startMinute))–\(minuteText(bell.endMinute))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else if tomorrowEntries != nil {
                    Text("내일 시간표가 아직 없어요")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                }
            }
            .padding(.top, 8)
        } label: {
            Text("내일 시간표")
                .font(.headline)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
        .onChange(of: tomorrowExpanded) { expanded in
            if expanded, tomorrowEntries == nil, !tomorrowLoading {
                Task { await loadTomorrow(settings: settings) }
            }
        }
    }

    private func minuteText(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    // MARK: - 빈 상태

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("오늘 시간표가 없어요")
                .font(.headline)
            // INFO-200은 주말/미업로드/필터오류를 구분 못 하므로 단정적 문구 금지
            Text("주말이거나 아직 나이스에 올라오지 않았을 수 있어요.\n아래로 당겨 새로고침해 보세요.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - 데이터 로드

    @MainActor
    private func load(settings: AppSettings) async {
        let now = Date()
        let todayYmd = NeisClient.ymd(now)
        var entries: [TimetableEntry] = []
        var sourceYmd = todayYmd

        // 자정을 넘긴 재로드에서 어제 받아둔 "내일"이 남지 않게 무효화
        tomorrowEntries = nil
        if tomorrowExpanded { Task { await loadTomorrow(settings: settings) } }

        if let fetched = try? await NeisClient.shared.timetable(school: settings.school, ymd: todayYmd,
                                                                grade: settings.grade, classNm: settings.classNm) {
            if !fetched.isEmpty { cacheWrite(fetched, key: ttKey(settings, todayYmd)) }  // 일시적 INFO-200이 좋은 캐시를 덮지 않게
            entries = fetched
        }
        if entries.isEmpty {
            // 0 = 오늘 캐시(오프라인 대비), 1...7 = 지난 날짜 폴백
            for back in 0...7 {
                guard let date = Calendar.current.date(byAdding: .day, value: -back, to: now) else { continue }
                let ymd = NeisClient.ymd(date)
                if let cached = cacheRead([TimetableEntry].self, key: ttKey(settings, ymd)), !cached.isEmpty {
                    entries = cached
                    sourceYmd = ymd
                    break
                }
            }
        }

        var meals: [Meal] = []
        if let fetched = try? await NeisClient.shared.meals(school: settings.school, ymd: todayYmd) {
            if !fetched.isEmpty { cacheWrite(fetched, key: mealKey(settings, todayYmd)) }
            meals = fetched
        }
        if meals.isEmpty, let cached = cacheRead([Meal].self, key: mealKey(settings, todayYmd)) {
            meals = cached
        }

        if entries.isEmpty {
            state = .empty
            LiveActivityManager.shared.sync(day: DaySessions(sessions: []),
                                            schoolName: settings.school.name,
                                            mealLine: mealLine(from: meals))
        } else {
            // 폴백 시간표라도 종 시간은 항상 오늘 기준
            let day = makeDaySessions(entries: entries, bells: settings.bells, on: now, calendar: .current)
            state = .loaded(day: day, entries: entries, sourceYmd: sourceYmd, meals: meals)
            LiveActivityManager.shared.sync(day: day,
                                            schoolName: settings.school.name,
                                            mealLine: mealLine(from: meals))
        }
    }

    @MainActor
    private func loadTomorrow(settings: AppSettings) async {
        tomorrowLoading = true
        defer { tomorrowLoading = false }
        guard let date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) else {
            tomorrowEntries = []
            return
        }
        let ymd = NeisClient.ymd(date)
        if let cached = cacheRead([TimetableEntry].self, key: ttKey(settings, ymd)), !cached.isEmpty {
            tomorrowEntries = cached
            return
        }
        if let fetched = try? await NeisClient.shared.timetable(school: settings.school, ymd: ymd,
                                                                grade: settings.grade, classNm: settings.classNm) {
            cacheWrite(fetched, key: ttKey(settings, ymd))
            tomorrowEntries = fetched
        } else {
            tomorrowEntries = []
        }
    }

    // 심야·주말에도 다이나믹 아일랜드를 확인할 수 있는 가짜 세션.
    // 앱을 다시 열면 실제 시간표 기준 sync가 돌면서 자동 정리된다.
    private func startIslandTest(settings: AppSettings) {
        let now = Date()
        let day = DaySessions(sessions: [
            DaySessions.Session(label: "3교시 수학", start: now.addingTimeInterval(-300),
                                end: now.addingTimeInterval(900), isBreak: false, period: 3),
            DaySessions.Session(label: "쉬는시간", start: now.addingTimeInterval(900),
                                end: now.addingTimeInterval(1500), isBreak: true, period: nil),
            DaySessions.Session(label: "4교시 영어", start: now.addingTimeInterval(1500),
                                end: now.addingTimeInterval(4500), isBreak: false, period: 4),
        ])
        LiveActivityManager.shared.sync(day: day, schoolName: settings.school.name,
                                        mealLine: "쌀밥 · 불고기 · 배추김치")
    }

    private func mealLine(from meals: [Meal]) -> String? {
        guard let lunch = meals.first(where: { $0.name == "중식" }) ?? meals.first,
              !lunch.dishes.isEmpty else { return nil }
        return lunch.dishes.map(\.name).joined(separator: " · ")
    }

    // MARK: - UserDefaults JSON 캐시

    private func ttKey(_ s: AppSettings, _ ymd: String) -> String {
        "tt.\(s.school.office).\(s.school.code).\(s.grade).\(s.classNm).\(ymd)"
    }

    private func mealKey(_ s: AppSettings, _ ymd: String) -> String {
        "meal.\(s.school.office).\(s.school.code).\(ymd)"
    }

    private func cacheWrite<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func cacheRead<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
