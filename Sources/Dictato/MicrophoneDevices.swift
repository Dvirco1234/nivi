import AudioToolbox
import CoreAudio
import DictatoCore

/// One microphone the Mac can record from.
struct MicrophoneDevice: Identifiable, Equatable {
    /// The device's unique id. This is what the priority list stores.
    let id: String
    let name: String
    let audioDeviceID: AudioDeviceID
}

/// Lists the microphones and works out which one Dictato should record from.
///
/// CoreAudio is used rather than `AVCaptureDevice`, for one reason: binding the recording
/// engine to a device needs its `AudioDeviceID`, which only CoreAudio hands out. Asking
/// two frameworks the same question and matching the answers up would be more code and
/// one more thing to get out of step.
enum MicrophoneDevices {

    /// Names of devices seen since the app started, kept so a microphone that is
    /// unplugged while Preferences is open keeps its name in the list instead of turning
    /// back into a bare id. Only device ids are saved to disk, so this is all the app can
    /// know about a device it has not met this session.
    private(set) static var knownNames: [String: String] = [:]

    /// The name to show for a device id, which may not be plugged in.
    static func name(for id: String) -> String { knownNames[id] ?? id }

    /// Every device that is plugged in right now and has at least one input channel.
    static func available() -> [MicrophoneDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        var ids = [AudioDeviceID](repeating: 0,
                                  count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return ids.compactMap { id in
            guard inputChannels(of: id) > 0,
                  let uid = stringProperty(kAudioDevicePropertyDeviceUID, of: id) else { return nil }
            let name = stringProperty(kAudioObjectPropertyName, of: id) ?? uid
            knownNames[uid] = name
            return MicrophoneDevice(id: uid, name: name, audioDeviceID: id)
        }
    }

    /// The device the next recording will use: the first one on the user's list that is
    /// plugged in. Nil means "let the system pick", which is what the app did before this
    /// setting existed.
    static func preferred() -> MicrophoneDevice? {
        let order = MicrophonePriority.decode(json: Settings().microphonePriority)
        guard !order.isEmpty else { return nil }
        let devices = available()
        guard let uid = MicrophonePriority.firstAvailable(order: order,
                                                          available: devices.map(\.id)) else {
            return nil
        }
        return devices.first { $0.id == uid }
    }

    /// The system's own default input, used for the green dot when the user's list has
    /// nothing to say.
    static func systemDefault() -> MicrophoneDevice? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &device) == noErr,
              device != 0,
              let uid = stringProperty(kAudioDevicePropertyDeviceUID, of: device) else { return nil }
        let name = stringProperty(kAudioObjectPropertyName, of: device) ?? uid
        return MicrophoneDevice(id: uid, name: name, audioDeviceID: device)
    }

    // MARK: - Reading one device

    private static func inputChannels(of device: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size > 0 else { return 0 }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer) == noErr else {
            return 0
        }
        let list = buffer.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector,
                                       of device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { return nil }
        return value as String?
    }
}
