import Foundation

@MainActor
public final class CodexClient {
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var buffer = Data()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var timeouts: [Int: Task<Void, Never>] = [:]
    private var generation = UUID()
    public var onUpdate: ((QuotaWindow) -> Void)?

    public init() {}

    public static var executable: String? {
        let candidates = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex",
                          FileManager.default.homeDirectoryForCurrentUser.path + "/.local/bin/codex"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func readWeekly() async throws -> QuotaWindow {
        if process == nil { try await start() }
        let data = try await request("account/rateLimits/read")
        let response = try JSONDecoder().decode(QuotaResponse.self, from: data)
        guard let weekly = response.weekly else { throw ReadingError.noWeeklyWindow }
        return weekly
    }

    private func start() async throws {
        guard let path = Self.executable else { throw ReadingError.codexMissing }
        let child = Process()
        let stdin = Pipe(), stdout = Pipe()
        generation = UUID()
        let token = generation
        child.executableURL = URL(fileURLWithPath: path)
        child.arguments = ["app-server"]
        child.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        child.standardInput = stdin
        child.standardOutput = stdout
        // Never record account payloads, credentials, or unrelated Codex diagnostics.
        child.standardError = FileHandle.nullDevice
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                if data.isEmpty { self.stop() } else { self.receive(data) }
            }
        }
        child.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.stop()
            }
        }
        process = child; input = stdin; output = stdout
        do {
            try child.run()
            _ = try await request("initialize", params: ["clientInfo": ["name": "headroom", "version": "1.0.0"]])
            try send(["method": "initialized", "params": [:]])
        } catch {
            stop()
            throw error
        }
    }

    private func request(_ method: String, params: [String: Any]? = nil) async throws -> Data {
        nextID += 1
        let id = nextID
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            timeouts[id] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled, let self else { return }
                self.finish(id, result: .failure(ReadingError.timedOut))
                self.stop()
            }
            var payload: [String: Any] = ["id": id, "method": method]
            if let params { payload["params"] = params }
            do { try send(payload) }
            catch { finish(id, result: .failure(error)) }
        }
    }

    private func send(_ payload: [String: Any]) throws {
        guard let input, process?.isRunning == true else { throw ReadingError.disconnected }
        var data = try JSONSerialization.data(withJSONObject: payload)
        data.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        guard buffer.count < 4_000_000 else { stop(); return }
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let id = object["id"] as? Int, pending[id] != nil {
                if let result = object["result"], let data = try? JSONSerialization.data(withJSONObject: result) {
                    finish(id, result: .success(data))
                } else {
                    finish(id, result: .failure(ReadingError.unavailable))
                }
            } else if object["method"] as? String == "account/rateLimits/updated",
                      let params = object["params"],
                      let data = try? JSONSerialization.data(withJSONObject: params),
                      let response = try? JSONDecoder().decode(QuotaResponse.self, from: data),
                      let weekly = response.weekly {
                onUpdate?(weekly)
            }
        }
    }

    private func finish(_ id: Int, result: Result<Data, Error>) {
        timeouts.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    public func stop() {
        generation = UUID()
        output?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close()
        let child = process
        child?.terminationHandler = nil
        if child?.isRunning == true { child?.terminate() }
        process = nil; input = nil; output = nil; buffer.removeAll()
        for id in Array(pending.keys) { finish(id, result: .failure(ReadingError.disconnected)) }
    }
}
