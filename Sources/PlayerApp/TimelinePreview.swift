import AppKit
import CMpv
import Observation
import PlayerCore
import SwiftUI

struct ThumbnailFrame: Sendable {
    let pixels: Data
    let width: Int
    let height: Int
    let stride: Int
    let time: Double
}

actor ThumbnailDecoder {
    private let decoder = LPThumbnailDecoder()
    func reset() { decoder.reset() }
    func frame(url: URL, seconds: Double, library: String, exact: Bool = true) -> ThumbnailFrame? {
        guard !Task.isCancelled, url.isFileURL, seconds.isFinite, seconds >= 0,
              let frame = decoder.frame(atPath: url.path, seconds: seconds, library: library, exact: exact),
              !Task.isCancelled,
              let pixels = frame["pixels"] as? Data,
              let width = frame["width"] as? Int, let height = frame["height"] as? Int,
              let stride = frame["stride"] as? Int, let time = frame["time"] as? Double else { return nil }
        return ThumbnailFrame(pixels: pixels, width: width, height: height, stride: stride, time: time)
    }
}

struct ThumbnailRequest: Hashable {
    let url: URL
    let seconds: Double
    let library: String
}

struct ThumbnailSource: Equatable {
    let url: URL
    let duration: Double
    let library: String
}

@Observable final class TimelinePreview {
    var hoverX: CGFloat?
    var image: NSImage?
    var imageTime: Double?
    var represented: ThumbnailRequest?
    var loading = false
    var approximate = false
    @ObservationIgnored private let decoder = ThumbnailDecoder()
    @ObservationIgnored private let warmDecoder = ThumbnailDecoder()
    @ObservationIgnored private var source: ThumbnailSource?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var desired: ThumbnailRequest?
    @ObservationIgnored private var foregroundTask: Task<Void, Never>?
    @ObservationIgnored private var warmTask: Task<Void, Never>?
    private struct CachedFrame {
        let image: NSImage
        let time: Double
        let cost: Int
    }
    @ObservationIgnored private var cache: [Double: CachedFrame] = [:]
    @ObservationIgnored private var order: [Double] = []

    func prepare(_ source: ThumbnailSource) {
        guard self.source?.url != source.url || self.source?.library != source.library else { return }
        clear(); self.source = source
        let generation = generation
        warmTask = Task { [weak self] in
            for time in TimelinePosition.warmupTimes(duration: source.duration) {
                guard let self, !Task.isCancelled, self.generation == generation else { return }
                if let frame = await self.warmDecoder.frame(url: source.url, seconds: time, library: source.library, exact: false),
                   !Task.isCancelled, self.generation == generation {
                    self.store(frame, at: time)
                    if let target = self.desired { self.showCached(for: target) }
                }
                do { try await Task.sleep(for: .milliseconds(35)) } catch { return }
            }
        }
    }

    /// Runs synchronously for pointer and slider changes, so cached images appear in that event.
    func request(_ request: ThumbnailRequest?) {
        represented = request; desired = request
        guard let request else { image = nil; imageTime = nil; loading = false; return }
        showCached(for: request)
        guard !hasExactFrame(request), foregroundTask == nil else { return }
        let generation = generation
        foregroundTask = Task { [weak self] in
            defer { if self?.generation == generation { self?.foregroundTask = nil } }
            while let self, !Task.isCancelled, self.generation == generation, let target = self.desired {
                if self.hasExactFrame(target) { return }
                if let frame = await self.decoder.frame(url: target.url, seconds: target.seconds, library: target.library),
                   !Task.isCancelled, self.generation == generation {
                    self.store(frame, at: target.seconds)
                    if let latest = self.desired { self.showCached(for: latest) }
                } else if self.desired == target { self.loading = false; return }
                if self.desired == target { return }
            }
        }
    }

    private func hasExactFrame(_ request: ThumbnailRequest) -> Bool {
        guard let frame = cache[request.seconds] else { return false }
        return abs(frame.time - request.seconds) < 0.3
    }

    private func showCached(for request: ThumbnailRequest) {
        guard source?.url == request.url else { image = nil; imageTime = nil; loading = true; return }
        let candidate = cache.values.min { abs($0.time - request.seconds) < abs($1.time - request.seconds) }
        image = candidate?.image; imageTime = candidate?.time
        approximate = candidate.map { abs($0.time - request.seconds) >= 0.3 } ?? false
        loading = !hasExactFrame(request)
    }

