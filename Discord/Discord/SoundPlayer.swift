import Foundation
import AVFoundation

/// Plays the three cues recovered from the X bundle. The splash jingle is
/// gated by the music preference; the apply/restore cues are short feedback
/// sounds tied to an explicit user action and always play.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    private var welcomePlayer: AVAudioPlayer?
    private var effectPlayers: [AVAudioPlayer] = []

    private init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            playWelcome()
        } else {
            welcomePlayer?.stop()
            welcomePlayer = nil
        }
    }

    func playEffect(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.volume = 0.8
        player.play()
        effectPlayers.append(player)
        if effectPlayers.count > 4 {
            effectPlayers.removeFirst(effectPlayers.count - 4)
        }
    }

    private func playWelcome() {
        guard welcomePlayer == nil else { return }
        guard let url = Bundle.main.url(forResource: "Welcome", withExtension: "wav") else { return }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.volume = 0.6
        player.play()
        welcomePlayer = player
    }
}
