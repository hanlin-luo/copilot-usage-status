import SwiftUI
#if canImport(Charts)
import Charts
#endif
#if canImport(AppKit)
import AppKit
#endif

public struct ContentView: View {
    @ObservedObject private var viewModel: UsageStatusViewModel

    public init(viewModel: UsageStatusViewModel) {
        _viewModel = ObservedObject(initialValue: viewModel)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            endpointConfiguration
            Divider()
            actions
        }
        .padding(16)
        .frame(minWidth: 240, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var endpointConfiguration: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("API 地址")
                    .font(.subheadline)
            } icon: {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
            }
            .labelStyle(.titleAndIcon)
            .accessibilityHidden(true)

            TextField("例如：http://localhost:4141/usage", text: $viewModel.endpointDraft)
                .textFieldStyle(.roundedBorder)
                .disabled(!viewModel.isEndpointEditable)
                .onSubmit { viewModel.applyEndpointChanges() }
                .accessibilityLabel("Copilot API 地址")

            if let error = viewModel.endpointError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                Button {
                    viewModel.applyEndpointChanges()
                } label: {
                    Label("应用", systemImage: "checkmark.circle")
                }
                .disabled(!viewModel.canApplyEndpoint)

                Button {
                    viewModel.resetEndpointToDefault()
                } label: {
                    Label("重置", systemImage: "arrow.uturn.backward")
                }
                .disabled(!viewModel.canResetEndpoint)
            }
            .buttonStyle(.borderless)
            .imageScale(.medium)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var header: some View {
        Text("Copilot 高级用量")
            .font(.headline)

        switch viewModel.state {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(.circular)
                Text("加载中…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("正在加载最新用量")

        case let .loaded(interactions):
            LoadedUsageView(interactions: interactions, lastUpdated: viewModel.lastUpdated)

        case let .failed(message):
            VStack(alignment: .leading, spacing: 8) {
                Label("无法获取数据", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let lastUpdated = viewModel.lastUpdated {
                    Text("上次成功更新 \(lastUpdated, style: .relative)")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
            .accessibilityLabel("加载失败：\(message)")
        }
    }

    private var actions: some View {
        HStack {
            Button {
                viewModel.refreshNow()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r")

            Spacer()

#if canImport(AppKit)
            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出", systemImage: "xmark.circle")
            }
            .keyboardShortcut("q")
#endif
        }
        .buttonStyle(.borderless)
        .imageScale(.medium)
    }
}

private struct LoadedUsageView: View {
    let interactions: PremiumInteractions
    let lastUpdated: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSummary
            chartSection
            footerMeta
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var headerSummary: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text("\(interactions.used)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()

            if let total = interactions.totalComputed {
                Text("/ \(total)")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }

        if let remaining = interactions.remaining {
            Text("剩余 \(remaining) 次")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var chartSection: some View {
#if canImport(Charts)
        if let total = interactions.totalComputed, total > 0 {
            UsageDonutChart(interactions: interactions, total: total)
                .padding(.vertical, 8)
        } else if let percentRemaining = interactions.percentRemaining {
            Gauge(value: max(0, min(1, 1 - percentRemaining / 100))) {
                Text("使用率")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(Gradient(colors: [.accentColor, .blue]))
            .frame(width: 120, height: 120)
            .padding(.vertical, 8)
        } else if let progress = interactions.progress {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .accessibilityLabel("已使用 \(Int(progress * 100)) 百分比")
        }
#else
        if let progress = interactions.progress {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .accessibilityLabel("已使用 \(Int(progress * 100)) 百分比")
        }
#endif
    }

    @ViewBuilder
    private var footerMeta: some View {
        if let lastUpdated {
            Text("更新于 \(lastUpdated, style: .relative)")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }
}

private extension PremiumInteractions {
    var totalComputed: Int? {
        if let total { return total }
        if let remaining { return remaining + used }
        return nil
    }
}

#if canImport(Charts)
private struct UsageDonutChart: View {
    struct Slice: Identifiable {
        let id: String
        let label: String
        let value: Double
        let color: Color
        let icon: String
    }

    let interactions: PremiumInteractions
    let total: Int

    private var slices: [Slice] {
        let usedValue = Double(interactions.used)
        let remainingValue = Double(max(total - interactions.used, 0))

        return [
            Slice(id: "used", label: "已使用", value: usedValue, color: Color.accentColor, icon: "flame.fill"),
            Slice(id: "remaining", label: "剩余", value: remainingValue, color: Color.green.opacity(0.85), icon: "leaf.fill")
        ].filter { $0.value > 0 }
    }

    private var usagePercentage: Int {
        guard total > 0 else { return 0 }
        return Int(round(Double(interactions.used) / Double(total) * 100))
    }

    var body: some View {
        VStack(spacing: 12) {
            Chart(slices) { slice in
                SectorMark(
                    angle: .value("Quota", slice.value),
                    innerRadius: .ratio(0.6),
                    outerRadius: .ratio(1.0)
                )
                .cornerRadius(8)
                .foregroundStyle(slice.color)
            }
            .chartLegend(.hidden)
            .frame(height: 160)
            .overlay(alignment: .center) {
                GaugeCenterLabel(percentage: usagePercentage)
            }
            .accessibilityLabel("Copilot 用量图表")
            .accessibilityValue("已使用 \(usagePercentage) 百分之")

            UsageLegend(slices: slices, total: total, used: interactions.used)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
    }
}

private struct GaugeCenterLabel: View {
    let percentage: Int

    var body: some View {
        VStack(spacing: 4) {
            Text("已使用")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(percentage)%")
                .font(.title2)
                .fontWeight(.semibold)
                .contentTransition(.numericText())
        }
        .accessibilityHidden(true)
    }
}

private struct UsageLegend: View {
    let slices: [UsageDonutChart.Slice]
    let total: Int
    let used: Int

    var remaining: Int { max(total - used, 0) }

    var body: some View {
        HStack(spacing: 16) {
            ForEach(slices) { slice in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(slice.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if slice.id == "used" {
                            Text("\(used) 次")
                                .font(.caption2)
                                .foregroundStyle(.primary)
                                .monospacedDigit()
                        } else {
                            Text("\(remaining) 次")
                                .font(.caption2)
                                .foregroundStyle(.primary)
                                .monospacedDigit()
                        }
                    }
                } icon: {
                    Image(systemName: slice.icon)
                        .font(.caption)
                        .foregroundStyle(slice.color)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
#endif

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(viewModel: UsageStatusViewModel(service: PreviewUsageService(), refreshInterval: 60))
            .frame(width: 280)
    }
}

private struct PreviewUsageService: UsageProviding {
    func fetchPremiumInteractions() async throws -> PremiumInteractions {
        PremiumInteractions(used: 12, total: 50)
    }
}
#endif
