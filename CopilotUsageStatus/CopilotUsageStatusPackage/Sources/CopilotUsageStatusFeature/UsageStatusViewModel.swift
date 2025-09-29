import Foundation
import SwiftUI

@MainActor
public final class UsageStatusViewModel: ObservableObject {
    public enum State {
        case idle
        case loading
        case loaded(PremiumInteractions)
        case failed(String)

        public var accessibilityLabel: String {
            switch self {
            case .idle, .loading:
                return "正在加载 Copilot 高级互动使用情况"
            case let .loaded(interactions):
                if let total = interactions.total {
                    return "已使用 \(interactions.used) 次，共 \(total) 次"
                } else {
                    return "已使用 \(interactions.used) 次"
                }
            case let .failed(message):
                return "加载失败：\(message)"
            }
        }

        var isIdle: Bool {
            if case .idle = self { return true }
            return false
        }
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var lastUpdated: Date?

    private let service: UsageProviding
    private let refreshInterval: TimeInterval
    private var refreshTask: Task<Void, Never>?

    public init(service: UsageProviding = UsageService(), refreshInterval: TimeInterval = 60) {
        self.service = service
        self.refreshInterval = refreshInterval
    }

    deinit {
        refreshTask?.cancel()
    }

    public func start() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.load()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.refreshInterval * 1_000_000_000))
                await self.load()
            }
        }
    }

    public func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    public func refreshNow() {
        Task { [weak self] in
            await self?.load(force: true)
        }
    }

    private func load(force: Bool = false) async {
        if force || state.isIdle {
            state = .loading
        }

        do {
            let interactions = try await service.fetchPremiumInteractions()
            withAnimation(.easeInOut(duration: 0.15)) {
                state = .loaded(interactions)
            }
            lastUpdated = Date()
        } catch {
            state = .failed(Self.errorDescription(from: error))
        }
    }

    private static func errorDescription(from error: Error) -> String {
        if let usageError = error as? UsageServiceError {
            return usageError.localizedDescription
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "网络连接不可用"
            case .cannotConnectToHost, .timedOut, .cannotFindHost:
                return "无法连接到服务"
            default:
                return urlError.localizedDescription
            }
        }

        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }

        return "\(error.localizedDescription)"
    }

    public var menuTitle: String {
        switch state {
        case .idle, .loading:
            return "Copilot"
        case let .loaded(interactions):
            if let total = interactions.total {
                return "\(interactions.used)/\(total)"
            } else {
                return "\(interactions.used) used"
            }
        case .failed:
            return "Copilot ⚠️"
        }
    }

    public var progressValue: Double? {
        if case let .loaded(interactions) = state {
            return interactions.progress
        }

        return nil
    }

    public var menuSystemImageName: String {
        switch state {
        case .idle, .loading:
            return "arrow.triangle.2.circlepath"
        case .failed:
            return "exclamationmark.triangle.fill"
        case let .loaded(interactions):
            guard let progress = interactions.progress else {
                return "bolt.fill"
            }

            switch progress {
            case ..<0.5:
                return "chart.bar.xaxis"
            case 0.5..<0.8:
                return "chart.bar"
            default:
                return "chart.bar.doc.horizontal.fill"
            }
        }
    }

    public var menuAccessibilityLabel: String {
        state.accessibilityLabel
    }
}