    private func store(_ frame: ThumbnailFrame, at seconds: Double) {
        guard let provider = CGDataProvider(data: frame.pixels as CFData),
              let cgImage = CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: frame.stride, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return }
        // Do not let an approximate background frame replace a precise interactive result.
        if let old = cache[seconds], abs(old.time - seconds) < abs(frame.time - seconds) { return }
        cache[seconds] = CachedFrame(image: NSImage(cgImage: cgImage, size: NSSize(width: frame.width, height: frame.height)),
            time: frame.time, cost: frame.pixels.count)
        order.removeAll { $0 == seconds }; order.append(seconds)
        while order.count > 128 || cache.values.reduce(0, { $0 + $1.cost }) > 32 * 1024 * 1024 {
            cache.removeValue(forKey: order.removeFirst())
        }
    }

    func clear() {
        let wasPrepared = source != nil
        generation = UUID(); foregroundTask?.cancel(); warmTask?.cancel()
        if wasPrepared {
            let decoder = decoder, warmDecoder = warmDecoder
            Task { await decoder.reset(); await warmDecoder.reset() }
        }
        foregroundTask = nil; warmTask = nil; source = nil; desired = nil
        cache.removeAll(); order.removeAll(); hoverX = nil
        image = nil; imageTime = nil; represented = nil; loading = false; approximate = false
    }
}

struct PreviewSeekBar: View {
    @Bindable var model: PlayerModel
    private var preview: TimelinePreview { model.timelinePreview }

    var body: some View {
        GeometryReader { geometry in
            let duration = model.duration.isFinite ? max(0, model.duration) : 0
            let time = model.scrubbing ? model.scrubPosition : preview.hoverX.map {
                TimelinePosition.seconds(x: $0, width: geometry.size.width, duration: duration)
            }
            let pointerX = model.scrubbing ? TimelinePosition.x(seconds: model.scrubPosition, width: geometry.size.width, duration: duration) : (preview.hoverX ?? 0)
            let request = model.thumbnailRequest(time: time)
            Slider(value: Binding(get: { model.scrubbing ? model.scrubPosition : model.position }, set: { model.scrubPosition = $0; preview.request(model.thumbnailRequest(time: $0)) }), in: 0...max(1, duration)) { editing in
                if editing { model.scrubPosition = model.position; model.scrubbing = true }
                else { model.scrubbing = false; model.seek(model.scrubPosition); preview.hoverX = nil; preview.request(nil) }
            }
            .controlSize(.mini).disabled(!model.loaded || duration <= 0).accessibilityLabel("Timeline")
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    preview.hoverX = model.loaded && duration > 0 ? location.x : nil
                    if !model.scrubbing {
                        preview.request(model.thumbnailRequest(time: duration > 0 ? TimelinePosition.seconds(x: location.x, width: geometry.size.width, duration: duration) : nil))
                    }
                case .ended: preview.hoverX = nil; if !model.scrubbing { preview.request(nil) }
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let time, model.loaded, duration > 0 {
                    VStack(spacing: 5) {
                        if request != nil {
                            ZStack {
                                Color.black
                                if let image = preview.image, preview.represented == request {
                                    Image(nsImage: image).resizable().scaledToFit()
                                } else if preview.loading { ProgressView().controlSize(.small) }
                                else { Image(systemName: "video.slash").foregroundStyle(.secondary) }
                            }.frame(width: 192, height: 108).clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        Text(timestamp(time)).monospacedDigit().font(.system(size: 11, weight: .medium))
                        if preview.approximate, let actual = preview.imageTime, request != nil {
                            Text("Preview ≈ \(timestamp(actual))").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(6).frame(width: 204).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                    .offset(x: min(max(0, pointerX - 102), max(0, geometry.size.width - 204)), y: -24)
                    .allowsHitTesting(false)
                }
            }
            .task(id: request) { if !Task.isCancelled { preview.request(request) } }
        }
        .frame(height: 16).zIndex(10)
        .onDisappear { preview.hoverX = nil; preview.request(nil) }
    }
}

extension PlayerModel {
    func prepareTimelinePreviews() {
        guard let source = thumbnailSource else { return }
        timelinePreview.prepare(source)
    }
    var thumbnailSource: ThumbnailSource? {
        guard loaded, duration.isFinite, duration > 0, current?.discKind == nil,
              tracks.contains(where: { $0["type"] as? String == "video" && $0["albumart"] as? Bool != true }),
              let id = currentID, let url = library.resolve(id), url.isFileURL,
              !["m3u", "m3u8", "mid", "midi"].contains(url.pathExtension.lowercased()),
              let path = runtimeLibraryPath else { return nil }
        return ThumbnailSource(url: url, duration: duration, library: path)
    }
    func thumbnailRequest(time: Double?) -> ThumbnailRequest? {
        guard let time, time.isFinite, let source = thumbnailSource else { return nil }
        return ThumbnailRequest(url: source.url, seconds: min(max(0, (time * 2).rounded() / 2), max(0, duration - 0.1)), library: source.library)
    }
}
