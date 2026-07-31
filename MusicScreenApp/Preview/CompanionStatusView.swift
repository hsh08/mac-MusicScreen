import SwiftUI

struct CompanionStatusView: View {
    @ObservedObject var status: CompanionStatusModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            statusRow(
                "Apple Music",
                value: status.isAppleMusicConnected ? "Connected" : "Not connected",
                isGood: status.isAppleMusicConnected
            )
            statusRow(
                "Last track refresh",
                value: status.lastTrackRefreshAt?.formatted(date: .omitted, time: .standard) ?? "Never",
                isGood: status.lastTrackRefreshAt != nil
            )
            statusRow(
                "Shared cache",
                value: cacheStatusText,
                isGood: status.cacheWriteSucceeded == true
            )
            statusRow(
                "Screen saver data",
                value: status.isScreenSaverDataReady ? "Ready" : "Not ready",
                isGood: status.isScreenSaverDataReady
            )
        }
        .font(.system(size: 12, weight: .medium))
        .padding(12)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }

    private var cacheStatusText: String {
        if status.cacheWriteSucceeded == true { return "Saved" }
        if status.cacheWriteSucceeded == false { return "Failed" }
        return "Waiting"
    }

    private func statusRow(_ label: String, value: String, isGood: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isGood ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(label)
                .foregroundStyle(.white.opacity(0.68))
            Spacer(minLength: 14)
            Text(value)
                .foregroundStyle(.white)
        }
    }
}
