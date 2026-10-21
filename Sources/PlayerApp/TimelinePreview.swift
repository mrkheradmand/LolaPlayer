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
    func frame(url: URL, seconds: Double, library: String) -> ThumbnailFrame? {
        guard !Task.isCancelled, url.isFileURL, seconds.isFinite, seconds >= 0,
              let frame = decoder.frame(atPath: url.path, seconds: seconds, library: library),
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

@Observable final class TimelinePreview {
    var hoverX: CGFloat?
    var image: NSImage?
    var represented: ThumbnailRequest?
    var loading = false
    @ObservationIgnored private let decoder = ThumbnailDecoder()
    @ObservationIgnored private let cache = NSCache<NSString, NSImage>()

    init() { cache.countLimit = 64; cache.totalCostLimit = 16 * 1024 * 1024 }

    func load(_ request: ThumbnailRequest?) async {
        guard !Task.isCancelled else { return }
        image = nil; represented = request; loading = request != nil
        guard let request else { return }
        let key = "\(request.url.path)#\(request.seconds)" as NSString
        if let cached = cache.object(forKey: key) { image = cached; loading = false; return }
        do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
        guard let frame = await decoder.frame(url: request.url, seconds: request.seconds, library: request.library),
              !Task.isCancelled, represented == request else {
            if !Task.isCancelled && represented == request { loading = false }
            return
        }
        guard let provider = CGDataProvider(data: frame.pixels as CFData),
              let cgImage = CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: frame.stride, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { loading = false; return }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: frame.width, height: frame.height))
        cache.setObject(image, forKey: key, cost: frame.pixels.count)
        self.image = image; loading = false
    }
    func clear() { cache.removeAllObjects(); image = nil; represented = nil; loading = false }
}

struct PreviewSeekBar: View {
    @Bindable var model: PlayerModel
    private var preview: TimelinePreview { model.timelinePreview }

    var body: some View {
        GeometryReader { geometry in
            let duration = model.duration.isFinite ? max(0, model.duration) : 0
            let time = preview.hoverX.map { TimelinePosition.seconds(x: $0, width: geometry.size.width, duration: model.duration) }
            let request = thumbnailRequest(time: time)
            Slider(value: Binding(get: { model.scrubbing ? model.scrubPosition : model.position }, set: { model.scrubPosition = $0 }), in: 0...max(1, duration)) { editing in
                if editing { model.scrubPosition = model.position; model.scrubbing = true }
                else { model.scrubbing = false; model.seek(model.scrubPosition) }
            }
            .controlSize(.mini).disabled(!model.loaded || duration <= 0).accessibilityLabel("Timeline")
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): preview.hoverX = model.loaded && duration > 0 ? location.x : nil
                case .ended: preview.hoverX = nil
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
                    }
                    .padding(6).frame(width: 204).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                    .offset(x: min(max(0, (preview.hoverX ?? 0) - 102), max(0, geometry.size.width - 204)), y: -24)
                    .allowsHitTesting(false)
                }
            }
            .task(id: request) { await preview.load(request) }
        }
        .frame(height: 16).zIndex(10)
        .onDisappear { preview.hoverX = nil }
        .onChange(of: model.currentID) { _, _ in preview.hoverX = nil; preview.clear() }
        .onChange(of: model.loaded) { _, loaded in if !loaded { preview.hoverX = nil; preview.clear() } }
    }

    private func thumbnailRequest(time: Double?) -> ThumbnailRequest? {
        guard let time, model.loaded, model.current?.discKind == nil,
              model.tracks.contains(where: { $0["type"] as? String == "video" && $0["albumart"] as? Bool != true }),
              let id = model.currentID, let url = model.library.resolve(id), url.isFileURL,
              !["m3u", "m3u8", "mid", "midi"].contains(url.pathExtension.lowercased()),
              let library = model.runtimeLibraryPath else { return nil }
        return ThumbnailRequest(url: url, seconds: min((time * 2).rounded() / 2, max(0, model.duration - 0.1)), library: library)
    }
}
