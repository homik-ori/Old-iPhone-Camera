import CoreImage
import Foundation
import ImageIO
import Photos
import UIKit

struct ProcessedPhoto {
    let image: UIImage
    let jpegData: Data
    let pixelSize: CGSize
}

/// Постобработка «как на старом iPhone»: даунскейл, лёгкое смягчение,
/// тёплый баланс белого и очень деликатное зерно старого сенсора.
final class ImageProcessor {
    static let shared = ImageProcessor()

    private let context = CIContext(options: [CIContextOption.cacheIntermediates: false])
    private let processingQueue = DispatchQueue(label: "com.homikori.OldiphoneCam.processing",
                                                qos: .userInitiated)

    private init() {}

    func process(jpegData: Data,
                 aspect: CaptureAspect,
                 exposureStops: Float = 0,
                 completion: @escaping (Result<ProcessedPhoto, Error>) -> Void) {
        processingQueue.async { [weak self] in
            guard let self else { return }
            let result: Result<ProcessedPhoto, Error>
            do {
                result = .success(try self.processSynchronously(jpegData: jpegData,
                                                                aspect: aspect,
                                                                exposureStops: exposureStops))
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func processSynchronously(jpegData: Data,
                                      aspect: CaptureAspect,
                                      exposureStops: Float) throws -> ProcessedPhoto {
        guard let sourceImage = UIImage(data: jpegData), let sourceCGImage = sourceImage.cgImage else {
            throw AppError.imageProcessingFailed
        }

        var image = CIImage(cgImage: sourceCGImage)
        if sourceImage.imageOrientation != .up {
            image = image.oriented(forExifOrientation: Self.exifOrientation(sourceImage.imageOrientation))
        }

        let target = aspect.pixelSize
        let targetRect = CGRect(origin: .zero, size: target)
        let targetAspect = target.width / target.height
        let sourceExtent = image.extent
        guard sourceExtent.width > 1, sourceExtent.height > 1 else {
            throw AppError.imageProcessingFailed
        }

        // Центральный кроп под выбранное соотношение сторон.
        var cropRect = sourceExtent
        let sourceAspect = sourceExtent.width / sourceExtent.height
        if sourceAspect > targetAspect {
            cropRect.size.width = sourceExtent.height * targetAspect
            cropRect.origin.x = sourceExtent.minX + (sourceExtent.width - cropRect.width) / 2.0
        } else {
            cropRect.size.height = sourceExtent.width / targetAspect
            cropRect.origin.y = sourceExtent.minY + (sourceExtent.height - cropRect.height) / 2.0
        }
        cropRect = cropRect.integral

        image = image.cropped(to: cropRect)
        image = image.transformed(by: CGAffineTransform(translationX: -cropRect.minX,
                                                        y: -cropRect.minY))

        // Точный ресайз до 3264 px по длинной стороне: убирает микрорезкость
        // современных многопиксельных сенсоров.
        let scaleX = target.width / cropRect.width
        let scaleY = target.height / cropRect.height
        image = image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Компенсация пересвета при длинной выдержке, когда ISO уже на минимуме.
        if abs(exposureStops) > 0.01 {
            image = image.applyingFilter("CIExposureAdjust", parameters: [
                "inputEV": exposureStops
            ])
        }

        // 1. Едва заметное оптическое смягчение.
        if let blur = CIFilter(name: "CIGaussianBlur",
                               parameters: [
                                   kCIInputImageKey: image.clampedToExtent(),
                                   kCIInputRadiusKey: 0.38
                               ])?.outputImage {
            image = blur.cropped(to: targetRect)
        }

        // 2. Мягкие света и тени — без современного «выжигания» HDR.
        image = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
            "inputShadowAmount": 0.30,
            "inputHighlightAmount": exposureStops < -1.0 ? 0.76 : 0.88,
            "inputRadius": 2.5
        ])

        // 3. Тёплый естественный оттенок.
        image = image.applyingFilter("CITemperatureAndTint", parameters: [
            "inputNeutral": CIVector(x: 6500, y: 0),
            "inputTargetNeutral": CIVector(x: 6075, y: 4)
        ])

        // Чуть менее контрастная и насыщенная картинка, чем у современных iPhone.
        image = image.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.965,
            kCIInputContrastKey: 0.982,
            kCIInputBrightnessKey: 0.004
        ])

        // Почти невидимая виньетка старой оптики.
        image = image.applyingFilter("CIVignette", parameters: [
            kCIInputIntensityKey: 0.10,
            kCIInputRadiusKey: 1.65
        ])

        // 4. Естественное монохромное зерно матрицы с прозрачностью ~5%.
        if let random = CIFilter(name: "CIRandomGenerator")?.outputImage {
            let grain = random
                .cropped(to: targetRect)
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 0.333, y: 0.333, z: 0.333, w: 0),
                    "inputGVector": CIVector(x: 0.333, y: 0.333, z: 0.333, w: 0),
                    "inputBVector": CIVector(x: 0.333, y: 0.333, z: 0.333, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.052),
                    "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
                ])

            if let blended = CIFilter(name: "CISoftLightBlendMode", parameters: [
                kCIInputImageKey: grain,
                kCIInputBackgroundImageKey: image
            ])?.outputImage {
                image = blended.cropped(to: targetRect)
            }
        }

        image = image.applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
        ])

        guard let outputCGImage = context.createCGImage(image, from: targetRect) else {
            throw AppError.imageProcessingFailed
        }

        let outputImage = UIImage(cgImage: outputCGImage, scale: 1.0, orientation: .up)
        guard let outputJPEG = outputImage.jpegData(compressionQuality: 0.85) else {
            throw AppError.imageProcessingFailed
        }

        return ProcessedPhoto(image: outputImage, jpegData: outputJPEG, pixelSize: target)
    }

    private static func exifOrientation(_ orientation: UIImage.Orientation) -> Int32 {
        switch orientation {
        case .up: return Int32(CGImagePropertyOrientation.up.rawValue)
        case .down: return Int32(CGImagePropertyOrientation.down.rawValue)
        case .left: return Int32(CGImagePropertyOrientation.left.rawValue)
        case .right: return Int32(CGImagePropertyOrientation.right.rawValue)
        case .upMirrored: return Int32(CGImagePropertyOrientation.upMirrored.rawValue)
        case .downMirrored: return Int32(CGImagePropertyOrientation.downMirrored.rawValue)
        case .leftMirrored: return Int32(CGImagePropertyOrientation.leftMirrored.rawValue)
        case .rightMirrored: return Int32(CGImagePropertyOrientation.rightMirrored.rawValue)
        @unknown default: return Int32(CGImagePropertyOrientation.up.rawValue)
        }
    }
}

enum PhotoLibrarySaver {
    static func save(jpegData: Data, completion: @escaping (Result<String, Error>) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(.failure(AppError.photoLibraryDenied)) }
                return
            }

            var localIdentifier: String?
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = "OldiphoneCam_\(Self.fileTimestamp()).jpg"
                options.uniformTypeIdentifier = "public.jpeg"
                request.addResource(with: .photo, data: jpegData, options: options)
                localIdentifier = request.placeholderForCreatedAsset?.localIdentifier
            }, completionHandler: { success, error in
                DispatchQueue.main.async {
                    if let error {
                        completion(.failure(AppError.photoLibrarySaveFailed(error.localizedDescription)))
                    } else if success {
                        completion(.success(localIdentifier ?? ""))
                    } else {
                        completion(.failure(AppError.photoLibrarySaveFailed("неизвестная ошибка")))
                    }
                }
            })
        }
    }

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}
