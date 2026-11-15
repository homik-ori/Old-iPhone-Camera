import CoreImage
import UIKit

enum CameraFilter: String, CaseIterable {
    case original
    case vivid
    case vividWarm
    case vividCool
    case dramatic
    case dramaticWarm
    case mono
    case noir
    case vintage2014
    case palette

    var title: String {
        switch self {
        case .original: return "Оригинал"
        case .vivid: return "Яркий"
        case .vividWarm: return "Яркий тёплый"
        case .vividCool: return "Яркий холодный"
        case .dramatic: return "Эффектный"
        case .dramaticWarm: return "Эффектный тёплый"
        case .mono: return "Моно"
        case .noir: return "Нуар"
        case .vintage2014: return "Винтаж 2014"
        case .palette: return "Палитра"
        }
    }

    var swatchColors: [UIColor] {
        switch self {
        case .original:
            return [UIColor(red: 0.20, green: 0.17, blue: 0.13, alpha: 1),
                    UIColor(red: 0.83, green: 0.55, blue: 0.30, alpha: 1),
                    UIColor(red: 0.94, green: 0.83, blue: 0.64, alpha: 1)]
        case .vivid:
            return [UIColor(red: 0.04, green: 0.20, blue: 0.38, alpha: 1),
                    UIColor(red: 0.06, green: 0.63, blue: 0.66, alpha: 1),
                    UIColor(red: 0.96, green: 0.74, blue: 0.16, alpha: 1)]
        case .vividWarm:
            return [UIColor(red: 0.37, green: 0.13, blue: 0.05, alpha: 1),
                    UIColor(red: 0.94, green: 0.43, blue: 0.10, alpha: 1),
                    UIColor(red: 1.00, green: 0.82, blue: 0.35, alpha: 1)]
        case .vividCool:
            return [UIColor(red: 0.04, green: 0.22, blue: 0.40, alpha: 1),
                    UIColor(red: 0.27, green: 0.62, blue: 0.83, alpha: 1),
                    UIColor(red: 0.72, green: 0.92, blue: 0.94, alpha: 1)]
        case .dramatic:
            return [UIColor(red: 0.03, green: 0.04, blue: 0.05, alpha: 1),
                    UIColor(red: 0.20, green: 0.23, blue: 0.25, alpha: 1),
                    UIColor(red: 0.71, green: 0.68, blue: 0.60, alpha: 1)]
        case .dramaticWarm:
            return [UIColor(red: 0.08, green: 0.04, blue: 0.03, alpha: 1),
                    UIColor(red: 0.36, green: 0.17, blue: 0.10, alpha: 1),
                    UIColor(red: 0.82, green: 0.58, blue: 0.36, alpha: 1)]
        case .mono:
            return [UIColor(white: 0.06, alpha: 1), UIColor(white: 0.45, alpha: 1), UIColor(white: 0.90, alpha: 1)]
        case .noir:
            return [UIColor(white: 0.0, alpha: 1), UIColor(white: 0.16, alpha: 1), UIColor(white: 0.78, alpha: 1)]
        case .vintage2014:
            return [UIColor(red: 0.22, green: 0.20, blue: 0.12, alpha: 1),
                    UIColor(red: 0.64, green: 0.55, blue: 0.31, alpha: 1),
                    UIColor(red: 0.88, green: 0.78, blue: 0.55, alpha: 1)]
        case .palette:
            return PaletteTint.allCases.map(\.color)
        }
    }
}

enum PaletteTint: String, CaseIterable {
    case amber
    case filmGreen
    case coolBlue
    case sunsetPink
    case sepia

    var title: String {
        switch self {
        case .amber: return "Тёплый янтарь"
        case .filmGreen: return "Плёночный зелёный"
        case .coolBlue: return "Холодный синий"
        case .sunsetPink: return "Закатный розовый"
        case .sepia: return "Сепия"
        }
    }

    var shortTitle: String {
        switch self {
        case .amber: return "Янтарь"
        case .filmGreen: return "Зелёный"
        case .coolBlue: return "Синий"
        case .sunsetPink: return "Розовый"
        case .sepia: return "Сепия"
        }
    }

    var color: UIColor {
        switch self {
        case .amber: return UIColor(red: 0.86, green: 0.58, blue: 0.27, alpha: 1)
        case .filmGreen: return UIColor(red: 0.48, green: 0.58, blue: 0.39, alpha: 1)
        case .coolBlue: return UIColor(red: 0.34, green: 0.51, blue: 0.67, alpha: 1)
        case .sunsetPink: return UIColor(red: 0.86, green: 0.53, blue: 0.55, alpha: 1)
        case .sepia: return UIColor(red: 0.61, green: 0.48, blue: 0.34, alpha: 1)
        }
    }
}

struct LookSettings {
    var filter: CameraFilter = .original
    var palette: PaletteTint = .amber
    var paletteIntensity: Float = 0.35
    var retro: Float = 0.65

    static let `default` = LookSettings()
}

/// Общая цветокоррекция для live-preview и финального снимка.
final class LookRenderer {
    static let shared = LookRenderer()

    private init() {}

