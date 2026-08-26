import Foundation

final class CodexAppServerClient {
    typealias JSONDictionary = [String: Any]
    typealias Completion = @Sendable (Result<JSONDictionary, Error>) -> Void

    static let minimumResetCreditsVersion = CodexCLIVersion(major: 0, minor: 142, patch: 3)

    private static let initializationTimeoutSeconds = 10
    private static let maximumStderrBytes = 8_192

    var notificationHandler: ((String, JSONDictionary?) -> Void)?

    private let queue = DispatchQueue(label: "AgentBar.rpc")
    private let stderrLock = NSLock()
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var outputBuffer = Data()
    private var stderrBuffer = Data()
    private var nextRequestID = 1
    private var pending: [Int: Completion] = [:]
    private var initialized = false
    private var selectedCodexPath: String?
    private var selectedCodexVersion: CodexCLIVersion?
    private var initializationTimeoutWorkItem: DispatchWorkItem?

    func start(completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        queue.async {
            if self.initialized {
                completion(.success(()))
                return
            }

            guard self.process == nil else {
                completion(.failure(QuotaError.initializationFailed(I18n.current.appServerAlreadyStarting)))
                return
            }

            do {
                try self.launchProcess()
                self.sendRequestLocked(
                    method: "initialize",
                    id: 0,
                    params: [
                        "clientInfo": [
                            "name": "codex_agent_bar",
                            "title": "Codex Agent Bar",
                            "version": AppVersion.shortVersion,
                        ],
                    ]
                ) { result in
                    switch result {
                    case .success:
                        self.sendNotificationLocked(method: "initialized", params: [:])
                        self.initialized = true
                        self.log("RPC initialized")
                        completion(.success(()))
                    case .failure(let error):
                        self.stop()
                        completion(.failure(QuotaError.initializationFailed(error.localizedDescription)))
                    }
                }
                self.scheduleInitializationTimeoutLocked()
            } catch {
                self.stopLocked()
                completion(.failure(error))
            }
        }
    }

    func sendRequest(method: String, params: JSONDictionary? = nil, completion: @escaping Completion) {
        let sendableParams = UncheckedSendable(params)

        queue.async {
            let id = self.nextRequestID
            self.nextRequestID += 1
            self.sendRequestLocked(method: method, id: id, params: sendableParams.value, completion: completion)
        }
    }

    func stop() {
        queue.async {
            self.stopLocked()
        }
    }

