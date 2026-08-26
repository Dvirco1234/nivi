import AppKit

/// System sound cues for recording start/stop (played only when the setting is on).
enum SoundPlayer {
    private static let start = NSSound(contentsOfFile: "/System/Library/Sounds/Blow.aiff", byReference: true)
    private static let stop = NSSound(contentsOfFile: "/System/Library/Sounds/Frog.aiff", byReference: true)

    static func playStart() { start?.stop(); start?.play() }
    static func playStop() { stop?.stop(); stop?.play() }
}
