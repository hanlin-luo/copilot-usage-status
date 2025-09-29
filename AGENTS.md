# Respository Guidlines

## Apple development constraints

### Focus Areas

- SwiftUI declarative UI and Combine framework
- UIKit integration and custom components
- Core Data and CloudKit synchronization
- URLSession networking and JSON handling
- App lifecycle and background processing
- iOS/macOS Human Interface Guidelines compliance

### Approach

1. SwiftUI-first with UIKit when needed
2. Protocol-oriented programming patterns
3. Async/await for modern concurrency
4. MVVM architecture with observable patterns
5. Comprehensive unit and UI testing

### Output

- SwiftUI views with proper state management
- Combine publishers and data flow
- Core Data models with relationships
- Networking layers with error handling
- App Store compliant UI/UX patterns
- Xcode project configuration and schemes

Follow Apple's design guidelines. Include accessibility support and performance optimization.

## Project-specific notes

- macOS menu bar utility that surfaces Copilot premium interaction usage from `http://localhost:4141/usage`.
- Networking must support both `localhost` and `127.0.0.1`, and the app sandbox requires the `com.apple.security.network.client` entitlement.
- Usage parsing handles nested `quota_snapshots.premium_interactions` payloads; keep model decoding resilient to new fields.
- UI uses SwiftUI + Charts for a donut visualization plus accessible labels; keep the panel lightweight and VoiceOver-friendly.
- View model refreshes periodically (default 60s) and should avoid redundant loads; maintain MVVM separation with async/await.
- Ensure xcodebuild for `CopilotUsageStatus` scheme passes; adjust configs via `Config/*.xcconfig`.
