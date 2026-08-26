import ActivityKit
import SwiftUI
import WidgetKit

struct ClassActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClassActivityAttributes.self) { context in
            LockScreenActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.label)
                            .font(.headline)
                            .lineLimit(1)
                        Text(context.attributes.schoolName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: timerRange(context.state.endDate), countsDown: true)
                        .font(.title2)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 64)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.nextLabel)
                            .font(.caption)
                            .lineLimit(1)
                        if let meal = context.state.mealLine {
                            Text(meal)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                Text(context.state.label)
                    .font(.caption2)
                    .lineLimit(1)
            } compactTrailing: {
                // 고정 폭: 초 단위 카운트다운의 레이아웃 점프 방지
                Text(timerInterval: timerRange(context.state.endDate), countsDown: true)
                    .font(.caption2)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: context.state.isBreak ? "cup.and.saucer.fill" : "clock.fill")
                    .foregroundColor(.accentColor)
            }
            .keylineTint(.accentColor)
        }
    }
}

// endDate가 과거여도 크래시하지 않는 유효 구간
private func timerRange(_ end: Date) -> ClosedRange<Date> {
    let now = Date.now
    return now...max(now, end)
}

private struct LockScreenActivityView: View {
    let context: ActivityViewContext<ClassActivityAttributes>

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.label)
                    .font(.headline)
                    .bold()
                    .lineLimit(1)
                Text(context.state.nextLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(timerInterval: timerRange(context.state.endDate), countsDown: true)
                .font(.title3)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 72)
        }
        .padding()
        .activityBackgroundTint(Color.black.opacity(0.4))
    }
}
