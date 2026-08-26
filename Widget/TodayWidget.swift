import SwiftUI
import WidgetKit

// 홈 화면 위젯 — v1.1 기능의 씨앗이자, 위젯 확장 프로세스가 실행되는지 판별하는 카나리아.
// 위젯 갤러리에 "다음교시"가 보이면 확장은 정상 실행 중이라는 뜻이다.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: TodayProvider()) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Text("다음교시")
                    .font(.headline)
                Text(entry.date, style: .time)
                    .font(.title2)
                    .monospacedDigit()
                Text("위젯 확장 정상 작동")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding()
            .widgetBackgroundCompat()
        }
        .configurationDisplayName("다음교시")
        .description("시간표 위젯 (준비 중)")
        .supportedFamilies([.systemSmall])
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { TodayEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        completion(Timeline(entries: [TodayEntry(date: Date())], policy: .never))
    }
}

extension View {
    // iOS 17+ SDK로 빌드된 홈 위젯은 containerBackground 미채택 시 에러 문구가 렌더링된다
    @ViewBuilder func widgetBackgroundCompat() -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(.background, for: .widget)
        } else {
            self
        }
    }
}
