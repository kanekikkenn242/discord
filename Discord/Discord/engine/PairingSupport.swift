import Foundation
import AVFoundation
import Network
import UIKit
import UserNotifications

// MARK: - Local Network permission

/// iOS grants Local Network access per app, and Bonjour is blocked until it is
/// granted. Publishing a service without ever browsing one can leave the app
/// in the "not determined" state, where `NetService.publish()` fails silently
/// and the iPhone lists nothing in Developer Mode.
///
/// Mirroring a throwaway service with both a listener and a browser forces the
/// decision, and finishes quickly either way so the pairing host still starts.
final class LocalNetworkAuthorization {
    private var browser: NWBrowser?
    private var listener: NWListener?
    private var completion: ((Bool) -> Void)?
    private var finished = true

    /// Must also appear in `NSBonjourServices`.
    private let probeType = "_aircardprobe._tcp"

    func request(timeout: TimeInterval = 1.5, completion: @escaping (Bool) -> Void) {
        cancelProbe()
        self.completion = completion
        finished = false

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let listener = try? NWListener(using: parameters)
        listener?.service = NWListener.Service(name: "DiscordProbe", type: probeType)
        listener?.newConnectionHandler = { connection in connection.cancel() }
        listener?.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.finish(false) }
        }
        self.listener = listener

        let browser = NWBrowser(for: .bonjour(type: probeType, domain: nil), using: parameters)
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.finish(false) }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            if !results.isEmpty { self?.finish(true) }
        }
        self.browser = browser

        listener?.start(queue: .main)
        browser.start(queue: .main)

        // Never stall the pairing flow: a dismissed or already-answered prompt
        // still lets `NetService.publish()` report its own failure.
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish(true)
        }
    }

    private func finish(_ authorized: Bool) {
        guard !finished else { return }
        finished = true
        browser?.cancel()
        browser = nil
        listener?.cancel()
        listener = nil
        let block = completion
        completion = nil
        block?(authorized)
    }

    private func cancelProbe() {
        browser?.cancel()
        browser = nil
        listener?.cancel()
        listener = nil
        completion = nil
        finished = true
    }
}

// MARK: - Keep-alive

/// The user has to leave the app to approve the PIN in Settings, so the pairing
/// host has to survive being backgrounded or it is suspended, its Bonjour
/// advertisement is withdrawn, and the phone can never connect.
///
/// This version uses the APIs available to the iOS 18.5 SDK. The normal
/// background grace period and silent audio keep-alive remain active while
/// pairing is in progress.
final class PairingKeepAlive {
    static let shared = PairingKeepAlive()

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var audioRunning = false

    private var grace: UIBackgroundTaskIdentifier = .invalid
    private var started = false

    // MARK: Lifecycle

    func begin() {
        started = true
        requestNotificationPermission()
        startAudio()
        beginGrace()
    }

    func finish(success: Bool) {
        guard started else { return }
        started = false
        endGrace()
        // Give iOS a moment to hand control back before dropping the audio
        // session, otherwise the app can be suspended on the way out of Settings.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, !self.started else { return }
            self.stopAudio()
        }
    }

    func cancel() {
        started = false
        endGrace()
        stopAudio()
    }

    // MARK: PIN

    /// Puts the code where the user can read it once the app is in the
    /// background. It is also retained in the app UI.
    func showPin(_ pin: String, hostName: String) {
        guard UIApplication.shared.applicationState != .active else { return }
        notify(title: "Pairing code \(pin)", body: "Enter this code in Settings › Privacy & Security › Developer Mode.")
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "discord.pairing.\(UUID().uuidString)", content: content, trigger: nil)
        )
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                log("pairing: notification permission failed: \(error.localizedDescription)", level: .warning)
            } else if !granted {
                log("pairing: notifications are off — the PIN stays in the app only", level: .warning)
            }
        }
    }

    // MARK: Audio

    private func startAudio() {
        guard !audioRunning else { return }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let format = engine.outputNode.inputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { return }

            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)

            let frames = AVAudioFrameCount(max(1024, format.sampleRate))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
            buffer.frameLength = frames
            if let channels = buffer.floatChannelData {
                for index in 0..<Int(format.channelCount) {
                    memset(channels[index], 0, Int(frames) * MemoryLayout<Float>.size)
                }
            }

            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play()

            self.engine = engine
            self.player = player
            audioRunning = true
            log("pairing: background audio keep-alive started", level: .trace)
        } catch {
            log("pairing: keep-alive audio unavailable: \(error.localizedDescription)", level: .warning)
        }
    }

    private func stopAudio() {
        guard audioRunning else { return }
        audioRunning = false
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: Background grace

    private func beginGrace() {
        guard grace == .invalid else { return }
        grace = UIApplication.shared.beginBackgroundTask(withName: "discord-pairing") { [weak self] in
            self?.endGrace()
        }
    }

    private func endGrace() {
        guard grace != .invalid else { return }
        UIApplication.shared.endBackgroundTask(grace)
        grace = .invalid
    }
}
