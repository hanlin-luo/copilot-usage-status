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
    @Published public var endpointDraft: String {
        didSet {
            guard allowsEndpointUpdates else { return }
            validateEndpointInput()
        }
    }
    @Published public private(set) var endpointError: String?

    private var service: UsageProviding
    private let refreshInterval: TimeInterval
    private var refreshTask: Task<Void, Never>?
    private let userDefaults: UserDefaults
    private let serviceFactory: (URL, URL?) -> UsageProviding
    private let allowsEndpointUpdates: Bool
    private var storedEndpointString: String
    private var pendingNormalizedEndpoint: NormalizedEndpoint?

    private static let endpointDefaultsKey = "copilotUsageEndpointURL"
    private static let defaultEndpointString = "http://localhost:4141/usage"

    public init(service: UsageProviding? = nil,
                refreshInterval: TimeInterval = 60,
                userDefaults: UserDefaults = .standard,
                serviceFactory: ((URL, URL?) -> UsageProviding)? = nil) {
        self.serviceFactory = serviceFactory ?? { endpoint, fallback in
            UsageService(endpoint: endpoint, fallbackEndpoint: fallback)
        }
        self.userDefaults = userDefaults
        self.refreshInterval = refreshInterval

        let storedValue = userDefaults.string(forKey: Self.endpointDefaultsKey) ?? Self.defaultEndpointString
        let normalizedStored = Self.normalizeEndpoint(from: storedValue) ?? Self.normalizeEndpoint(from: Self.defaultEndpointString)!

        self.storedEndpointString = normalizedStored.normalizedString
        self.endpointDraft = normalizedStored.normalizedString

        if storedValue != normalizedStored.normalizedString {
            userDefaults.set(normalizedStored.normalizedString, forKey: Self.endpointDefaultsKey)
        }

        if let service, !(service is UsageService) {
            self.service = service
            self.allowsEndpointUpdates = false
        } else {
            self.service = self.serviceFactory(normalizedStored.url, normalizedStored.fallback)
            self.allowsEndpointUpdates = true
            self.pendingNormalizedEndpoint = normalizedStored
        }

        self.endpointError = nil
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

    public var isEndpointEditable: Bool {
        allowsEndpointUpdates
    }

    public var canApplyEndpoint: Bool {
        guard allowsEndpointUpdates else { return false }
        guard endpointError == nil, let normalized = pendingNormalizedEndpoint else { return false }
        return normalized.normalizedString != storedEndpointString
    }

    public var canResetEndpoint: Bool {
        allowsEndpointUpdates && storedEndpointString != Self.defaultEndpointString
    }

    public func applyEndpointChanges() {
        guard allowsEndpointUpdates else { return }
        validateEndpointInput()

        guard endpointError == nil, let normalized = pendingNormalizedEndpoint else { return }
        guard normalized.normalizedString != storedEndpointString else { return }

        storedEndpointString = normalized.normalizedString
        userDefaults.set(normalized.normalizedString, forKey: Self.endpointDefaultsKey)
        service = serviceFactory(normalized.url, normalized.fallback)

        endpointDraft = normalized.normalizedString
        pendingNormalizedEndpoint = normalized
        endpointError = nil

        refreshNow()
    }

    public func resetEndpointToDefault() {
        guard allowsEndpointUpdates else { return }
        endpointDraft = Self.defaultEndpointString
        applyEndpointChanges()
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

    private func validateEndpointInput() {
        let trimmed = endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            endpointError = "请输入有效的 URL"
            pendingNormalizedEndpoint = nil
            return
        }

        guard let normalized = Self.normalizeEndpoint(from: trimmed) else {
            endpointError = "URL 无效"
            pendingNormalizedEndpoint = nil
            return
        }

        endpointError = nil
        pendingNormalizedEndpoint = normalized
    }

    private static func normalizeEndpoint(from input: String) -> NormalizedEndpoint? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var working = trimmed

        if !working.contains("://") {
            working = "http://" + working
        }

        guard var components = URLComponents(string: working) else {
            return nil
        }

        if components.scheme == nil {
            components.scheme = "http"
        }

        guard components.host != nil else {
            return nil
        }

        if components.path.isEmpty || components.path == "/" {
            components.path = "/usage"
        }

        guard let normalizedURL = components.url else {
            return nil
        }

        var fallbackURL: URL?
        if let host = components.host?.lowercased() {
            if host == "localhost" {
                var fallbackComponents = components
                fallbackComponents.host = "127.0.0.1"
                fallbackURL = fallbackComponents.url
            } else if host == "127.0.0.1" {
                var fallbackComponents = components
                fallbackComponents.host = "localhost"
                fallbackURL = fallbackComponents.url
            }
        }

        return NormalizedEndpoint(url: normalizedURL,
                                   fallback: fallbackURL,
                                   normalizedString: normalizedURL.absoluteString)
    }

    private struct NormalizedEndpoint {
        let url: URL
        let fallback: URL?
        let normalizedString: String
    }
}
