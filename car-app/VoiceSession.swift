import Foundation
import SwiftUI
import UIKit
import Combine
import AVFoundation

enum PTTState: Equatable {
    case idle
    case requestingFloor
    case transmitting
    case receiving
    case blockedBusy
    case reconnecting
}

enum VoiceConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting
}

enum VoiceSessionEvent {
    case connectionStateChanged(VoiceConnectionState)
    case pttStateChanged(PTTState)
    case speakerChanged(String?)
    case message(String)
    case error(String)
}

enum VoiceCodec: String {
    case opus
}

struct VoiceFormat {
    let codec: VoiceCodec
    let sampleRateHz: Int
    let channels: Int
    let frameDurationMs: Int
    let targetBitrateBps: Int

    static let speechDefault = VoiceFormat(
        codec: .opus,
        sampleRateHz: 16_000,
        channels: 1,
        frameDurationMs: 20,
        targetBitrateBps: 20_000
    )

    func asDictionary() -> [String: Any] {
        [
            "codec": codec.rawValue,
            "sampleRateHz": sampleRateHz,
            "channels": channels,
            "frameDurationMs": frameDurationMs,
            "targetBitrateBps": targetBitrateBps
        ]
    }
}

actor RelayVoiceSession {
    private let convoyService: ConvoyService
    private let urlSession: URLSession

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?

    private var heartbeatAckMisses = 0
    private var stableConnectedAt: Date?
    private var backoffSeconds: TimeInterval = 1

    private var convoyId: UUID?
    private var relayToken: String?
    private var relayURL: URL?
    private let voiceFormat: VoiceFormat

    private var pttState: PTTState = .idle
    private var connectionState: VoiceConnectionState = .disconnected
    private var onEvent: (@Sendable (VoiceSessionEvent) -> Void)?
    
    private var micCapture: MicCapture?
    private var isCapturing = false
    private var speakerPlayback: SpeakerPlayback?
    private var presenceListening = false
    private var presenceMuted = false
    private var lastAudioReceivedAt: Date?
    private var lastPresenceUpdateAt: Date?
    private var lastPresenceErrorAt: Date?

    private func log(_ message: String) {
        #if DEBUG
        print("[VOICE] \(message)")
        #endif
    }

    init(
        convoyService: ConvoyService,
        urlSession: URLSession = .shared,
        voiceFormat: VoiceFormat = .speechDefault
    ) {
        self.convoyService = convoyService
        self.urlSession = urlSession
        self.voiceFormat = voiceFormat
    }

    func setEventHandler(_ handler: (@Sendable (VoiceSessionEvent) -> Void)?) {
        self.onEvent = handler
        log("event handler set")
    }

    func connect(convoyId: UUID) async {
        log("connect requested for convoyId=\(convoyId.uuidString)")
        self.convoyId = convoyId
        updateConnectionState(.connecting)
        log("state -> connecting")

        do {
            let deviceUUID = await MainActor.run {
                UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            }
            let connectResponse = try await convoyService.connectRelay(convoyId: convoyId, deviceUUID: deviceUUID)
            let wsURL = buildWebSocketURL(from: connectResponse)
            relayToken = connectResponse.relayToken
            relayURL = wsURL
            log("relay connect OK, url=\(wsURL.absoluteString)")
            try await openSocket(url: wsURL, relayToken: connectResponse.relayToken)
        } catch {
            log("connect failed: \(error.localizedDescription)")
            reportError(error.localizedDescription)
            await scheduleReconnect()
        }
    }

    func disconnect() async {
        log("disconnect requested")
        stopCaptureIfNeeded()
        stopPlaybackIfNeeded()
        deactivateAudioSession()
        await updatePresence(listening: false, muted: false, lastAudioReceived: nil)
        reconnectTask?.cancel()
        heartbeatTask?.cancel()
        receiveTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        heartbeatAckMisses = 0
        pttState = .idle
        connectionState = .disconnected
        convoyId = nil
        emit(.connectionStateChanged(.disconnected))
        emit(.pttStateChanged(.idle))
        log("state -> disconnected, ptt -> idle")
    }

    func requestFloor() async {
        log("ptt requestFloor called (conn=\(connectionState), ptt=\(pttState))")
        guard connectionState == .connected, pttState == .idle else { return }
        pttState = .requestingFloor
        log("ptt -> requestingFloor")
        emit(.pttStateChanged(.requestingFloor))
        await sendJSON([
            "type": "ptt_request",
            "voiceFormat": voiceFormat.asDictionary()
        ])
    }

    func releaseFloor() async {
        log("ptt releaseFloor called (conn=\(connectionState), ptt=\(pttState))")
        guard connectionState == .connected, pttState == .transmitting else { return }
        await sendJSON(["type": "ptt_end"])
        stopCaptureIfNeeded()
        pttState = .idle
        log("ptt -> idle (released)")
        emit(.pttStateChanged(.idle))
    }

    func sendAudioFrame(_ data: Data) async {
        log("sendAudioFrame bytes=\(data.count) (conn=\(connectionState), ptt=\(pttState))")
        guard connectionState == .connected, pttState == .transmitting else {
            return
        }

        guard let socket = webSocketTask else { return }
        do {
            try await socket.send(.data(data))
        } catch {
            reportError("Audio send failed: \(error.localizedDescription)")
            await forceReconnect()
        }
    }

    private func openSocket(url: URL, relayToken: String) async throws {
        log("opening socket: \(url.absoluteString)")
        let socket = urlSession.webSocketTask(with: url)
        webSocketTask = socket
        socket.resume()

        receiveTask?.cancel()
        receiveTask = Task {
            await receiveLoop()
        }
        log("socket receive loop started")

        log("sending auth")
        await sendJSON([
            "type": "auth",
            "relayToken": relayToken,
            "voiceFormat": voiceFormat.asDictionary()
        ])
    }

    private func receiveLoop() async {
        guard let socket = webSocketTask else { return }

        while !Task.isCancelled {
            do {
                let message = try await socket.receive()
                switch message {
                case .string(let text):
                    log("recv text: \(text)")
                    await handleTextMessage(text)
                case .data(let data):
                    await handleAudioData(data)
                @unknown default:
                    break
                }
            } catch {
                log("socket receive error: \(error.localizedDescription)")
                reportError("Socket receive failed: \(error.localizedDescription)")
                await scheduleReconnect()
                return
            }
        }
    }

    private func handleTextMessage(_ text: String) async {
        log("handle message")
        emit(.message(text))

        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return
        }
        log("type=\(type)")

        switch type {
        case "auth_ok":
            log("auth_ok; state -> connected; ptt -> idle")
            stableConnectedAt = Date()
            backoffSeconds = 1
            heartbeatAckMisses = 0
            updateConnectionState(.connected)
            pttState = .idle
            emit(.pttStateChanged(.idle))
            startPlaybackIfNeeded()
            await updatePresence(listening: true, muted: false, lastAudioReceived: nil)
            startHeartbeat()

        case "heartbeat_ack":
            log("heartbeat_ack")
            heartbeatAckMisses = 0

        case "ptt_granted":
            log("ptt_granted; ptt -> transmitting")
            pttState = .transmitting
            emit(.pttStateChanged(.transmitting))
            startCaptureIfNeeded()

        case "ptt_denied_busy":
            log("ptt_denied_busy; ptt -> blockedBusy")
            pttState = .blockedBusy
            emit(.pttStateChanged(.blockedBusy))

            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self.resetBusyStateIfNeeded()
            }

        case "incoming_transmission":
            let speaker = object["speaker"] as? String ?? object["speakerId"] as? String
            log("incoming_transmission speaker=\(speaker ?? "nil")")
            pttState = .receiving
            emit(.pttStateChanged(.receiving))
            emit(.speakerChanged(speaker))

        case "transmission_end":
            log("transmission_end")
            if pttState != .transmitting {
                pttState = .idle
                emit(.pttStateChanged(.idle))
            }
            stopCaptureIfNeeded()
            emit(.speakerChanged(nil))

        case "auth_failed":
            log("auth_failed")
            reportError("Relay auth failed.")
            await scheduleReconnect()

        default:
            break
        }
    }

    private func handleAudioData(_ data: Data) async {
        guard !data.isEmpty else { return }
        startPlaybackIfNeeded()
        speakerPlayback?.enqueue(data)
        let now = Date()
        lastAudioReceivedAt = now
        await updatePresence(listening: true, muted: false, lastAudioReceived: now)
    }

    private func resetBusyStateIfNeeded() {
        guard pttState == .blockedBusy else { return }
        log("reset busy -> idle")
        pttState = .idle
        emit(.pttStateChanged(.idle))
    }
    
    private func startCaptureIfNeeded() {
        guard !isCapturing else { return }
        let capture = MicCapture(sampleRate: voiceFormat.sampleRateHz, channels: voiceFormat.channels)
        micCapture = capture
        do {
            try capture.start { [weak self] frame in
                Task { [weak self] in
                    await self?.sendAudioFrame(frame)
                }
            }
            isCapturing = true
            log("mic capture started")
        } catch {
            log("mic capture failed to start: \(error.localizedDescription)")
        }
    }

    private func stopCaptureIfNeeded() {
        guard isCapturing else { return }
        micCapture?.stop()
        micCapture = nil
        isCapturing = false
        log("mic capture stopped")
    }

    private func startPlaybackIfNeeded() {
        if speakerPlayback == nil {
            speakerPlayback = SpeakerPlayback(sampleRate: voiceFormat.sampleRateHz, channels: voiceFormat.channels)
        }

        do {
            try speakerPlayback?.start()
        } catch {
            log("speaker playback failed to start: \(error.localizedDescription)")
            reportError("Speaker playback failed to start: \(error.localizedDescription)")
        }
    }

    private func stopPlaybackIfNeeded() {
        speakerPlayback?.stop()
        speakerPlayback = nil
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            log("audio session deactivate failed: \(error.localizedDescription)")
        }
    }

    private func startHeartbeat() {
        log("heartbeat loop start")
        heartbeatTask?.cancel()
        heartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if Task.isCancelled { return }
                log("send heartbeat")
                await sendJSON(["type": "heartbeat"])
                heartbeatAckMisses += 1
                if heartbeatAckMisses >= 2 {
                    log("heartbeat timeout; forcing reconnect")
                    reportError("Heartbeat timeout. Reconnecting.")
                    await forceReconnect()
                    return
                }
            }
        }
    }

    private func forceReconnect() async {
        log("forceReconnect")
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        heartbeatTask?.cancel()
        receiveTask?.cancel()
        stopCaptureIfNeeded()
        stopPlaybackIfNeeded()
        deactivateAudioSession()
        await scheduleReconnect()
    }

    private func scheduleReconnect() async {
        log("scheduleReconnect (current backoff=\(backoffSeconds)s)")
        guard reconnectTask == nil || reconnectTask?.isCancelled == true else { return }

        updateConnectionState(.reconnecting)
        pttState = .reconnecting
        emit(.pttStateChanged(.reconnecting))

        let delay = backoffWithJitter(base: backoffSeconds)
        backoffSeconds = min(backoffSeconds * 2, 20)

        log("reconnect in ~\(String(format: "%.2f", delay))s")

        reconnectTask = Task {
            defer { Task { await self.clearReconnectTask() } }

            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            let convoyId = await self.currentConvoyId()
            guard !Task.isCancelled, let convoyId else { return }
            await self.connect(convoyId: convoyId)
        }
    }

    private func currentConvoyId() -> UUID? {
        convoyId
    }

    private func clearReconnectTask() {
        reconnectTask = nil
    }

    private func backoffWithJitter(base: TimeInterval) -> TimeInterval {
        let jitter = Double.random(in: 0...(base * 0.25))
        return base + jitter
    }

    private func sendJSON(_ payload: [String: Any]) async {
        guard let socket = webSocketTask else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            guard let text = String(data: data, encoding: .utf8) else { return }
            log("send text: \(text)")
            try await socket.send(.string(text))
        } catch {
            log("socket send error: \(error.localizedDescription)")
            reportError("Socket send failed: \(error.localizedDescription)")
        }
    }

    private func buildWebSocketURL(from response: ConnectRelayResponse) -> URL {
        let host = response.relayHost.hasPrefix("ws") ? response.relayHost : "wss://\(response.relayHost)"
        if let path = response.relayPath, !path.isEmpty,
           var components = URLComponents(string: host) {
            components.path = path.hasPrefix("/") ? path : "/\(path)"
            return components.url ?? URL(string: host)!
        }

        return URL(string: host)!
    }

    private func updateConnectionState(_ state: VoiceConnectionState) {
        connectionState = state
        log("state -> \(state)")
        emit(.connectionStateChanged(state))
    }

    private func updatePresence(listening: Bool? = nil, muted: Bool? = nil, lastAudioReceived: Date? = nil) async {
        if let listening {
            presenceListening = listening
        }
        if let muted {
            presenceMuted = muted
        }
        if let lastAudioReceived {
            lastAudioReceivedAt = lastAudioReceived
        }

        guard let convoyId else { return }
        let now = Date()

        if let lastPresenceUpdateAt,
           now.timeIntervalSince(lastPresenceUpdateAt) < (lastAudioReceived == nil ? 5 : 2) {
            return
        }

        lastPresenceUpdateAt = now

        do {
            try await convoyService.updatePresence(
                convoyId: convoyId,
                listening: presenceListening,
                muted: presenceMuted,
                lastAudioReceived: lastAudioReceivedAt
            )
        } catch {
            log("presence update failed: \(error.localizedDescription)")
            if let lastPresenceErrorAt,
               now.timeIntervalSince(lastPresenceErrorAt) < 10 {
                return
            }
            lastPresenceErrorAt = now
            reportError("Presence update failed: \(error.localizedDescription)")
        }
    }

    private func reportError(_ message: String) {
        log("error: \(message)")
        emit(.error(message))
    }

    private func emit(_ event: VoiceSessionEvent) {
        #if DEBUG
        switch event {
        case .connectionStateChanged(let s): log("emit: connection=\(s)")
        case .pttStateChanged(let s): log("emit: ptt=\(s)")
        case .speakerChanged(let sp): log("emit: speaker=\(sp ?? "nil")")
        case .message(let m): log("emit: message=\(m)")
        case .error(let e): log("emit: error=\(e)")
        }
        #endif
        onEvent?(event)
    }
}

