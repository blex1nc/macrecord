import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Reads single pixels with ScreenCaptureKit (local only; needs Screen Recording permission).
public final class ScreenPixelSampler: PixelSampling {
    public init() {}

    public static var permissionGranted: Bool { CGPreflightScreenCaptureAccess() }
    public static func requestPermission() { _ = CGRequestScreenCaptureAccess() }

    /// Blocking; call from a background thread.
    public func rgb(atX x: Double, y: Double) -> UInt32? {
        let box = ResultBox()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            box.value = await Self.sample(x: x, y: y)
            done.signal()
        }
        done.wait()
        return box.value
    }

    private final class ResultBox: @unchecked Sendable { var value: UInt32? }

    static func sample(x: Double, y: Double) async -> UInt32? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.frame.contains(CGPoint(x: x, y: y)) }) else {
            return nil
        }
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: x - display.frame.minX, y: y - display.frame.minY, width: 1, height: 1)
        config.width = 1
        config.height = 1
        config.showsCursor = false
        let filter = SCContentFilter(display: display, excludingWindows: [])
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else {
            return nil
        }
        return pixel(of: image)
    }

    static func pixel(of image: CGImage) -> UInt32? {
        var data = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return UInt32(data[0]) << 16 | UInt32(data[1]) << 8 | UInt32(data[2])
    }
}
