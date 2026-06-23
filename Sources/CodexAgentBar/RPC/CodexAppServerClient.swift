import Foundation

final class CodexAppServerClient {
    typealias JSONDictionary = [String: Any]
    typealias Completion = @Sendable (Result<JSONDictionary, Error>) -> Void

    var notificationHandler: ((String, JSONDictionary?) -> Void)?

    private let queue = DispatchQueue(label: "codex-agent-bar.rpc")
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var outputBuffer = Data()
    private var nextRequestID = 1
    private var pending: [Int: Completion] = [:]
    private var initialized = false

    func start(completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        queue.async {
            if self.initialized {
                completion(.success(()))
                return
            }

            guard self.process == nil else {
                completion(.failure(QuotaError.initializationFailed("app-server is already starting.")))
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

    private func launchProcess() throws {
        guard let codexPath = resolveCodexCLIPath() else {
            throw QuotaError.codexCLINotFound
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["-s", "read-only", "-a", "untrusted", "app-server"]
        process.environment = makeProcessEnvironment(codexPath: codexPath)
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

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
            guard !data.isEmpty, let message = String(data: data, encoding: .utf8) else {
                return
            }

            self?.log("app-server stderr: \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        process.terminationHandler = { [weak self] process in
            guard let client = self else {
                return
            }

            client.queue.async {
                client.log("app-server exited with status \(process.terminationStatus)")
                client.failAllPendingLocked(QuotaError.appServerStartFailed("Process exited with status \(process.terminationStatus)."))
                client.stopLocked()
            }
        }

        try process.run()

        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe
        log("Started codex app-server at \(codexPath)")
    }

    private func makeProcessEnvironment(codexPath: String) -> [String: String] {
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
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
        failAllPendingLocked(QuotaError.appServerStartFailed("Process stopped."))

        if let process, process.isRunning {
            process.terminate()
        }

        process = nil
    }

    private func resolveCodexCLIPath() -> String? {
        let fileManager = FileManager.default
        let environmentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let pathCandidates = environmentPath
            .split(separator: ":")
            .map { String($0) + "/codex" }

        var candidates = pathCandidates + [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]

        let home = fileManager.homeDirectoryForCurrentUser.path
        let nvmRoot = "\(home)/.nvm/versions/node"
        if let versions = try? fileManager.contentsOfDirectory(atPath: nvmRoot) {
            candidates += versions
                .sorted(by: >)
                .map { "\(nvmRoot)/\($0)/bin/codex" }
        }

        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
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
        print("[CodexAgentBar] \(message)")
    }
}

extension CodexAppServerClient: @unchecked Sendable {}
