import Foundation

/// Manages the lifecycle of the copilot-api service process
@MainActor
public final class CopilotApiService: ObservableObject {
    public enum ServiceState: Equatable {
        case idle
        case starting
        case running
        case stopping
        case stopped(String)
        case failed(String)

        public static func == (lhs: ServiceState, rhs: ServiceState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.starting, .starting), (.running, .running), (.stopping, .stopping):
                return true
            case let (.stopped(lhsMessage), .stopped(rhsMessage)):
                return lhsMessage == rhsMessage
            case let (.failed(lhsMessage), .failed(rhsMessage)):
                return lhsMessage == rhsMessage
            default:
                return false
            }
        }
    }

    @Published public private(set) var state: ServiceState = .idle

    private var process: Process?
    private let command = "npx"
    private let arguments = ["copilot-api@latest", "start"]

    // Store full path to npx for better reliability
    private var npxPath: String {
        // Try to find npx in common locations
        let commonPaths = [
            "/usr/local/bin/npx",
            "/opt/homebrew/bin/npx",
            "~/.nvm/versions/node/*/bin/npx"
        ]

        // First try system PATH
        if let path = findCommandInPath("npx") {
            return path
        }

        // Try common paths
        for pathTemplate in commonPaths {
            let expandedPath = (pathTemplate as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expandedPath) {
                return expandedPath
            }
        }

        // Fallback to just "npx"
        return "npx"
    }

    private func findCommandInPath(_ command: String) -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let paths = path.split(separator: ":")

        print("Searching for \(command) in PATH: \(path)")

        for pathDir in paths {
            let fullPath = "\(pathDir)/\(command)"
            if FileManager.default.fileExists(atPath: fullPath) {
                print("Found \(command) at: \(fullPath)")
                return fullPath
            }
        }

        // Special handling for NVM - check common NVM directories
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let nvmBasePaths = [
            "\(homeDir)/.nvm/versions/node",
            "/usr/local",
            "/opt/homebrew"
        ]

        for basePath in nvmBasePaths {
            if let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: basePath), includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    if fileURL.lastPathComponent == command && FileManager.default.isExecutableFile(atPath: fileURL.path) {
                        print("Found \(command) at NVM location: \(fileURL.path)")
                        return fileURL.path
                    }
                }
            }
        }

        print("Could not find \(command) in any location")
        return nil
    }

    public init() {}

    deinit {
        // Cannot call async method in deinit, so we'll handle cleanup differently
        if let process = process {
            process.terminate()
        }
    }

    /// Starts the copilot-api service
    public func startService() async {
        switch state {
        case .idle, .stopped, .failed:
            // Can start from these states
            break
        case .starting, .running, .stopping:
            return // Already starting or running
        }

        state = .starting

        do {
            try await startProcess()
            state = .running
        } catch {
            state = .failed("Failed to start service: \(error.localizedDescription)")
        }
    }

    /// Stops the copilot-api service
    public func stopService() {
        guard state == .running || state == .starting else {
            return
        }

        state = .stopping

        if let process = process {
            process.terminate()
            process.waitUntilExit()
            self.process = nil
        }

        state = .stopped("Service stopped")
    }

    private func startProcess() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()

            // Use the resolved npx path
            let resolvedCommand = npxPath
            print("Starting copilot-api with command: \(resolvedCommand)")

            // Check if the command exists
            guard FileManager.default.fileExists(atPath: resolvedCommand) || resolvedCommand == "npx" else {
                let error = NSError(domain: "CopilotApiService", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "npx command not found at path: \(resolvedCommand)"
                ])
                print("Command not found: \(resolvedCommand)")
                continuation.resume(throwing: error)
                return
            }

            process.executableURL = URL(fileURLWithPath: resolvedCommand)
            process.arguments = arguments

            // Set environment variables (clean copy for sandbox safety)
            let environment = ProcessInfo.processInfo.environment
            process.environment = environment

            // Set up pipes for output and error
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            // Set current working directory to user home for better sandbox compatibility
            if let homeDir = FileManager.default.homeDirectoryForCurrentUser as URL? {
                process.currentDirectoryURL = homeDir
            }

            do {
                try process.run()
                self.process = process
                print("Successfully started copilot-api process with PID: \(process.processIdentifier)")
                // Only begin monitoring after the process has launched successfully
                monitorProcessOutput(outputPipe: outputPipe, errorPipe: errorPipe, process: process)
                continuation.resume()
            } catch {
                print("Failed to start copilot-api process: \(error)")

                // Provide more specific error messages for common sandbox issues
                let errorMessage: String
                if error.localizedDescription.contains("Operation not permitted") {
                    errorMessage = "Sandbox restriction: Cannot execute external processes. This may require disabling sandbox or adding proper entitlements."
                } else if error.localizedDescription.contains("No such file or directory") {
                    errorMessage = "Command not found: \(resolvedCommand). Please ensure Node.js and npm are installed."
                } else {
                    errorMessage = "Failed to start copilot-api: \(error.localizedDescription)"
                }

                let detailedError = NSError(domain: "CopilotApiService", code: error._code, userInfo: [
                    NSLocalizedDescriptionKey: errorMessage
                ])
                continuation.resume(throwing: detailedError)
            }
        }
    }

    private func monitorProcessOutput(outputPipe: Pipe, errorPipe: Pipe, process: Process) {
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading

        // We don't need to buffer data for this use case, just process it immediately
        outputHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.count > 0, let output = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    self?.handleServiceOutput(output)
                }
            }
        }

        errorHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.count > 0, let errorOutput = String(data: data, encoding: .utf8) {
                print("copilot-api error: \(errorOutput)")
                // If we see common error patterns, update the state
                if errorOutput.contains("command not found") || errorOutput.contains("not found") {
                    Task { @MainActor in
                        self?.state = .failed("npx command not found. Please install Node.js and npm.")
                    }
                } else if errorOutput.contains("permission denied") {
                    Task { @MainActor in
                        self?.state = .failed("Permission denied. Check file permissions.")
                    }
                }
            }
        }

        // Monitor process termination
        DispatchQueue.global(qos: .background).async { [weak self] in
            process.waitUntilExit()
            let terminationStatus = process.terminationStatus
            Task { @MainActor in
                guard let self = self else { return }
                if self.state == .running || self.state == .starting {
                    if terminationStatus == 0 {
                        self.state = .stopped("Service completed normally")
                    } else {
                        self.state = .failed("Service exited with code: \(terminationStatus)")
                    }
                }
            }
        }
    }

    private func handleServiceOutput(_ output: String) {
        // Look for indicators that the service is ready
        if output.contains("Server running") ||
           output.contains("Listening on") ||
           output.contains("4141") ||
           output.contains("ready") {
            if case .starting = state {
                state = .running
            }
        }
    }
}