fileprivate final class MicCapture {
    private let engine = AVAudioEngine()
    private let desiredSampleRate: Double
    private let desiredChannels: AVAudioChannelCount

    private var onFrame: ((Data) -> Void)?

    init(sampleRate: Int, channels: Int) {
        self.desiredSampleRate = Double(sampleRate)
        self.desiredChannels = AVAudioChannelCount(max(1, channels))
    }

    func start(onFrame: @escaping (Data) -> Void) throws {
        self.onFrame = onFrame

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setPreferredSampleRate(desiredSampleRate)
        try session.setActive(true, options: [])

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: desiredSampleRate,
            channels: desiredChannels,
            interleaved: true
        )!

        // Install the tap with the hardware format, then convert to the transport format.
        let frameSamples = AVAudioFrameCount((inputFormat.sampleRate * 0.02).rounded())

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: frameSamples, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            if buffer.format.sampleRate != self.desiredSampleRate ||
                buffer.format.channelCount != self.desiredChannels ||
                buffer.format.commonFormat != .pcmFormatInt16 {
                if let converted = self.convert(buffer: buffer, to: outputFormat) {
                    self.emitPCM(buffer: converted)
                }
            } else {
                self.emitPCM(buffer: buffer)
            }
        }

        try engine.start()
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        onFrame = nil
    }

    private func emitPCM(buffer: AVAudioPCMBuffer) {
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        guard let dataPointer = audioBuffer.mData else { return }
        let data = Data(bytes: dataPointer, count: Int(audioBuffer.mDataByteSize))
        onFrame?(data)
    }

    private func convert(buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
        if let error { print("[VOICE] convert error: \(error.localizedDescription)") }
        return outBuffer
    }
}

