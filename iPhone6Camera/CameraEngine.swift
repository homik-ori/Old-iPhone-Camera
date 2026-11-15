import AVFoundation
import Foundation

/// Отвечает за сессию AVCapture, выбор широкоугольного объектива,
/// фокус/экспозицию, зум и получение JPEG-данных.
final class CameraEngine: NSObject {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.homikori.iPhone6Camera.session", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var videoDevice: AVCaptureDevice?

    private(set) var position: AVCaptureDevice.Position = .back
    private(set) var isConfigured = false
    private(set) var exposureBias: Float = 0
    private(set) var maxZoomFactor: CGFloat = 5
    private(set) var currentZoom: CGFloat = 1
    private(set) var cameraHasFlash = false
    private(set) var shutterSpeed: ShutterSpeed = .auto
    private(set) var captureExposureStops: Float = 0

    private var autoBaselineISO: Float = 0
    private var autoBaselineDuration: CMTime = .zero
    private var manualExposureStops: Float = 0

    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        installSessionObservers()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        if session.isRunning {
            session.stopRunning()
        }
    }

    // MARK: - Разрешения

    static func requestCameraAccess(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    static var cameraAccessDenied: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .denied || status == .restricted
    }

    // MARK: - Настройка сессии

    func configure(completion: @escaping (Result<Void, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                if !self.isConfigured {
                    try self.configureSession(position: .back)
                }
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// Настраивается только на sessionQueue.
    private func configureSession(position: AVCaptureDevice.Position) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw AppError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw AppError.cannotAddInput }
        session.addInput(input)
        videoInput = input
        videoDevice = device
        self.position = position
        cameraHasFlash = device.hasFlash

        guard session.canAddOutput(photoOutput) else { throw AppError.cannotAddOutput }
        session.addOutput(photoOutput)

        // Отключаем максимальную вычислительную обработку: никакого Deep Fusion,
        // агрессивного шумодава и многоступенчатого склеивания. .speed — самый
        // «прямой» путь получения одного кадра.
        photoOutput.maxPhotoQualityPrioritization = .speed
        photoOutput.isHighResolutionCaptureEnabled = true
        photoOutput.isLivePhotoCaptureEnabled = false
        photoOutput.isDepthDataDeliveryEnabled = false

        updateConnectionOrientation()

        try configureDeviceForDefaultState(device)
        isConfigured = true
    }

    private func configureDeviceForDefaultState(_ device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        device.isSubjectAreaChangeMonitoringEnabled = true
        device.cancelVideoZoomRamp()
        device.videoZoomFactor = 1
        device.setExposureTargetBias(0, completionHandler: nil)

        currentZoom = 1
        exposureBias = 0
        shutterSpeed = .auto
        captureExposureStops = 0
        autoBaselineISO = 0
        autoBaselineDuration = .zero
        manualExposureStops = 0
        maxZoomFactor = min(5.0, max(1.0, device.activeFormat.videoMaxZoomFactor))
    }

    private func updateConnectionOrientation() {
        guard let connection = photoOutput.connection(with: .video) else { return }
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }

    // MARK: - Жизненный цикл

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    // MARK: - Переключение камеры

    func switchCamera(completion: @escaping (Result<AVCaptureDevice.Position, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self, let oldInput = self.videoInput else {
                DispatchQueue.main.async { completion(.failure(AppError.cameraUnavailable)) }
                return
            }

            let newPosition: AVCaptureDevice.Position = self.position == .back ? .front : .back
            guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else {
                DispatchQueue.main.async { completion(.failure(AppError.cameraUnavailable)) }
                return
            }

            do {
                let newInput = try AVCaptureDeviceInput(device: newDevice)

                self.session.beginConfiguration()
                self.session.removeInput(oldInput)

                guard self.session.canAddInput(newInput) else {
                    self.session.addInput(oldInput)
                    self.session.commitConfiguration()
                    throw AppError.cannotAddInput
                }

                self.session.addInput(newInput)
                self.session.commitConfiguration()

                self.videoInput = newInput
                self.videoDevice = newDevice
                self.position = newPosition
                self.cameraHasFlash = newDevice.hasFlash
                self.updateConnectionOrientation()
                try self.configureDeviceForDefaultState(newDevice)

                DispatchQueue.main.async { completion(.success(newPosition)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    // MARK: - Фокус, экспозиция и зум

    func focus(at devicePoint: CGPoint, lock: Bool, completion: ((Error?) -> Void)? = nil) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else {
                DispatchQueue.main.async { completion?(AppError.cameraUnavailable) }
                return
            }

            let point = CGPoint(
                x: min(max(devicePoint.x, 0.05), 0.95),
                y: min(max(devicePoint.y, 0.05), 0.95)
            )

            do {
                try device.lockForConfiguration()

                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = point
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                }

                let keepsManualExposure = self.shutterSpeed.isManual
                if lock {
                    if device.isFocusModeSupported(.locked) {
                        device.focusMode = .locked
                    }
                    if !keepsManualExposure, device.isExposureModeSupported(.locked) {
                        device.exposureMode = .locked
                    }
                    device.isSubjectAreaChangeMonitoringEnabled = false
                } else {
                    if device.isFocusModeSupported(.autoFocus) {
                        device.focusMode = .autoFocus
                    } else if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    }
                    if !keepsManualExposure {
                        if device.isExposureModeSupported(.autoExpose) {
                            device.exposureMode = .autoExpose
                        } else if device.isExposureModeSupported(.continuousAutoExposure) {
                            device.exposureMode = .continuousAutoExposure
                        }
                    }
                    device.isSubjectAreaChangeMonitoringEnabled = true
                }

                device.unlockForConfiguration()
                DispatchQueue.main.async { completion?(nil) }
            } catch {
                DispatchQueue.main.async { completion?(error) }
            }
        }
    }

    func resetFocusAndExposure(completion: (() -> Void)? = nil) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else {
                DispatchQueue.main.async { completion?() }
                return
            }

            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if !self.shutterSpeed.isManual {
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                    device.setExposureTargetBias(self.exposureBias, completionHandler: nil)
                }
                device.isSubjectAreaChangeMonitoringEnabled = true
                device.unlockForConfiguration()
            } catch {
                // Сброс не критичен: не блокируем интерфейс из-за ошибки конфигурации.
            }

            DispatchQueue.main.async { completion?() }
        }
    }

    func setExposureBias(_ bias: Float, completion: (() -> Void)? = nil) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else {
                DispatchQueue.main.async { completion?() }
                return
            }

            let clamped = min(max(bias, -2.0), 2.0)
            do {
                try device.lockForConfiguration()
                device.setExposureTargetBias(clamped, completionHandler: nil)
                device.unlockForConfiguration()
                self.exposureBias = clamped
                if self.shutterSpeed.isManual {
                    self.captureExposureStops = min(2.5, max(-4.0, self.manualExposureStops + clamped))
                }
            } catch {
                // Значение остаётся прежним.
            }
            DispatchQueue.main.async { completion?() }
        }
    }

    /// Переключает камеру между автоэкспозицией и ручной выдержкой.
    /// ISO подбирается так, чтобы сохранить яркость сцены, насколько это возможно.
    func setShutter(_ speed: ShutterSpeed,
                    completion: @escaping (Result<Void, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else {
                DispatchQueue.main.async { completion(.failure(AppError.cameraUnavailable)) }
                return
            }

            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                if speed == .auto {
                    guard device.isExposureModeSupported(.continuousAutoExposure) else {
                        throw AppError.manualExposureUnsupported
                    }
                    device.exposureMode = .continuousAutoExposure
                    device.setExposureTargetBias(self.exposureBias, completionHandler: nil)
                    self.shutterSpeed = .auto
                    self.autoBaselineISO = 0
                    self.autoBaselineDuration = .zero
                    self.manualExposureStops = 0
                    self.captureExposureStops = 0
                } else {
                    guard device.isExposureModeSupported(.custom), let requestedDuration = speed.duration else {
                        throw AppError.manualExposureUnsupported
                    }

                    let wasManual = self.shutterSpeed.isManual
                    if !wasManual || self.autoBaselineISO <= 0 || CMTimeGetSeconds(self.autoBaselineDuration) <= 0 {
                        self.autoBaselineISO = max(device.iso, 1)
                        self.autoBaselineDuration = device.exposureDuration
                    }

                    let minDuration = device.activeFormat.minExposureDuration
                    let maxDuration = device.activeFormat.maxExposureDuration
                    var duration = requestedDuration
                    if CMTimeCompare(duration, minDuration) < 0 { duration = minDuration }
                    if CMTimeCompare(duration, maxDuration) > 0 { duration = maxDuration }

                    let baselineSeconds = CMTimeGetSeconds(self.autoBaselineDuration)
                    let targetSeconds = CMTimeGetSeconds(duration)
                    guard baselineSeconds.isFinite, baselineSeconds > 0,
                          targetSeconds.isFinite, targetSeconds > 0 else {
                        throw AppError.manualExposureUnsupported
                    }

                    let minISO = max(device.activeFormat.minISO, 1)
                    let maxISO = max(device.activeFormat.maxISO, minISO)
                    let idealISO = self.autoBaselineISO * Float(baselineSeconds / targetSeconds)
                    let targetISO = min(max(idealISO, minISO), maxISO)

                    device.setExposureModeCustom(duration: duration, iso: targetISO, completionHandler: nil)
                    self.shutterSpeed = speed

                    // Если минимального ISO всё равно не хватает, экспозиция будет
                    // светлее исходной. Компенсируем это при постобработке.
                    let baselineExposure = self.autoBaselineISO * Float(baselineSeconds)
                    let appliedExposure = targetISO * Float(targetSeconds)
                    let stops: Float
                    if baselineExposure > 0, appliedExposure > 0 {
                        stops = Float(log2(Double(baselineExposure / appliedExposure)))
                    } else {
                        stops = 0
                    }
                    self.manualExposureStops = min(2.0, max(-4.0, stops))
                    self.captureExposureStops = min(2.5, max(-4.0, self.manualExposureStops + self.exposureBias))
                }

                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func setZoom(_ factor: CGFloat, rate: Float? = nil) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }

            do {
                try device.lockForConfiguration()
                let hardwareMax = max(1.0, device.activeFormat.videoMaxZoomFactor)
                let allowedMax = min(5.0, hardwareMax)
                let target = min(max(factor, 1.0), allowedMax)

                device.cancelVideoZoomRamp()
                if let rate {
                    device.ramp(toVideoZoomFactor: target, withRate: rate)
                } else {
                    device.videoZoomFactor = target
                }

                device.unlockForConfiguration()
                self.currentZoom = target
                self.maxZoomFactor = allowedMax
            } catch {
                // Если устройство занято, следующий жест просто повторит попытку.
            }
        }
    }

    // MARK: - Съёмка

    func capturePhoto(flash: FlashSetting, completion: @escaping (Result<Data, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, let device = self.videoDevice else {
                DispatchQueue.main.async { completion(.failure(AppError.cameraUnavailable)) }
                return
            }

            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                settings = AVCapturePhotoSettings()
            }

            // Главный ключ к «вайбу»: скорость вместо многослойного HDR.
            settings.photoQualityPrioritization = .speed

            if device.hasFlash, device.position == .back {
                settings.flashMode = flash.avFlashMode
            } else {
                settings.flashMode = .off
            }

            let processor = PhotoCaptureProcessor { result in
                DispatchQueue.main.async { completion(result) }
            }
            processor.retainUntilFinished()
            self.photoOutput.capturePhoto(with: settings, delegate: processor)
        }
    }

    // MARK: - Наблюдатели

    private func installSessionObservers() {
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: .AVCaptureSessionRuntimeError,
            object: session,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.sessionQueue.async {
                if self.isConfigured, !self.session.isRunning {
                    self.session.startRunning()
                }
            }
        })

        observers.append(center.addObserver(
            forName: .AVCaptureSessionInterruptionEnded,
            object: session,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.sessionQueue.async {
                if self.isConfigured, !self.session.isRunning {
                    self.session.startRunning()
                }
            }
        })
    }
}

// MARK: - Делегат одного снимка

private final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    private var result: Result<Data, Error>?
    private var completion: ((Result<Data, Error>) -> Void)?
    private var selfRetain: PhotoCaptureProcessor?
    private var finished = false

    init(completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion
        super.init()
    }

    /// AVCapturePhotoOutput не удерживает delegate, поэтому держим себя сами
    /// до заключительного колбэка.
    func retainUntilFinished() {
        selfRetain = self
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            result = .failure(error)
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            result = .failure(AppError.captureFailed)
            return
        }
        result = .success(data)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        guard !finished else { return }
        finished = true

        let finalResult: Result<Data, Error>
        if let error {
            finalResult = .failure(error)
        } else if let result {
            finalResult = result
        } else {
            finalResult = .failure(AppError.captureFailed)
        }

        let callback = completion
        completion = nil
        callback?(finalResult)
        selfRetain = nil
    }
}
