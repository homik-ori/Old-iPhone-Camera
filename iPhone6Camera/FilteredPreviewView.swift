import AVFoundation
import CoreImage
import ImageIO
import MetalKit
import UIKit

/// Видоискатель с живой цветокоррекцией через Core Image и Metal.
final class FilteredPreviewView: MTKView {
    private var renderer: FilteredPreviewRenderer?

    init() {
        let device = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: device)
        setup()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        guard let device else { return }
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = false
        autoResizeDrawable = true
        isPaused = false
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 30
        clearColor = MTLClearColorMake(0, 0, 0, 1)
        isOpaque = true
        backgroundColor = .black

        let renderer = FilteredPreviewRenderer(device: device)
        self.renderer = renderer
        delegate = renderer
    }

    func enqueue(_ pixelBuffer: CVPixelBuffer) {
        renderer?.enqueue(pixelBuffer)
    }

    func setLook(_ look: LookSettings) {
        renderer?.setLook(look)
    }

    func setMirrored(_ mirrored: Bool) {
        renderer?.setMirrored(mirrored)
    }
}

private final class FilteredPreviewRenderer: NSObject, MTKViewDelegate {
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let stateLock = NSLock()

    private var latestBuffer: CVPixelBuffer?
    private var look = LookSettings.default
    private var mirrored = false

    init(device: MTLDevice) {
        guard let queue = device.makeCommandQueue() else {
            fatalError("Не удалось создать Metal command queue")
        }
        commandQueue = queue
        ciContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        super.init()
    }

    func enqueue(_ pixelBuffer: CVPixelBuffer) {
        stateLock.lock()
        latestBuffer = pixelBuffer
        stateLock.unlock()
    }

    func setLook(_ look: LookSettings) {
        stateLock.lock()
        self.look = look
        stateLock.unlock()
    }

    func setMirrored(_ mirrored: Bool) {
        stateLock.lock()
        self.mirrored = mirrored
        stateLock.unlock()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        stateLock.lock()
        let pixelBuffer = latestBuffer
        let currentLook = look
        let isMirrored = mirrored
        stateLock.unlock()

        let targetSize = view.drawableSize
        guard targetSize.width > 0, targetSize.height > 0 else { return }
        let targetRect = CGRect(origin: .zero, size: targetSize)

        let image: CIImage
        if let pixelBuffer {
            image = makePreviewImage(from: pixelBuffer,
                                     look: currentLook,
                                     targetSize: targetSize,
                                     mirrored: isMirrored)
        } else {
            image = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: targetRect)
        }

        ciContext.render(image,
                         to: drawable.texture,
                         commandBuffer: commandBuffer,
                         bounds: targetRect,
                         colorSpace: colorSpace)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func makePreviewImage(from pixelBuffer: CVPixelBuffer,
                                  look: LookSettings,
                                  targetSize: CGSize,
                                  mirrored: Bool) -> CIImage {
        var image = CIImage(cvPixelBuffer: pixelBuffer)

        // Некоторые конфигурации отдают горизонтальный буфер даже при
        // выставленной портретной ориентации соединения.
        if image.extent.width > image.extent.height {
            image = image.oriented(forExifOrientation: Int32(CGImagePropertyOrientation.right.rawValue))
        }

        let sourceExtent = image.extent
        let targetAspect = targetSize.width / targetSize.height
        let sourceAspect = sourceExtent.width / sourceExtent.height

        var crop = sourceExtent
        if sourceAspect > targetAspect {
            crop.size.width = sourceExtent.height * targetAspect
            crop.origin.x = sourceExtent.minX + (sourceExtent.width - crop.width) / 2.0
        } else {
            crop.size.height = sourceExtent.width / targetAspect
            crop.origin.y = sourceExtent.minY + (sourceExtent.height - crop.height) / 2.0
        }
        crop = crop.integral

        image = image.cropped(to: crop)
        image = image.transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))

        if mirrored {
            let extent = image.extent
            image = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
            image = image.transformed(by: CGAffineTransform(translationX: extent.minX + extent.maxX, y: 0))
        }

        // Для 30 FPS фильтруем уменьшенный кадр, а не полный сенсорный буфер.
        let longEdge = max(image.extent.width, image.extent.height)
        if longEdge > 1000 {
            let scale = 1000.0 / longEdge
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        var processed = LookRenderer.shared.apply(to: image, look: look)
        processed = processed.cropped(to: processed.extent)

        let widthScale = targetSize.width / processed.extent.width
        let heightScale = targetSize.height / processed.extent.height
        return processed
            .transformed(by: CGAffineTransform(scaleX: widthScale, y: heightScale))
            .cropped(to: CGRect(origin: .zero, size: targetSize))
    }
}