    func checkMinimumResetCreditsVersion(completion: @escaping @Sendable (Result<CodexCLIVersion, Error>) -> Void) {
        queue.async {
            self.selectedCodexPath = nil
            self.selectedCodexVersion = nil
            guard let codexPath = Self.resolveCodexCLIPath() else {
                completion(.failure(QuotaError.codexCLINotFound))
                return
            }

            do {
                let version = try Self.readCodexCLIVersion(codexPath: codexPath)
                guard version >= Self.minimumResetCreditsVersion else {
                    completion(.failure(QuotaError.unsupportedCodexCLIVersion(
                        current: version.displayText,
                        required: Self.minimumResetCreditsVersion.displayText
                    )))
                    return
                }

                self.selectedCodexPath = codexPath
                self.selectedCodexVersion = version
                self.log("Selected Codex CLI \(codexPath) (\(version.displayText))")
                completion(.success(version))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func launchProcess() throws {
        guard let codexPath = selectedCodexPath ?? Self.resolveCodexCLIPath() else {
            throw QuotaError.codexCLINotFound
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server"]
        process.environment = Self.makeProcessEnvironment(codexPath: codexPath)
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        clearStderrBuffer()

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }

            guard let client = self else {
                return
            }

            client.queue.async {
                client.consumeOutput(data)
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let client = self else {
                return
            }

            client.appendStderr(data)
            if let message = String(data: data, encoding: .utf8) {
                client.log("app-server stderr: \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        process.terminationHandler = { [weak self] process in
            guard let client = self else {
                return
            }

            errorPipe.fileHandleForReading.readabilityHandler = nil
            client.appendStderr(errorPipe.fileHandleForReading.readDataToEndOfFile())

            client.queue.async {
                client.log("app-server exited with status \(process.terminationStatus)")
                client.cancelInitializationTimeoutLocked()
                let message = client.appServerDiagnosticMessageLocked(
                    summary: I18n.current.appServerExited(status: process.terminationStatus)
                )
                client.failAllPendingLocked(QuotaError.appServerStartFailed(message))
                client.stopLocked()
            }
        }

        try process.run()

        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe
        let version = selectedCodexVersion.map { " (\($0.displayText))" } ?? ""
        log("Started codex app-server at \(codexPath)\(version)")
    }

    private func scheduleInitializationTimeoutLocked() {
        cancelInitializationTimeoutLocked()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.initialized, self.pending[0] != nil else {
                return
            }

            self.initializationTimeoutWorkItem = nil
            let message = self.appServerDiagnosticMessageLocked(
                summary: I18n.current.appServerInitializationTimedOut(
                    seconds: Self.initializationTimeoutSeconds
                )
            )
            self.failAllPendingLocked(QuotaError.appServerStartFailed(message))
            self.stopLocked()
        }

        initializationTimeoutWorkItem = workItem
        queue.asyncAfter(
            deadline: .now() + .seconds(Self.initializationTimeoutSeconds),
            execute: workItem
        )
    }

    private func cancelInitializationTimeoutLocked() {
        initializationTimeoutWorkItem?.cancel()
        initializationTimeoutWorkItem = nil
    }

    private func appendStderr(_ data: Data) {
        guard !data.isEmpty else {
            return
        }

        stderrLock.lock()
        defer { stderrLock.unlock() }

        let remainingCapacity = Self.maximumStderrBytes - stderrBuffer.count
        guard remainingCapacity > 0 else {
            return
        }

        stderrBuffer.append(data.prefix(remainingCapacity))
    }

    private func clearStderrBuffer() {
        stderrLock.lock()
        stderrBuffer.removeAll(keepingCapacity: true)
        stderrLock.unlock()
    }

    private func capturedStderr() -> String {
        stderrLock.lock()
        let data = stderrBuffer
        stderrLock.unlock()

        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func appServerDiagnosticMessageLocked(summary: String) -> String {
        var lines = [summary]

        if let selectedCodexPath {
            let version = selectedCodexVersion.map { " (\($0.displayText))" } ?? ""
            lines.append("Codex CLI: \(selectedCodexPath)\(version)")
        }

        let stderr = capturedStderr()
        if !stderr.isEmpty {
            lines.append(stderr)
        }

        return lines.joined(separator: "\n")
    }

    private static func makeProcessEnvironment(codexPath: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let codexBinDirectory = URL(fileURLWithPath: codexPath).deletingLastPathComponent().path
        let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let currentPath = environment["PATH"] ?? defaultPath
        let pathParts = ([codexBinDirectory] + currentPath.split(separator: ":").map(String.init))
            .reduce(into: [String]()) { result, path in
                guard !result.contains(path) else {
                    return
                }

                result.append(path)
            }

        environment["PATH"] = pathParts.joined(separator: ":")
        return environment
    }

    private func sendRequestLocked(
        method: String,
        id: Int,
        params: JSONDictionary?,
        completion: @escaping Completion
    ) {
        var message: JSONDictionary = [
            "method": method,
            "id": id,
        ]

        if let params {
            message["params"] = params
        }

        pending[id] = completion
        writeMessageLocked(message)
        log("RPC request \(id) \(method)")
    }

    private func sendNotificationLocked(method: String, params: JSONDictionary?) {
        var message: JSONDictionary = [
            "method": method,
        ]

        if let params {
            message["params"] = params
        }

        writeMessageLocked(message)
        log("RPC notification sent \(method)")
    }

    private func writeMessageLocked(_ message: JSONDictionary) {
        do {
            let data = try JSONSerialization.data(withJSONObject: message, options: [])
            var line = data
            line.append(0x0A)
            inputPipe?.fileHandleForWriting.write(line)
        } catch {
            log("Failed to encode RPC message: \(error.localizedDescription)")
        }
    }

    private func consumeOutput(_ data: Data) {
        outputBuffer.append(data)

        while let newlineIndex = outputBuffer.firstIndex(of: 0x0A) {
            let lineData = outputBuffer[..<newlineIndex]
            outputBuffer.removeSubrange(...newlineIndex)

            guard !lineData.isEmpty else {
                continue
            }

            handleLine(Data(lineData))
        }
    }

    private func handleLine(_ lineData: Data) {
        do {
            let object = try JSONSerialization.jsonObject(with: lineData, options: [])
            guard let message = object as? JSONDictionary else {
                log("RPC non-object message ignored")
                return
            }

            log("RPC message received:\n\(prettyPrintedSanitizedJSON(message))")

            if let id = message["id"] as? Int {
                guard let completion = pending.removeValue(forKey: id) else {
                    log("RPC response \(id) has no pending request")
                    return
                }

                if id == 0 {
                    cancelInitializationTimeoutLocked()
                }

                if let errorObject = message["error"] as? JSONDictionary {
                    completion(.failure(QuotaError.rpcError(rpcErrorMessage(errorObject))))
                } else {
                    completion(.success(message))
                }
                return
            }

            if let method = message["method"] as? String {
                let params = message["params"] as? JSONDictionary
                DispatchQueue.main.async {
                    self.notificationHandler?(method, params)
                }
            }
        } catch {
            log("Failed to parse RPC line: \(error.localizedDescription)")
        }
    }

    private func rpcErrorMessage(_ errorObject: JSONDictionary) -> String {
        if let message = errorObject["message"] as? String {
            return message
        }

        return prettyPrintedSanitizedJSON(errorObject)
    }

    private func failAllPendingLocked(_ error: Error) {
        let callbacks = pending.values
        pending.removeAll()
        callbacks.forEach { $0(.failure(error)) }
    }

    private func stopLocked() {
        initialized = false
        cancelInitializationTimeoutLocked()
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
        failAllPendingLocked(QuotaError.appServerStartFailed(I18n.current.processStopped))

        if let process, process.isRunning {
            process.terminate()
        }

        process = nil
        outputBuffer.removeAll(keepingCapacity: true)
        clearStderrBuffer()
    }

    private static func readCodexCLIVersion(codexPath: String) throws -> CodexCLIVersion {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["--version"]
        process.environment = makeProcessEnvironment(codexPath: codexPath)
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: errorOutput, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let versionText = stdout.isEmpty ? stderr : stdout

        guard process.terminationStatus == 0, let version = CodexCLIVersion.parse(versionText) else {
            throw QuotaError.appServerStartFailed(versionText)
        }

        return version
    }

    private static func resolveCodexCLIPath() -> String? {
        CodexCLIResolver.resolve()
    }

    private func prettyPrintedSanitizedJSON(_ object: Any) -> String {
        let sanitized = sanitizeJSONObject(object)
        guard
            JSONSerialization.isValidJSONObject(sanitized),
            let data = try? JSONSerialization.data(withJSONObject: sanitized, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else {
            return "\(sanitized)"
        }

        return text
    }

    private func sanitizeJSONObject(_ object: Any) -> Any {
        if let dictionary = object as? JSONDictionary {
            return dictionary.reduce(into: JSONDictionary()) { result, item in
                let key = item.key
                let lowercasedKey = key.lowercased()

                if lowercasedKey.contains("token")
                    || lowercasedKey.contains("secret")
                    || lowercasedKey.contains("authorization")
                    || lowercasedKey.contains("api_key")
                    || lowercasedKey.contains("apikey") {
                    result[key] = "<redacted>"
                } else if lowercasedKey == "email", let email = item.value as? String {
                    result[key] = maskEmail(email)
                } else {
                    result[key] = sanitizeJSONObject(item.value)
                }
            }
        }

        if let array = object as? [Any] {
            return array.map { sanitizeJSONObject($0) }
        }

        return object
    }

    private func maskEmail(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2, let first = parts[0].first else {
            return "<redacted-email>"
        }

        return "\(first)***@\(parts[1])"
    }

    private func log(_ message: String) {
        print("[AgentBar] \(message)")
    }
}

extension CodexAppServerClient: @unchecked Sendable {}
