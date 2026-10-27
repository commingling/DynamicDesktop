import AVFoundation
import CoreVideo
import Foundation

/// Write a tiny, solid-color movie for the wallpaper engine integration test.
/// Components use the usual RGB order and range 0...255.
func writeVideo(at url: URL, red: UInt8, green: UInt8, blue: UInt8) throws {
    let width = 64
    let height = 64
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
    ])
    guard writer.canAdd(input) else { throw VideoFixtureError.failed("Cannot add video input") }
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? VideoFixtureError.failed("Cannot start writer") }
    writer.startSession(atSourceTime: .zero)
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
    guard status == kCVReturnSuccess, let buffer = buffer else { throw VideoFixtureError.failed("Cannot create pixel buffer") }
    CVPixelBufferLockBaseAddress(buffer, [])
    guard let base = CVPixelBufferGetBaseAddress(buffer) else {
        CVPixelBufferUnlockBaseAddress(buffer, [])
        throw VideoFixtureError.failed("Cannot access pixel buffer")
    }
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    for y in 0..<height {
        let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
        for x in 0..<width {
            row[x * 4] = blue
            row[x * 4 + 1] = green
            row[x * 4 + 2] = red
            row[x * 4 + 3] = 255
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    for frame in 0..<2 {
        let deadline = Date().addingTimeInterval(5)
        while !input.isReadyForMoreMediaData && writer.status == .writing && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard input.isReadyForMoreMediaData,
              adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 1)) else {
            throw writer.error ?? VideoFixtureError.failed("Cannot append video frame")
        }
    }
    input.markAsFinished()
    let completed = DispatchSemaphore(value: 0)
    writer.finishWriting { completed.signal() }
    guard completed.wait(timeout: .now() + 10) == .success else { throw VideoFixtureError.failed("Video writer timed out") }
    guard writer.status == .completed else { throw writer.error ?? VideoFixtureError.failed("Video writer failed") }
}

enum VideoFixtureError: Error {
    case failed(String)
}
