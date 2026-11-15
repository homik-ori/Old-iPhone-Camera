import AVFoundation
import UIKit

/// Палитра и общие константы интерфейса.
enum Theme {
    static let yellow = UIColor(red: 1.0, green: 214.0 / 255.0, blue: 10.0 / 255.0, alpha: 1.0)
    static let background = UIColor.black
    static let secondaryText = UIColor(white: 1.0, alpha: 0.68)
    static let controlBackground = UIColor(white: 0.16, alpha: 0.62)
    static let panelBackground = UIColor(white: 0.09, alpha: 0.94)
}

/// Соотношение сторон кадра. Значения хранятся в «портретной» ориентации,
/// потому что приложение работает только в портрете.
enum CaptureAspect: String, CaseIterable {
    case fourThree
    case sixteenNine
    case square

    var title: String {
        switch self {
        case .fourThree: return "4:3"
        case .sixteenNine: return "16:9"
        case .square: return "1:1"
        }
    }

    /// Ширина / высота будущего файла.
    var value: CGFloat {
        switch self {
        case .fourThree: return 3.0 / 4.0
        case .sixteenNine: return 9.0 / 16.0
        case .square: return 1.0
        }
    }

    /// 8-мегапиксельный эквивалент iPhone 6. Длинная сторона — 3264 px,
    /// как у сенсора 3264 × 2448. Для 16:9 и 1:1 кадр обрезается пропорционально.
    var pixelSize: CGSize {
        switch self {
        case .fourThree:
            return CGSize(width: 2448, height: 3264)
        case .sixteenNine:
            return CGSize(width: 1836, height: 3264)
        case .square:
            return CGSize(width: 2448, height: 2448)
        }
    }
}

enum FlashSetting: String, CaseIterable {
    case auto
    case on
    case off

    var title: String {
        switch self {
        case .auto: return "Авто"
        case .on: return "Вкл"
        case .off: return "Выкл"
        }
    }

    var iconName: String {
        switch self {
        case .auto: return "bolt.badge.a.fill"
        case .on: return "bolt.fill"
        case .off: return "bolt.slash.fill"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .auto: return "Вспышка: авто"
        case .on: return "Вспышка: включена"
        case .off: return "Вспышка: выключена"
        }
    }

    var avFlashMode: AVCaptureDevice.FlashMode {
        switch self {
        case .auto: return .auto
        case .on: return .on
        case .off: return .off
        }
    }

    var next: FlashSetting {
        switch self {
        case .auto: return .on
        case .on: return .off
        case .off: return .auto
        }
    }
}

enum TimerSetting: Int, CaseIterable {
    case off = 0
    case three = 3
    case ten = 10

    var title: String {
        switch self {
        case .off: return "Выкл"
        case .three: return "3 с"
        case .ten: return "10 с"
        }
    }

    var seconds: Int { rawValue }
}

/// Ручная выдержка. Индекс используется напрямую ползунком в панели настроек.
enum ShutterSpeed: Int, CaseIterable {
    case auto = 0
    case s125
    case s60
    case s30
    case s15
    case s8
    case s4
    case s2
    case s1

    var title: String {
        switch self {
        case .auto: return "АВТО"
        case .s125: return "1/125"
        case .s60: return "1/60"
        case .s30: return "1/30"
        case .s15: return "1/15"
        case .s8: return "1/8"
        case .s4: return "1/4"
        case .s2: return "1/2"
        case .s1: return "1 с"
        }
    }

    var duration: CMTime? {
        switch self {
        case .auto: return nil
        case .s125: return CMTime(value: 1, timescale: 125)
        case .s60: return CMTime(value: 1, timescale: 60)
        case .s30: return CMTime(value: 1, timescale: 30)
        case .s15: return CMTime(value: 1, timescale: 15)
        case .s8: return CMTime(value: 1, timescale: 8)
        case .s4: return CMTime(value: 1, timescale: 4)
        case .s2: return CMTime(value: 1, timescale: 2)
        case .s1: return CMTime(value: 1, timescale: 1)
        }
    }

    var isManual: Bool { self != .auto }
}

enum AppError: LocalizedError {
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput
    case captureFailed
    case imageProcessingFailed
    case manualExposureUnsupported
    case photoLibraryDenied
    case photoLibrarySaveFailed(String)

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "Камера недоступна на этом устройстве."
        case .cannotAddInput:
            return "Не удалось подключить камеру к сессии захвата."
        case .cannotAddOutput:
            return "Не удалось настроить фото-выход камеры."
        case .captureFailed:
            return "Не удалось получить снимок с камеры."
        case .imageProcessingFailed:
            return "Не удалось обработать изображение."
        case .manualExposureUnsupported:
            return "Эта камера не поддерживает ручную выдержку."
        case .photoLibraryDenied:
            return "Нет доступа к медиатеке. Разрешите добавление фото в настройках."
        case .photoLibrarySaveFailed(let message):
            return "Не удалось сохранить снимок в «Фото»: \(message)"
        }
    }
}
