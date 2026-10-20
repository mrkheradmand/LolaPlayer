import Foundation
import MediaPlayer

/// Public macOS Now Playing integration. No global event taps or key interception.
final class SystemMediaControls: NSObject {
    private weak var model: PlayerModel?
    private let center = MPRemoteCommandCenter.shared()
    private let info = MPNowPlayingInfoCenter.default()
    private var registered: [MPRemoteCommand] = []
    private var connected = true
    private var published = false
    private var lastUpdate = Date.distantPast
    private var lastState: MPNowPlayingPlaybackState = .unknown
    private var lastID: UUID?

    init(model: PlayerModel) {
        self.model = model
        super.init()
        register(center.playCommand, #selector(play(_:)))
        register(center.pauseCommand, #selector(pause(_:)))
        register(center.togglePlayPauseCommand, #selector(toggle(_:)))
        register(center.previousTrackCommand, #selector(previous(_:)))
        register(center.nextTrackCommand, #selector(next(_:)))
    }

    private func register(_ command: MPRemoteCommand, _ action: Selector) {
        command.isEnabled = false
        command.addTarget(self, action: action)
        registered.append(command)
    }

    func update(force: Bool = false) {
        guard connected, let model else { return }
        let available = model.loaded && !model.failed
        guard available, let record = model.current else {
            for command in registered { command.isEnabled = false }
            if published {
                info.playbackState = .stopped; info.nowPlayingInfo = nil; published = false
            }
            lastID = nil; lastState = .stopped
            return
        }
        let state: MPNowPlayingPlaybackState = model.ended ? .stopped : (model.paused || model.buffering ? .paused : .playing)
        guard force || lastState != state || lastID != record.id || Date().timeIntervalSince(lastUpdate) >= 1 else { return }
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = model.adjacentID(-1) != nil
        center.nextTrackCommand.isEnabled = model.adjacentID(1) != nil
        let hasVideo = model.tracks.contains { $0["type"] as? String == "video" }
        info.nowPlayingInfo = [
            MPMediaItemPropertyTitle: record.name,
            MPMediaItemPropertyPlaybackDuration: model.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: model.position,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? model.speed : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: model.speed,
            MPNowPlayingInfoPropertyMediaType: (hasVideo ? MPNowPlayingInfoMediaType.video : .audio).rawValue
        ]
        if lastState != state || !published { info.playbackState = state }
        lastState = state; lastID = record.id; lastUpdate = Date(); published = true
    }

    private nonisolated enum Action: Sendable { case play, pause, toggle, previous, next }

    // The system may deliver command callbacks off the main thread. Only enqueue UI work.
    private nonisolated func dispatch(_ action: Action) -> MPRemoteCommandHandlerStatus {
        Task { @MainActor [weak self] in
            guard let self, self.connected, let model = self.model, model.loaded, !model.failed else { return }
            switch action {
            case .play: model.setPaused(false)
            case .pause: model.setPaused(true)
            case .toggle: model.togglePlayback()
            case .previous: model.adjacent(-1)
            case .next: model.adjacent(1)
            }
            self.update(force: true)
        }
        return .success
    }
    @objc private nonisolated func play(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus { dispatch(.play) }
    @objc private nonisolated func pause(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus { dispatch(.pause) }
    @objc private nonisolated func toggle(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus { dispatch(.toggle) }
    @objc private nonisolated func previous(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus { dispatch(.previous) }
    @objc private nonisolated func next(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus { dispatch(.next) }

    func stop() {
        guard connected else { return }; connected = false
        for command in registered { command.removeTarget(self); command.isEnabled = false }
        registered = []
        if published { info.playbackState = .stopped; info.nowPlayingInfo = nil; published = false }
    }
}
