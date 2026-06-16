import Foundation

final class CodexAppServerClient {
    typealias StateHandler = (QuotaDisplayState) -> Void

    private let executableURL = URL(
        fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"
    )
    private let queue = DispatchQueue(label: "com.maidongdong.CodexQuotaBar.app-server")
    private let onState: StateHandler

    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputBuffer = Data()
    private var pollTimer: DispatchSourceTimer?
    private var reconnectWorkItem: DispatchWorkItem?
    private var accountChangeWorkItem: DispatchWorkItem?
    private var stopped = false
    private var initialized = false
    private var nextRequestID = 2
    private var rateLimitRequestIDs = Set<Int>()
    private var requestTimeoutWorkItems = [Int: DispatchWorkItem]()

    init(onState: @escaping StateHandler) {
        self.onState = onState
    }

    func start() {
        queue.async {
            self.stopped = false
            self.startProcess()
        }
    }

    func stop() {
        queue.async {
            self.stopped = true
            self.reconnectWorkItem?.cancel()
            self.reconnectWorkItem = nil
            self.accountChangeWorkItem?.cancel()
            self.accountChangeWorkItem = nil
            self.pollTimer?.cancel()
            self.pollTimer = nil
            self.closeProcess()
        }
    }

    func refresh() {
        queue.async {
            self.requestRateLimits()
        }
    }

    private func startProcess() {
        guard !stopped, process == nil else {
            return
        }

        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            publishError("未找到 Codex app-server")
            scheduleReconnect()
            return
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputBuffer.removeAll(keepingCapacity: true)
        initialized = false
        clearPendingRateLimitRequests()
        inputHandle = inputPipe.fileHandleForWriting
        self.process = process

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            self?.queue.async {
                self?.consume(data)
            }
        }

        // Drain stderr so verbose app-server logging cannot block the process.
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        process.terminationHandler = { [weak self] _ in
            self?.queue.async {
                guard let self else {
                    return
                }
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                self.process = nil
                self.inputHandle = nil
                self.initialized = false
                self.clearPendingRateLimitRequests()
                self.pollTimer?.cancel()
                self.pollTimer = nil

                if !self.stopped {
                    self.publishError("Codex app-server 已断开，正在重连…")
                    self.scheduleReconnect()
                }
            }
        }

        do {
            try process.run()
            send(
                id: 1,
                method: "initialize",
                params: [
                    "clientInfo": [
                        "name": "CodexQuotaBar",
                        "title": "Codex 额度栏",
                        "version": "1.1.2"
                    ],
                    "capabilities": [
                        "experimentalApi": true
                    ]
                ]
            )
        } catch {
            self.process = nil
            inputHandle = nil
            publishError("无法启动 Codex app-server：\(error.localizedDescription)")
            scheduleReconnect()
        }
    }

    private func closeProcess() {
        guard let process else {
            return
        }

        process.terminationHandler = nil
        inputHandle?.closeFile()
        if process.isRunning {
            process.terminate()
        }
        self.process = nil
        inputHandle = nil
        initialized = false
        clearPendingRateLimitRequests()
    }

    private func restartProcess(status: String) {
        publish(.pending(status))
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        pollTimer?.cancel()
        pollTimer = nil
        closeProcess()
        startProcess()
    }

    private func scheduleReconnect() {
        guard !stopped else {
            return
        }

        reconnectWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.startProcess()
        }
        reconnectWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 3, execute: workItem)
    }

    private func startPolling() {
        pollTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 15, repeating: 15, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            self?.requestRateLimits()
        }
        timer.resume()
        pollTimer = timer
    }

    private func requestRateLimits() {
        guard initialized else {
            return
        }

        let id = nextRequestID
        nextRequestID += 1
        rateLimitRequestIDs.insert(id)
        scheduleRateLimitTimeout(for: id)
        send(id: id, method: "account/rateLimits/read", params: nil)
    }

    private func scheduleRateLimitTimeout(for id: Int) {
        requestTimeoutWorkItems[id]?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.handleRateLimitTimeout(id: id)
        }
        requestTimeoutWorkItems[id] = workItem
        queue.asyncAfter(deadline: .now() + 8, execute: workItem)
    }

    private func handleRateLimitTimeout(id: Int) {
        guard rateLimitRequestIDs.remove(id) != nil else {
            return
        }

        requestTimeoutWorkItems.removeValue(forKey: id)
        restartProcess(status: "读取额度超时，正在重连…")
    }

    private func clearPendingRateLimitRequests() {
        for workItem in requestTimeoutWorkItems.values {
            workItem.cancel()
        }
        requestTimeoutWorkItems.removeAll()
        rateLimitRequestIDs.removeAll()
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        let newline = Data([0x0A])

        while let range = outputBuffer.range(of: newline) {
            let line = outputBuffer.subdata(in: outputBuffer.startIndex..<range.lowerBound)
            outputBuffer.removeSubrange(outputBuffer.startIndex...range.lowerBound)
            handleLine(line)
        }
    }

    private func handleLine(_ data: Data) {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data),
              let message = object as? [String: Any] else {
            return
        }

        if let id = message["id"] as? Int {
            if id == 1, message["result"] != nil {
                initialized = true
                sendNotification(method: "initialized")
                requestRateLimits()
                startPolling()
                return
            }

            if rateLimitRequestIDs.remove(id) != nil {
                requestTimeoutWorkItems.removeValue(forKey: id)?.cancel()
                if let result = message["result"] {
                    decodeAndPublish(result)
                } else if let error = message["error"] as? [String: Any] {
                    let detail = error["message"] as? String ?? "未知错误"
                    publishError("读取额度失败：\(detail)")
                }
                return
            }
        }

        guard let method = message["method"] as? String else {
            return
        }

        switch method {
        case "account/rateLimits/updated":
            // Rolling updates are sparse. Refetch the full snapshot to avoid
            // accidentally clearing fields omitted by the notification.
            requestRateLimits()
        case "account/updated", "account/login/completed":
            handleAccountChanged()
        default:
            break
        }
    }

    private func handleAccountChanged() {
        accountChangeWorkItem?.cancel()
        publish(.pending("账号已切换，正在刷新额度…"))

        let workItem = DispatchWorkItem { [weak self] in
            self?.restartProcess(status: "账号已切换，正在刷新额度…")
        }
        accountChangeWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func decodeAndPublish(_ object: Any) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let result = try? JSONDecoder().decode(RateLimitsResult.self, from: data) else {
            publishError("Codex 返回了无法识别的额度数据")
            return
        }

        publish(QuotaDisplayState(snapshot: result.rateLimits))
    }

    private func send(id: Int, method: String, params: Any?) {
        var message: [String: Any] = [
            "id": id,
            "method": method
        ]
        if let params {
            message["params"] = params
        }
        write(message)
    }

    private func sendNotification(method: String) {
        write(["method": method])
    }

    private func write(_ message: [String: Any]) {
        guard let inputHandle,
              JSONSerialization.isValidJSONObject(message),
              var data = try? JSONSerialization.data(withJSONObject: message) else {
            return
        }

        data.append(0x0A)
        do {
            try inputHandle.write(contentsOf: data)
        } catch {
            publishError("向 Codex app-server 发送请求失败")
        }
    }

    private func publishError(_ message: String) {
        publish(.pending(message))
    }

    private func publish(_ state: QuotaDisplayState) {
        DispatchQueue.main.async {
            self.onState(state)
        }
    }
}