    func apply(to input: CIImage, look: LookSettings) -> CIImage {
        var image = input

        switch look.filter {
        case .original:
            image = applyOriginal(image)
        case .vivid:
            image = applyVivid(image, warm: false)
        case .vividWarm:
            image = applyVivid(image, warm: true)
        case .vividCool:
            image = applyVividCool(image)
        case .dramatic:
            image = applyDramatic(image, warm: false)
        case .dramaticWarm:
            image = applyDramatic(image, warm: true)
        case .mono:
            image = image.applyingFilter("CIPhotoEffectMono")
            image = image.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.10
            ])
        case .noir:
            image = image.applyingFilter("CIPhotoEffectNoir")
            image = image.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.06
            ])
        case .vintage2014:
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 5750, y: 8)
            ])
            image = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputShadowAmount": 0.42,
                "inputHighlightAmount": 0.82,
                "inputRadius": 3.0
            ])
            image = image.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.74,
                kCIInputContrastKey: 0.92,
                kCIInputBrightnessKey: 0.012
            ])
            image = image.applyingFilter("CIVignette", parameters: [
                kCIInputIntensityKey: 0.24,
                kCIInputRadiusKey: 1.55
            ])
        case .palette:
            image = applyOriginal(image)
            image = applyPalette(image, tint: look.palette, intensity: look.paletteIntensity)
        }

        image = applyRetro(to: image, level: look.retro)
        return image.applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
        ])
    }

    // MARK: - Presets

    private func applyOriginal(_ image: CIImage) -> CIImage {
        var result = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
            "inputShadowAmount": 0.30,
            "inputHighlightAmount": 0.88,
            "inputRadius": 2.5
        ])
        result = result.applyingFilter("CITemperatureAndTint", parameters: [
            "inputNeutral": CIVector(x: 6500, y: 0),
            "inputTargetNeutral": CIVector(x: 6075, y: 4)
        ])
        return result.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.965,
            kCIInputContrastKey: 0.982,
            kCIInputBrightnessKey: 0.004
        ])
    }

    private func applyVivid(_ image: CIImage, warm: Bool) -> CIImage {
        var result = image.applyingFilter("CIVibrance", parameters: ["inputAmount": 0.34])
        result = result.applyingFilter("CITemperatureAndTint", parameters: [
            "inputNeutral": CIVector(x: 6500, y: 0),
            "inputTargetNeutral": CIVector(x: warm ? 5600 : 6250, y: warm ? 7 : 1)
        ])
        return result.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 1.22,
            kCIInputContrastKey: 1.08,
            kCIInputBrightnessKey: 0.006
        ])
    }

    private func applyVividCool(_ image: CIImage) -> CIImage {
        var result = image.applyingFilter("CIVibrance", parameters: ["inputAmount": 0.30])
        result = result.applyingFilter("CITemperatureAndTint", parameters: [
            "inputNeutral": CIVector(x: 6500, y: 0),
            "inputTargetNeutral": CIVector(x: 7250, y: -3)
        ])
        return result.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 1.18,
            kCIInputContrastKey: 1.06,
            kCIInputBrightnessKey: 0.002
        ])
    }

    private func applyDramatic(_ image: CIImage, warm: Bool) -> CIImage {
        var result = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
            "inputShadowAmount": 0.24,
            "inputHighlightAmount": 0.70,
            "inputRadius": 4.0
        ])
        result = result.applyingFilter("CITemperatureAndTint", parameters: [
            "inputNeutral": CIVector(x: 6500, y: 0),
            "inputTargetNeutral": CIVector(x: warm ? 5650 : 6500, y: warm ? 7 : -1)
        ])
        result = result.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: warm ? 0.90 : 0.84,
            kCIInputContrastKey: 1.24,
            kCIInputBrightnessKey: -0.035
        ])
        return result.applyingFilter("CIVignette", parameters: [
            kCIInputIntensityKey: 0.20,
            kCIInputRadiusKey: 1.6
        ])
    }

    private func applyPalette(_ image: CIImage, tint: PaletteTint, intensity: Float) -> CIImage {
        let monochrome = image.applyingFilter("CIColorMonochrome", parameters: [
            "inputColor": CIColor(cgColor: tint.color.cgColor),
            "inputIntensity": 0.08 + 0.34 * min(max(intensity, 0), 1)
        ])
        return monochrome.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.94,
            kCIInputContrastKey: 0.99
        ])
    }

    // MARK: - Ретро-эффект

    private func applyRetro(to image: CIImage, level: Float) -> CIImage {
        let retro = min(max(level, 0), 1)
        guard retro > 0.001 else { return image }

        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        let scale = max(extent.width, extent.height) / 3264.0
        var result = image

        if let blur = CIFilter(name: "CIGaussianBlur", parameters: [
            kCIInputImageKey: result.clampedToExtent(),
            kCIInputRadiusKey: CGFloat(0.6 * retro) * scale
        ])?.outputImage {
            result = blur.cropped(to: extent)
        }

        let bloomRadius = (2.0 + 9.0 * CGFloat(retro)) * scale
        let bloomIntensity = 0.12 + 0.34 * retro
        if let bloom = CIFilter(name: "CIBloom", parameters: [
            kCIInputImageKey: result,
            kCIInputRadiusKey: bloomRadius,
            kCIInputIntensityKey: bloomIntensity
        ])?.outputImage {
            result = bloom.cropped(to: extent)
        }

        if let random = CIFilter(name: "CIRandomGenerator")?.outputImage {
            let grainAlpha = 0.010 + 0.060 * retro
            let grain = random
                .cropped(to: extent)
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 0.333, y: 0.333, z: 0.333, w: 0),
                    "inputGVector": CIVector(x: 0.333, y: 0.333, z: 0.333, w: 0),
                    "inputBVector": CIVector(x: 0.333, y: 0.333, z: 0.333, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(grainAlpha)),
                    "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
                ])

            if let blended = CIFilter(name: "CISoftLightBlendMode", parameters: [
                kCIInputImageKey: grain,
                kCIInputBackgroundImageKey: result
            ])?.outputImage {
                result = blended.cropped(to: extent)
            }
        }

        result = result.applyingFilter("CIVignette", parameters: [
            kCIInputIntensityKey: 0.04 + 0.18 * retro,
            kCIInputRadiusKey: 1.7
        ])

        return result
    }
}
