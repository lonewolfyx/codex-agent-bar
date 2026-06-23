import SwiftUI

struct QuotaPopoverView: View {
    @ObservedObject var store: QuotaStore
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let snapshot = store.snapshot {
                VStack(spacing: 12) {
                    QuotaRow(window: snapshot.primary)
                    QuotaRow(window: snapshot.secondary)
                }
            } else {
                Text(store.statusMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                footerText

                Spacer()

                Button("Quit", action: onQuit)
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(18)
        .frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(headerColor.opacity(0.14))
                Image(systemName: "terminal.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(headerColor)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text("Codex Quota")
                    .font(.system(size: 17, weight: .semibold))
                Text(store.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var footerText: some View {
        Group {
            if let lastUpdated = store.snapshot?.lastUpdated {
                Text("Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))")
            } else {
                Text(store.isLoading ? "Loading..." : "Not updated")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var headerColor: Color {
        if store.snapshot == nil {
            return store.isLoading ? QuotaPalette.warningColor : .red
        }

        return .green
    }
}

struct QuotaRow: View {
    let window: QuotaWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(window.title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(Int(window.remainingPercent.rounded()))% left")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }

            ProgressView(value: window.remainingPercent, total: 100)
                .progressViewStyle(.linear)
                .tint(color)

            HStack {
                Text("Used \(Int(window.usedPercent.rounded()))%")
                Spacer()
                Text(resetText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var resetText: String {
        guard let resetsAt = window.resetsAt else {
            return "Reset time unavailable"
        }

        return "Resets \(resetsAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private var color: Color {
        switch window.remainingPercent {
        case ...20:
            return .red
        case ...50:
            return QuotaPalette.warningColor
        default:
            return .green
        }
    }
}
