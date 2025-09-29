import SwiftUI
import CopilotUsageStatusFeature

@main
struct CopilotUsageStatusApp: App {
    @StateObject private var viewModel = UsageStatusViewModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 240)
        } label: {
            MenuBarLabelView(title: viewModel.menuTitle,
                              systemImage: viewModel.menuSystemImageName,
                              progress: viewModel.progressValue,
                              accessibilityLabel: viewModel.menuAccessibilityLabel)
            .task {
                viewModel.start()
            }
            .onDisappear {
                viewModel.stop()
            }
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabelView: View {
    let title: String
    let systemImage: String
    let progress: Double?
    let accessibilityLabel: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            if let progress {
                ProgressCircle(progress: progress)
            } else {
                Image(systemName: systemImage)
                    .symbolVariant(.fill)
            }
        }
        .labelStyle(.titleAndIcon)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(title))
    }
}

private struct ProgressCircle: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }
}