fileprivate final class SpeakerPlayback {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private var isRunning = false

    init(sampleRate: Int, channels: Int) {
        let desiredChannels = AVAudioChannelCount(max(1, channels))
        self.format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(sampleRate),
            channels: desiredChannels,
            interleaved: true
        )!

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func start() throws {
        guard !isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setPreferredSampleRate(format.sampleRate)
        try session.setActive(true, options: [])

        engine.prepare()
        try engine.start()
        player.play()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        player.stop()
        engine.stop()
        isRunning = false
    }

    func enqueue(_ data: Data) {
        guard isRunning else { return }
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return }
        let frameCount = AVAudioFrameCount(data.count / bytesPerFrame)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return
        }

        buffer.frameLength = frameCount
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        guard let mData = audioBuffer.mData else { return }

        data.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                memcpy(mData, baseAddress, min(Int(audioBuffer.mDataByteSize), data.count))
            }
        }

        player.scheduleBuffer(buffer, completionHandler: nil)
    }
}

@MainActor
final class VoiceStore: ObservableObject {
    @Published var connectionState: VoiceConnectionState = .disconnected
    @Published var pttState: PTTState = .idle
    @Published var currentSpeaker: String?
    @Published var message: String?
    @Published var errorMessage: String?

    private let session: RelayVoiceSession

