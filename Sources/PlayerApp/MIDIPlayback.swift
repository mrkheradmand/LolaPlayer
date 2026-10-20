import AVFAudio
import AudioToolbox
import Foundation

/// MIDI is synthesized with macOS's General MIDI instruments; no encoded output is created.
@MainActor final class MIDIPlayback {
    private let audioEngine = AVAudioEngine()
    private let instrument: AVAudioUnitMIDIInstrument
    private let sequencer: AVAudioSequencer
    let duration: Double

    init(url: URL) throws {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice, componentSubType: kAudioUnitSubType_DLSSynth,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        // AVFAudio raises an Objective-C exception, rather than a Swift Error, for a
        // missing component. Check first so unavailable system instruments cannot crash Lola.
        guard AudioComponentFindNext(nil, &description) != nil else {
            throw NSError(domain: "LolaPlayer.MIDI", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The macOS General MIDI synthesizer is unavailable in this environment."
            ])
        }
        instrument = AVAudioUnitMIDIInstrument(audioComponentDescription: description)
        audioEngine.attach(instrument)
        audioEngine.connect(instrument, to: audioEngine.mainMixerNode, format: nil)
        sequencer = AVAudioSequencer(audioEngine: audioEngine)
        try sequencer.load(from: url, options: [])
        for track in sequencer.tracks { track.destinationAudioUnit = instrument }
        duration = sequencer.tracks.map(\.lengthInSeconds).filter(\.isFinite).max() ?? 0
        guard duration > 0 else { throw CocoaError(.fileReadCorruptFile) }
        audioEngine.prepare()
        sequencer.prepareToPlay()
    }

    var position: Double { min(duration, max(0, sequencer.currentPositionInSeconds)) }
    var isPlaying: Bool { sequencer.isPlaying }
    var rate: Double {
        get { Double(sequencer.rate) }
        set { sequencer.rate = Float(newValue) }
    }
    var volume: Double {
        get { Double(audioEngine.mainMixerNode.outputVolume) }
        set { audioEngine.mainMixerNode.outputVolume = Float(newValue) }
    }
    func play() throws {
        if !audioEngine.isRunning { try audioEngine.start() }
        try sequencer.start()
    }
    func pause() {
        sequencer.stop()
        silence()
    }
    func seek(_ seconds: Double) {
        let playing = sequencer.isPlaying
        sequencer.stop(); silence()
        sequencer.currentPositionInSeconds = min(duration, max(0, seconds))
        if playing { try? sequencer.start() }
    }
    private func silence() {
        for channel in UInt8(0)..<16 {
            instrument.sendController(123, withValue: 0, onChannel: channel)
            instrument.sendController(120, withValue: 0, onChannel: channel)
        }
    }
    func shutdown() { pause(); audioEngine.stop() }
}
