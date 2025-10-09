import Testing
import Foundation
@testable import CopilotUsageStatusFeature

@Test func testUserSettingsDefaultValue() async throws {
    let settings = UserSettings()
    #expect(settings.customAPIBaseURL == "")
    #expect(settings.effectiveBaseURL == nil)
}

@Test func testUserSettingsValidURL() async throws {
    let settings = UserSettings()
    settings.customAPIBaseURL = "http://192.168.1.100:8080"
    
    #expect(settings.effectiveBaseURL != nil)
    #expect(settings.effectiveBaseURL?.absoluteString == "http://192.168.1.100:8080")
}

@Test func testUserSettingsInvalidURL() async throws {
    let settings = UserSettings()
    settings.customAPIBaseURL = "not a valid url"
    
    #expect(settings.effectiveBaseURL == nil)
}

@Test func testUserSettingsEmptyURL() async throws {
    let settings = UserSettings()
    settings.customAPIBaseURL = "   "
    
    #expect(settings.effectiveBaseURL == nil)
}

@Test func testUserSettingsReset() async throws {
    let settings = UserSettings()
    settings.customAPIBaseURL = "http://example.com"
    #expect(settings.customAPIBaseURL == "http://example.com")
    
    settings.resetToDefault()
    #expect(settings.customAPIBaseURL == "")
    #expect(settings.effectiveBaseURL == nil)
}

@Test func testUsageServiceWithCustomURL() async throws {
    let customURL = URL(string: "http://custom-server:9999")!
    let service = UsageService(baseURL: customURL, fallbackBaseURL: nil)
    
    #expect(service.baseURL == customURL)
    #expect(service.fallbackBaseURL == nil)
}
