import Foundation

public protocol UsageProviding: Sendable {
    func fetchPremiumInteractions() async throws -> PremiumInteractions
}

public enum UsageServiceError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case missingPremiumInteractions

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务响应无效"
        case let .httpError(code):
            return "请求失败，状态码 \(code)"
        case .missingPremiumInteractions:
            return "缺少 premium_interactions 数据"
        }
    }
}

public struct UsageService: UsageProviding {
    public let session: URLSession
    public let baseURL: URL
    public let fallbackBaseURL: URL?

    public init(session: URLSession = .shared,
                baseURL: URL = URL(string: "http://localhost:4141")!,
                fallbackBaseURL: URL? = URL(string: "http://127.0.0.1:4141")) {
        self.session = session
        self.baseURL = baseURL
        self.fallbackBaseURL = fallbackBaseURL
    }

    public func fetchPremiumInteractions() async throws -> PremiumInteractions {
        let endpoints = [baseURL, fallbackBaseURL].compactMap { $0 }

        var lastError: Error?

        for endpoint in endpoints {
            do {
                return try await fetch(from: endpoint)
            } catch {
                lastError = error

                if let urlError = error as? URLError,
                   [.cannotConnectToHost, .timedOut, .networkConnectionLost, .cannotFindHost].contains(urlError.code) {
                    continue
                }

                throw error
            }
        }

        throw lastError ?? UsageServiceError.missingPremiumInteractions
    }

    private func fetch(from baseURL: URL) async throws -> PremiumInteractions {
        let requestURL = baseURL.appendingPathComponent("usage")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageServiceError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw UsageServiceError.httpError(httpResponse.statusCode)
        }

        let usageResponse = try JSONDecoder().decode(UsageResponse.self, from: data)

        guard let premium = usageResponse.premiumInteractions else {
            throw UsageServiceError.missingPremiumInteractions
        }

        return premium
    }
}

extension UsageService: @unchecked Sendable {}
