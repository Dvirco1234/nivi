import AudioToolbox
import CoreAudio
import NiviCore

/// Turns the Mac's output volume down while a recording runs, and puts it back after.
///
/// Why this exists: a system sound, a notification or music playing out of the speakers
/// gets picked up by the microphone and ends up in the transcript.
///
/// This changes something that belongs to the user, so the old volume is written to
/// `volumeBeforeMute` **before** anything is muted. If the app is killed mid-recording,
/// the next launch reads that value and puts the volume back. Without it a crash would
/// leave the Mac silent with no explanation.
///
/// CoreAudio is used rather than `osascript`, which spawns a process and takes hundreds
/// of milliseconds at the exact moment the user is waiting to start speaking.
enum SystemVolume {

    /// Stored instead of a real volume when the output device has no volume slider we can
    /// move (some HDMI and aggregate devices). It means "the mute switch was used, so
    /// unmute on restore" and is out of the 0 to 1 range on purpose.
    private static let usedMuteSwitch: Double = 2

    // MARK: - What the app calls

    /// Saves the current volume, then silences the output. Safe to call when there is
    /// nothing to mute: it just does nothing.
    static func muteForRecording() {
        let settings = Settings()
        guard settings.volumeBeforeMute < 0 else { return }   // already muted by us
        guard let device = defaultOutputDevice() else { return }
        if let volume = volume(of: device) {
            guard volume > 0 else { return }   // already silent, nothing to put back
            settings.volumeBeforeMute = Double(volume)
            guard setVolume(0, on: device) else { return }
        } else if let muted = isMuted(device), !muted {
            settings.volumeBeforeMute = usedMuteSwitch
            guard setMuted(true, on: device) else { return }
        } else {
            return
        }
        Log.info("Muted the output while recording")
    }

    /// Puts the volume back to whatever was saved, and forgets it.
    static func restoreAfterRecording() {
        let settings = Settings()
        let saved = settings.volumeBeforeMute
        guard saved >= 0 else { return }
        settings.volumeBeforeMute = -1
        guard let device = defaultOutputDevice() else { return }
        if saved == usedMuteSwitch {
            _ = setMuted(false, on: device)
        } else {
            _ = setVolume(Float(saved), on: device)
        }
        Log.info("Put the output volume back")
    }

    /// Called once at launch. A saved volume here means the app went away mid-recording,
    /// so the user is sitting in front of a Mac we muted and never unmuted.
    static func restoreAfterCrash() {
        guard Settings().volumeBeforeMute >= 0 else { return }
        Log.info("Found a volume saved from a recording that never finished — putting it back")
        restoreAfterRecording()
    }

    // MARK: - CoreAudio

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &address, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }

    /// The single slider the Sound settings show, whatever channels the device really has.
    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    private static func volume(of device: AudioDeviceID) -> Float? {
        var address = volumeAddress
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    @discardableResult
    private static func setVolume(_ value: Float, on device: AudioDeviceID) -> Bool {
        var address = volumeAddress
        var new = Float32(min(1, max(0, value)))
        let status = AudioObjectSetPropertyData(device, &address, 0, nil,
                                                UInt32(MemoryLayout<Float32>.size), &new)
        if status != noErr { Log.error("Could not set the output volume (status \(status))") }
        return status == noErr
    }

    private static func isMuted(_ device: AudioDeviceID) -> Bool? {
        var address = muteAddress
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value != 0
    }

    @discardableResult
    private static func setMuted(_ muted: Bool, on device: AudioDeviceID) -> Bool {
        var address = muteAddress
        var value = UInt32(muted ? 1 : 0)
        let status = AudioObjectSetPropertyData(device, &address, 0, nil,
                                                UInt32(MemoryLayout<UInt32>.size), &value)
        return status == noErr
    }
}
