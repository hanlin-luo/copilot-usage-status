import Foundation

struct UsageResponse: Decodable {
    let premiumInteractions: PremiumInteractions?

    enum CodingKeys: String, CodingKey {
        case premiumInteractions = "premium_interactions"
        case quotaSnapshots = "quota_snapshots"
    }

    enum QuotaSnapshotKeys: String, CodingKey {
        case premiumInteractions = "premium_interactions"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let direct = try container.decodeIfPresent(PremiumInteractions.self, forKey: .premiumInteractions) {
            premiumInteractions = direct
            return
        }

        if let snapshots = try? container.nestedContainer(keyedBy: QuotaSnapshotKeys.self, forKey: .quotaSnapshots) {
            premiumInteractions = try snapshots.decodeIfPresent(PremiumInteractions.self, forKey: .premiumInteractions)
        } else {
            premiumInteractions = nil
        }
    }
}

public struct PremiumInteractions: Decodable {
    public let used: Int
    public let total: Int?
    private let providedRemaining: Int?
    public let percentRemaining: Double?
    public let unlimited: Bool?

    public var remaining: Int? {
        if let providedRemaining {
            return providedRemaining
        }

        guard let total else { return nil }
        return max(total - used, 0)
    }

    /// Progress represented as a value between 0 and 1 when total is available.
    public var progress: Double? {
        guard let total, total > 0 else { return nil }
        return Double(used) / Double(total)
    }

    public init(used: Int, total: Int? = nil, remaining: Int? = nil, percentRemaining: Double? = nil, unlimited: Bool? = nil) {
        self.used = used
        self.total = total
        self.providedRemaining = remaining
        self.percentRemaining = percentRemaining
        self.unlimited = unlimited
    }

    public init(from decoder: Decoder) throws {
        if var singleValue = try? decoder.singleValueContainer(), !singleValue.decodeNil() {
            if let intValue = try? singleValue.decode(Int.self) {
                self.init(used: intValue)
                return
            }

            if let stringValue = try? singleValue.decode(String.self), let intValue = Int(stringValue) {
                self.init(used: intValue)
                return
            }
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let total = try Self.decodeInt(forKey: .total, alternateKey: .entitlement, in: container)
        let remaining = try Self.decodeInt(forKey: .remaining, alternateKey: .quotaRemaining, in: container)
        let used = try Self.decodeInt(forKey: .used, in: container)
            ?? Self.deriveUsed(total: total, remaining: remaining)
            ?? 0

        let percentRemaining = try Self.decodeDouble(forKey: .percentRemaining, in: container)
        let unlimited = try container.decodeIfPresent(Bool.self, forKey: .unlimited)

        self.init(used: used,
                  total: total,
                  remaining: remaining,
                  percentRemaining: percentRemaining,
                  unlimited: unlimited)
    }

    private enum CodingKeys: String, CodingKey {
        case used
        case total
        case entitlement
        case remaining
        case quotaRemaining = "quota_remaining"
        case percentRemaining = "percent_remaining"
        case unlimited
    }

    private static func decodeInt(forKey key: CodingKeys,
                                  alternateKey: CodingKeys? = nil,
                                  in container: KeyedDecodingContainer<CodingKeys>) throws -> Int? {
        if let intValue = try container.decodeIfPresent(Int.self, forKey: key) {
            return intValue
        }

        if let stringValue = try container.decodeIfPresent(String.self, forKey: key) {
            return Int(stringValue)
        }

        if let alternateKey,
           let altInt = try container.decodeIfPresent(Int.self, forKey: alternateKey) {
            return altInt
        }

        if let alternateKey,
           let altString = try container.decodeIfPresent(String.self, forKey: alternateKey) {
            return Int(altString)
        }

        return nil
    }

    private static func decodeDouble(forKey key: CodingKeys,
                                     in container: KeyedDecodingContainer<CodingKeys>) throws -> Double? {
        if let doubleValue = try container.decodeIfPresent(Double.self, forKey: key) {
            return doubleValue
        }

        if let stringValue = try container.decodeIfPresent(String.self, forKey: key) {
            return Double(stringValue)
        }

        return nil
    }

    private static func deriveUsed(total: Int?, remaining: Int?) -> Int? {
        guard let total, let remaining else { return nil }
        return max(total - remaining, 0)
    }
}
