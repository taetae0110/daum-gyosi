import SwiftUI

@MainActor
struct OnboardingView: View {
    @State private var step = 0

    // 1단계: 학교 찾기
    @State private var query = ""
    @State private var kindFilter = "전체"
    @State private var results: [School] = []
    @State private var isSearching = false
    @State private var errorText: String?
    @State private var school: School?

    // 2단계: 학년·반
    @State private var grade = 1
    @State private var classNm = "1"

    // 3단계: 교시 시간
    @State private var bells: [BellSlot] = []
    @State private var lessonMinutes = 50

    var body: some View {
        switch step {
        case 0: schoolStep
        case 1: gradeStep
        default: bellStep
        }
    }

    // MARK: - 1단계

    private var schoolStep: some View {
        VStack(spacing: 12) {
            Text("학교 찾기")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("학교 종류", selection: $kindFilter) {
                ForEach(["전체", "초등학교", "중학교", "고등학교"], id: \.self) { kind in
                    Text(kind).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            HStack {
                TextField("학교 이름을 입력하세요", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { search() }
                if isSearching {
                    ProgressView()
                }
            }
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            List(results, id: \.self) { s in
                Button {
                    select(s)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.name)
                            .bold()
                            .foregroundColor(.primary)
                        Text("\(s.region) · \(s.address)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(.plain)
        }
        .padding()
    }

    private func search() {
        let name = query.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isSearching = true
        errorText = nil
        results = []
        Task {
            do {
                let kind = kindFilter == "전체" ? nil : kindFilter
                results = try await NeisClient.shared.searchSchools(name: name, kind: kind)
                if results.isEmpty {
                    errorText = "검색 결과가 없어요"
                }
            } catch {
                errorText = "검색에 실패했어요. 잠시 후 다시 시도해 주세요."
            }
            isSearching = false
        }
    }

    private func select(_ s: School) {
        school = s
        grade = 1
        classNm = "1"
        step = 1
    }

    // MARK: - 2단계

    private var gradeRange: ClosedRange<Int> {
        school?.kind == "초등학교" ? 1...6 : 1...3
    }

    private var gradeStep: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(school?.name ?? "")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("학년과 반을 선택하세요")
                    .font(.title2.bold())
            }
            HStack(spacing: 0) {
                Picker("학년", selection: $grade) {
                    ForEach(gradeRange, id: \.self) { g in
                        Text("\(g)학년").tag(g)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()
                Picker("반", selection: $classNm) {
                    ForEach(1...15, id: \.self) { n in
                        Text("\(n)반").tag(String(n))
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()
            }
            Button("다음") {
                goToBells()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func goToBells() {
        let kind = school?.kind ?? "고등학교"
        bells = BellSlot.defaultTemplate(kind: kind)
        lessonMinutes = bells.first.map { $0.endMinute - $0.startMinute } ?? 50
        step = 2
    }

    // MARK: - 3단계

    private var bellStep: some View {
        VStack(spacing: 0) {
            Text("교시 시간을 확인하세요")
                .font(.title2.bold())
                .padding()
            Form {
                Section {
                    DatePicker("1교시 시작", selection: firstStartBinding, displayedComponents: .hourAndMinute)
                    Stepper("수업 시간 \(lessonMinutes)분", value: $lessonMinutes, in: 30...60, step: 5)
                        .onChange(of: lessonMinutes) { _ in
                            rebuild()
                        }
                }
                Section("교시별 시간") {
                    ForEach(bells.indices, id: \.self) { i in
                        BellRow(slot: $bells[i])
                    }
                }
            }
            Button {
                finish()
            } label: {
                Text("시작하기")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    private var firstStartBinding: Binding<Date> {
        Binding(
            get: { minuteToDate(bells.first?.startMinute ?? 510) },
            set: { rebuild(startMinute: dateToMinute($0)) }
        )
    }

    // 시작 시각·수업 길이만으로 전체 시간표를 다시 만든다 (쉬는시간 10분, 4교시 후 점심 60분)
    private func rebuild(startMinute: Int? = nil) {
        let start = startMinute ?? bells.first?.startMinute ?? 510
        let count = school?.kind == "초등학교" ? 6 : 7
        var slots: [BellSlot] = []
        var cursor = start
        for p in 1...count {
            slots.append(BellSlot(period: p, startMinute: cursor, endMinute: cursor + lessonMinutes))
            cursor += lessonMinutes + (p == 4 ? 60 : 10)
        }
        bells = slots
    }

    private func minuteToDate(_ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
    }

    private func dateToMinute(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 8) * 60 + (c.minute ?? 30)
    }

    private func finish() {
        guard let school else { return }
        SettingsStore.shared.save(AppSettings(school: school, grade: grade, classNm: classNm, bells: bells))
    }
}

private struct BellRow: View {
    @Binding var slot: BellSlot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(slot.period)교시  \(timeLabel(slot.startMinute))–\(timeLabel(slot.endMinute))")
                .font(.body.monospacedDigit())
            HStack(spacing: 16) {
                Stepper("시작") {
                    if slot.startMinute + 5 < slot.endMinute { slot.startMinute += 5 }
                } onDecrement: {
                    if slot.startMinute >= 5 { slot.startMinute -= 5 }
                }
                Stepper("종료") {
                    if slot.endMinute + 5 <= 1435 { slot.endMinute += 5 }
                } onDecrement: {
                    if slot.endMinute - 5 > slot.startMinute { slot.endMinute -= 5 }
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func timeLabel(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}
