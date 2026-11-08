import AppKit
import CoreImage
import CoreMedia
import ScreenCaptureKit

final class SystemWindowPicker: NSObject, SCContentSharingPickerObserver {
    private let receive: @MainActor (Result<SCContentFilter?, Error>) -> Void

    init(receive: @escaping @MainActor (Result<SCContentFilter?, Error>) -> Void) {
        self.receive = receive
    }

    @MainActor func present() {
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = .singleWindow
        configuration.excludedBundleIDs = [Bundle.main.bundleIdentifier ?? "local.keban.study-assistant"]
        configuration.allowsChangingSelectedContent = false
        picker.defaultConfiguration = configuration
        picker.add(self)
        picker.isActive = true
        picker.present()
    }

    private func finish(_ result: Result<SCContentFilter?, Error>) {
        Task { @MainActor in
            SCContentSharingPicker.shared.remove(self)
            receive(result)
        }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        finish(.success(filter))
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        finish(.success(nil))
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        finish(.failure(error))
    }
}

final class WindowFrameReceiver: NSObject, SCStreamOutput {
    let frames: AsyncStream<CGImage>
    private let continuation: AsyncStream<CGImage>.Continuation
    private let context = CIContext()

    override init() {
        (frames, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
              let buffer = sampleBuffer.imageBuffer else { return }
        let image = CIImage(cvPixelBuffer: buffer)
        if let frame = context.createCGImage(image, from: image.extent) {
            continuation.yield(frame)
            continuation.finish()
        }
    }

    func finish() { continuation.finish() }
}

@MainActor final class PickedWindow {
    private let stream: SCStream

    init(filter: SCContentFilter) {
        let config = SCStreamConfiguration()
        let width = max(1, filter.contentRect.width), height = max(1, filter.contentRect.height)
        let scale = min(CGFloat(filter.pointPixelScale), 2200 / max(width, height))
        config.width = max(2, Int(width * scale))
        config.height = max(2, Int(height * scale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.capturesAudio = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: 5)
        stream = SCStream(filter: filter, configuration: config, delegate: nil)
    }

    func image() async throws -> CGImage {
        let receiver = WindowFrameReceiver()
        try stream.addStreamOutput(receiver, type: .screen, sampleHandlerQueue: DispatchQueue(label: "keban.window-frame"))
        defer {
            receiver.finish()
            try? stream.removeStreamOutput(receiver, type: .screen)
        }
        try await stream.startCapture()
        do {
            let frame = try await withThrowingTaskGroup(of: CGImage.self) { group in
                group.addTask {
                    for await frame in receiver.frames { return frame }
                    throw CancellationError()
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(5))
                    throw AppError.message("No screenshot was received. Make sure the window is not minimized, then select it again.")
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else { throw CancellationError() }
                return first
            }
            try await stream.stopCapture()
            return frame
        } catch {
            try? await stream.stopCapture()
            throw error
        }
    }
}
