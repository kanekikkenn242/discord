import Foundation
import AVFoundation
import Network
import UIKit
import BackgroundTasks
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
/// Three layers, strongest first: a continued-processing task whose system
/// banner also carries the PIN (iOS 26+), the normal background grace period,
/// and a silent audio loop, which keeps a `UIBackgroundModes: audio` app alive
/// for as long as pairing is in progress.
final class PairingKeepAlive {
    static let shared = PairingKeepAlive()

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var audioRunning = false

    private var grace: UIBackgroundTaskIdentifier = .invalid
    private var continued: AnyObject?
    private var registeredIdentifier: String?
    private var started = false

    // MARK: Lifecycle

    func begin() {
        started = true
        requestNotificationPermission()
        startAudio()
        beginGrace()
        if #available(iOS 26.0, *) { submitContinued() }
    }

    func finish(success: Bool) {
        guard started else { return }
        started = false
        if #available(iOS 26.0, *) { endContinued(success: success) }
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
        if #available(iOS 26.0, *) { endContinued(success: false) }
        endGrace()
        stopAudio()
    }

    // MARK: PIN

    /// Puts the code where the user can read it while in Settings: on the
    /// continued-processing banner, and as a notification once the app is gone
    /// from the foreground.
    func showPin(_ pin: String, hostName: String) {
        if #available(iOS 26.0, *), let task = continued as? BGContinuedProcessingTask {
            task.updateTitle("Pairing code \(pin)", subtitle: "Enter it on this iPhone to pair with \(hostName)")
            task.progress.completedUnitCount = 1
        }
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

    // MARK: Continued processing (iOS 26+)

    @available(iOS 26.0, *)
    private func submitContinued() {
        guard let identifier = continuedTaskIdentifier() else {
            log("pairing: no BGTaskSchedulerPermittedIdentifiers entry — relying on audio keep-alive", level: .warning)
            return
        }

        if registeredIdentifier != identifier {
            let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
                guard let self, let task = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                self.attach(task)
            }
            guard registered else {
                log("pairing: continued task \(identifier) was refused", level: .warning)
                return
            }
            registeredIdentifier = identifier
        }

        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: "Pairing with this iPhone",
            subtitle: "Settings › Privacy & Security › Developer Mode"
        )
        // Queue would start the banner long after the user has paired; fail is
        // what we want when the slot is not free.
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            log("pairing: continued task unavailable (\(error.localizedDescription)) — audio keep-alive only", level: .warning)
        }
    }

    @available(iOS 26.0, *)
    private func attach(_ task: BGContinuedProcessingTask) {
        guard started else {
            task.setTaskCompleted(success: false)
            return
        }
        continued = task
        task.progress.totalUnitCount = 2
        task.progress.completedUnitCount = 0
        task.expirationHandler = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                log("pairing: iOS ended the continued task", level: .warning)
                self.continued = nil
            }
        }
    }

    @available(iOS 26.0, *)
    private func endContinued(success: Bool) {
        guard let task = continued as? BGContinuedProcessingTask else { return }
        task.expirationHandler = nil
        task.progress.completedUnitCount = task.progress.totalUnitCount
        task.setTaskCompleted(success: success)
        continued = nil
    }

    private func continuedTaskIdentifier() -> String? {
        let bundle = Bundle.main.bundleIdentifier ?? AppInfo.bundleID
        let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        if let wildcard = permitted.first(where: { $0.hasPrefix(bundle) && $0.hasSuffix(".*") }) {
            return String(wildcard.dropLast()) + "session"
        }
        return permitted.first { $0.hasPrefix(bundle) }
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
