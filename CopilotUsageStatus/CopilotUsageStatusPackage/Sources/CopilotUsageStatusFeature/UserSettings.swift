import Foundation

public final class UserSettings: ObservableObject {
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let customAPIBaseURL = "customAPIBaseURL"
    }
    
    @Published public var customAPIBaseURL: String {
        didSet {
            defaults.set(customAPIBaseURL, forKey: Keys.customAPIBaseURL)
        }
    }
    
    public init() {
        self.customAPIBaseURL = defaults.string(forKey: Keys.customAPIBaseURL) ?? ""
    }
    
    public var effectiveBaseURL: URL? {
        let trimmed = customAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }
        return URL(string: trimmed)
    }
    
    public func resetToDefault() {
        customAPIBaseURL = ""
    }
}