    private func log(_ message: String) {
        #if DEBUG
        print("[VOICE][STORE] \(message)")
        #endif
    }

    init(session: RelayVoiceSession) {
        self.session = session

        Task { [weak self] in
            await session.setEventHandler { [weak self] event in
                Task { [weak self] in
                    await MainActor.run {
                        self?.consume(event)
                    }
                }
            }
        }
    }

    func connect(convoyId: UUID) {
        Task {
            self.log("connect(convoyId=\(convoyId.uuidString))")
            await session.connect(convoyId: convoyId)
        }
    }

    func disconnect() {
        Task {
            self.log("disconnect()")
            await session.disconnect()
        }
    }

    func pressPTT() {
        Task {
            self.log("pressPTT()")
            await session.requestFloor()
        }
    }

    func releasePTT() {
        Task {
            self.log("releasePTT()")
            await session.releaseFloor()
        }
    }

    private func consume(_ event: VoiceSessionEvent) {
        log("consume: \(event)")
        switch event {
        case .connectionStateChanged(let state):
            connectionState = state
            if state == .connected {
                errorMessage = nil
            }
        case .pttStateChanged(let state):
            pttState = state
        case .speakerChanged(let speaker):
            currentSpeaker = speaker
        case .message(let text):
            message = text
        case .error(let text):
            errorMessage = text
        }
    }
}

extension VoiceStore {
    static func live(convoyService: ConvoyService) -> VoiceStore {
        VoiceStore(session: RelayVoiceSession(convoyService: convoyService))
    }
}
