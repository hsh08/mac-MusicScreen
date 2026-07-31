import SwiftUI

struct ClockView: View {
    let showsTime: Bool
    let showsDate: Bool
    let compact: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: compact ? 2 : 5) {
                if showsTime {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: compact ? 34 : 54, weight: .medium, design: .rounded))
                        .monospacedDigit()
                }

                if showsDate {
                    Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.system(size: compact ? 13 : 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }
}
