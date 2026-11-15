import AVFoundation
import UIKit

/// Главный экран камеры в стиле iOS 15 с «плёнкой» iPhone 6.
final class CameraViewController: UIViewController, UIGestureRecognizerDelegate {
    // MARK: - Камера и обработка

    private let engine = CameraEngine()
    private var previewLayer: AVCaptureVideoPreviewLayer!

    // MARK: - Слои интерфейса

    private let previewContainer = UIView()
    private let previewView = CameraPreviewView()
    private let gridOverlay = GridOverlayView()
    private let topBar = UIView()
    private let flashButton = UIButton(type: .system)
    private let chevronButton = UIButton(type: .system)
    private let lockBanner = UILabel()
    private let focusReticle = FocusReticleView()
    private let zoomStack = UIStackView()
    private let zoomDial = ZoomDialView()
    private let bottomContainer = UIView()
    private let modeLabel = UILabel()
    private let shutterButton = ShutterButton()
    private let thumbnailButton = UIButton(type: .custom)
    private let flipButton = UIButton(type: .system)
    private let settingsPanel = CameraSettingsPanel()
    private let toastLabel = UILabel()
    private let countdownBackdrop = UIView()
    private let countdownLabel = UILabel()
    private let flashOverlay = UIView()
    private let blinkOverlay = UIView()
    private let permissionView = UIView()
    private let thumbnailSpinner = UIActivityIndicatorView(style: .medium)

    // MARK: - Состояние

    private var currentAspect: CaptureAspect = .fourThree
    private var flashSetting: FlashSetting = .auto
    private var timerSetting: TimerSetting = .off
    private var shutterSpeed: ShutterSpeed = .auto
    private var isGridOn = false
    private var isFrontCamera = false
    private var isSettingsOpen = false
    private var isFocusLocked = false
    private var isCountingDown = false
    private var isCapturing = false
    private var isConfiguringCamera = false
    private var isSwitchingCamera = false

    private var currentExposureBias: Float = 0
    private var currentZoom: CGFloat = 1
    private var pinchStartZoom: CGFloat = 1
    private var lastZoomHapticStep = 10

    private var lastFocusPoint: CGPoint?
    private var focusDimWorkItem: DispatchWorkItem?
    private var focusHideWorkItem: DispatchWorkItem?
    private var zoomDialHideWorkItem: DispatchWorkItem?
    private var toastHideWorkItem: DispatchWorkItem?
    private var suppressPreviewTapUntil: Date?
    private var suppressZoomButtonTapUntil: Date?
    private var panStartExposureBias: Float = 0

    private var lastPhoto: UIImage?
    private var lastPhotoData: Data?

    private var tapRecognizer: UITapGestureRecognizer?
    private var longPressRecognizer: UILongPressGestureRecognizer?
    private var exposurePanRecognizer: UIPanGestureRecognizer?
    private var pinchRecognizer: UIPinchGestureRecognizer?

    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    private var appObservers: [NSObjectProtocol] = []

    private enum DefaultsKey {
        static let flash = "camera.flash"
        static let aspect = "camera.aspect"
        static let timer = "camera.timer"
        static let grid = "camera.grid"
        static let shutter = "camera.shutter"
    }

    // MARK: - Жизненный цикл

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        restoreSettings()
        buildInterface()
        installGestures()
        installAppObservers()
        refreshAllControls()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
        impactFeedback.prepare()
        selectionFeedback.prepare()
        startCameraIfPossible()

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-openShutterPanel") {
            settingsPanel.selectTool(4)
            setSettingsOpen(true, animated: false)
        }
        #endif
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if engine.isConfigured {
            engine.start()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
        engine.stop()
        cancelCountdown()
        hideZoomDial(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyPreviewFrame(animated: false)
        if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        previewView.layoutIfNeeded()
    }

    deinit {
        appObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Построение интерфейса

    private func buildInterface() {
        buildPreview()
        buildTopBar()
        buildLockBanner()
        buildBottomBar()
        buildSettingsPanel()
        buildOverlays()
        buildPermissionView()

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            topBar.heightAnchor.constraint(equalToConstant: 44),

            previewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            previewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            previewContainer.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 8),
            previewContainer.bottomAnchor.constraint(equalTo: bottomContainer.topAnchor, constant: -8),

            bottomContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            bottomContainer.heightAnchor.constraint(equalToConstant: 154)
        ])
    }

    private func buildPreview() {
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.backgroundColor = .clear
        view.addSubview(previewContainer)

        previewView.backgroundColor = .black
        previewView.layer.cornerRadius = 10
        previewView.layer.cornerCurve = .continuous
        previewView.clipsToBounds = true
        previewContainer.addSubview(previewView)

        previewLayer = AVCaptureVideoPreviewLayer(session: engine.session)
        previewLayer.videoGravity = .resizeAspectFill
        previewView.previewLayer = previewLayer

        gridOverlay.frame = previewView.bounds
        gridOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        previewView.addSubview(gridOverlay)

        focusReticle.isHidden = true
        previewView.addSubview(focusReticle)

        zoomStack.translatesAutoresizingMaskIntoConstraints = false
        zoomStack.axis = .horizontal
        zoomStack.spacing = 8
        zoomStack.alignment = .center
        previewView.addSubview(zoomStack)

        for factor in [1, 2, 3] {
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.tag = factor
            button.setTitle("\(factor)x", for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
            button.backgroundColor = Theme.controlBackground
            button.layer.cornerRadius = 19
            button.clipsToBounds = true
            button.widthAnchor.constraint(equalToConstant: 38).isActive = true
            button.heightAnchor.constraint(equalToConstant: 38).isActive = true
            button.accessibilityLabel = "Зум \(factor)x"
            button.addTarget(self, action: #selector(zoomButtonTapped(_:)), for: .touchUpInside)
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(zoomButtonHeld(_:)))
            hold.minimumPressDuration = 0.22
            button.addGestureRecognizer(hold)
            zoomStack.addArrangedSubview(button)
        }

        zoomDial.translatesAutoresizingMaskIntoConstraints = false
        previewView.addSubview(zoomDial)
        zoomDial.onZoomChanged = { [weak self] value in
            self?.applyZoom(value, haptic: true)
        }

        NSLayoutConstraint.activate([
            zoomStack.centerXAnchor.constraint(equalTo: previewView.centerXAnchor),
            zoomStack.bottomAnchor.constraint(equalTo: previewView.bottomAnchor, constant: -14),
            zoomStack.heightAnchor.constraint(equalToConstant: 38),

            zoomDial.centerXAnchor.constraint(equalTo: previewView.centerXAnchor),
            zoomDial.bottomAnchor.constraint(equalTo: previewView.bottomAnchor, constant: -10),
            zoomDial.widthAnchor.constraint(equalToConstant: 300),
            zoomDial.heightAnchor.constraint(equalToConstant: 150)
        ])
    }

    private func buildTopBar() {
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.backgroundColor = .clear
        view.addSubview(topBar)

        flashButton.translatesAutoresizingMaskIntoConstraints = false
        flashButton.backgroundColor = Theme.controlBackground
        flashButton.layer.cornerRadius = 22
        flashButton.tintColor = .white
        flashButton.addTarget(self, action: #selector(flashTapped), for: .touchUpInside)
        topBar.addSubview(flashButton)

        chevronButton.translatesAutoresizingMaskIntoConstraints = false
        chevronButton.backgroundColor = Theme.controlBackground
        chevronButton.layer.cornerRadius = 22
        chevronButton.tintColor = .white
        chevronButton.setImage(UIImage(systemName: "chevron.up",
                                       withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)),
                               for: .normal)
        chevronButton.accessibilityLabel = "Открыть настройки"
        chevronButton.addTarget(self, action: #selector(chevronTapped), for: .touchUpInside)
        topBar.addSubview(chevronButton)

        NSLayoutConstraint.activate([
            flashButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 16),
            flashButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            flashButton.widthAnchor.constraint(equalToConstant: 44),
            flashButton.heightAnchor.constraint(equalToConstant: 44),

            chevronButton.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            chevronButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            chevronButton.widthAnchor.constraint(equalToConstant: 44),
            chevronButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func buildLockBanner() {
        lockBanner.translatesAutoresizingMaskIntoConstraints = false
        lockBanner.text = "ФИКСАЦИЯ ЭКСПОЗИЦИИ/ФОКУСА"
        lockBanner.font = UIFont.systemFont(ofSize: 9.5, weight: .semibold)
        lockBanner.textColor = .black
        lockBanner.backgroundColor = Theme.yellow
        lockBanner.textAlignment = .center
        lockBanner.layer.cornerRadius = 5
        lockBanner.layer.masksToBounds = true
        lockBanner.alpha = 0
        lockBanner.isHidden = true
        view.addSubview(lockBanner)

        NSLayoutConstraint.activate([
            lockBanner.centerXAnchor.constraint(equalTo: previewContainer.centerXAnchor),
            lockBanner.topAnchor.constraint(equalTo: previewContainer.topAnchor, constant: 12),
            lockBanner.widthAnchor.constraint(equalToConstant: 250),
            lockBanner.heightAnchor.constraint(equalToConstant: 23)
        ])
    }

    private func buildBottomBar() {
        bottomContainer.translatesAutoresizingMaskIntoConstraints = false
        bottomContainer.backgroundColor = .clear
        view.addSubview(bottomContainer)

        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        modeLabel.attributedText = NSAttributedString(string: "ФОТО", attributes: [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: Theme.yellow,
            .kern: 1.8
        ])
        modeLabel.textAlignment = .center
        modeLabel.accessibilityLabel = "Режим фото"
        bottomContainer.addSubview(modeLabel)

        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
        bottomContainer.addSubview(shutterButton)

        thumbnailButton.translatesAutoresizingMaskIntoConstraints = false
        thumbnailButton.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        thumbnailButton.layer.cornerRadius = 7
        thumbnailButton.layer.borderWidth = 1
        thumbnailButton.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        thumbnailButton.clipsToBounds = true
        thumbnailButton.tintColor = UIColor.white.withAlphaComponent(0.65)
        thumbnailButton.imageView?.contentMode = .scaleAspectFill
        thumbnailButton.setImage(UIImage(systemName: "photo.fill",
                                         withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)),
                                 for: .normal)
        thumbnailButton.addTarget(self, action: #selector(thumbnailTapped), for: .touchUpInside)
        thumbnailButton.accessibilityLabel = "Последний снимок"
        bottomContainer.addSubview(thumbnailButton)

        thumbnailSpinner.translatesAutoresizingMaskIntoConstraints = false
        thumbnailSpinner.color = .white
        thumbnailSpinner.hidesWhenStopped = true
        thumbnailButton.addSubview(thumbnailSpinner)

        flipButton.translatesAutoresizingMaskIntoConstraints = false
        flipButton.backgroundColor = Theme.controlBackground
        flipButton.layer.cornerRadius = 23
        flipButton.tintColor = .white
        flipButton.setImage(UIImage(systemName: "arrow.triangle.2.circlepath.camera",
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .medium)),
                            for: .normal)
        flipButton.accessibilityLabel = "Переключить камеру"
        flipButton.addTarget(self, action: #selector(flipTapped), for: .touchUpInside)
        bottomContainer.addSubview(flipButton)

        NSLayoutConstraint.activate([
            shutterButton.centerXAnchor.constraint(equalTo: bottomContainer.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: bottomContainer.bottomAnchor, constant: -2),
            shutterButton.widthAnchor.constraint(equalToConstant: 82),
            shutterButton.heightAnchor.constraint(equalToConstant: 82),

            modeLabel.centerXAnchor.constraint(equalTo: bottomContainer.centerXAnchor),
            modeLabel.bottomAnchor.constraint(equalTo: shutterButton.topAnchor, constant: -10),
            modeLabel.heightAnchor.constraint(equalToConstant: 18),
            modeLabel.widthAnchor.constraint(equalToConstant: 120),

            thumbnailButton.leadingAnchor.constraint(equalTo: bottomContainer.leadingAnchor, constant: 26),
            thumbnailButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            thumbnailButton.widthAnchor.constraint(equalToConstant: 54),
            thumbnailButton.heightAnchor.constraint(equalToConstant: 54),

            thumbnailSpinner.centerXAnchor.constraint(equalTo: thumbnailButton.centerXAnchor),
            thumbnailSpinner.centerYAnchor.constraint(equalTo: thumbnailButton.centerYAnchor),

            flipButton.trailingAnchor.constraint(equalTo: bottomContainer.trailingAnchor, constant: -26),
            flipButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            flipButton.widthAnchor.constraint(equalToConstant: 46),
            flipButton.heightAnchor.constraint(equalToConstant: 46)
        ])
    }

    private func buildSettingsPanel() {
        settingsPanel.translatesAutoresizingMaskIntoConstraints = false
        settingsPanel.isHidden = true
        settingsPanel.alpha = 0
        settingsPanel.transform = CGAffineTransform(translationX: 0, y: 24)
        view.addSubview(settingsPanel)

        settingsPanel.onFlashChange = { [weak self] setting in
            self?.setFlash(setting)
        }
        settingsPanel.onAspectChange = { [weak self] aspect in
            self?.setAspect(aspect)
        }
        settingsPanel.onExposureChange = { [weak self] value in
            self?.applyExposureBias(value, haptic: true)
        }
        settingsPanel.onTimerChange = { [weak self] timer in
            self?.setTimer(timer)
        }
        settingsPanel.onShutterChange = { [weak self] speed in
            self?.setShutter(speed)
        }
        settingsPanel.onGridChange = { [weak self] isOn in
            self?.setGrid(isOn)
        }

        NSLayoutConstraint.activate([
            settingsPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            settingsPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            settingsPanel.bottomAnchor.constraint(equalTo: shutterButton.topAnchor, constant: -10),
            settingsPanel.heightAnchor.constraint(equalToConstant: 150)
        ])
    }

    private func buildOverlays() {
        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        toastLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        toastLabel.textColor = .white
        toastLabel.textAlignment = .center
        toastLabel.backgroundColor = UIColor(white: 0, alpha: 0.72)
        toastLabel.layer.cornerRadius = 15
        toastLabel.layer.masksToBounds = true
        toastLabel.alpha = 0
        toastLabel.isHidden = true
        toastLabel.isUserInteractionEnabled = false
        view.addSubview(toastLabel)

        countdownBackdrop.translatesAutoresizingMaskIntoConstraints = false
        countdownBackdrop.backgroundColor = UIColor(white: 0, alpha: 0.26)
        countdownBackdrop.alpha = 0
        countdownBackdrop.isHidden = true
        countdownBackdrop.isUserInteractionEnabled = false
        view.addSubview(countdownBackdrop)

        countdownLabel.translatesAutoresizingMaskIntoConstraints = false
        countdownLabel.font = UIFont.systemFont(ofSize: 112, weight: .ultraLight)
        countdownLabel.textColor = .white
        countdownLabel.textAlignment = .center
        countdownLabel.layer.shadowColor = UIColor.black.cgColor
        countdownLabel.layer.shadowOpacity = 0.7
        countdownLabel.layer.shadowRadius = 8
        countdownLabel.layer.shadowOffset = .zero
        countdownLabel.isHidden = true
        countdownLabel.isUserInteractionEnabled = false
        view.addSubview(countdownLabel)

        flashOverlay.translatesAutoresizingMaskIntoConstraints = false
        flashOverlay.backgroundColor = .white
        flashOverlay.alpha = 0
        flashOverlay.isUserInteractionEnabled = false
        view.addSubview(flashOverlay)

        blinkOverlay.translatesAutoresizingMaskIntoConstraints = false
        blinkOverlay.backgroundColor = .black
        blinkOverlay.alpha = 0
        blinkOverlay.isUserInteractionEnabled = false
        view.addSubview(blinkOverlay)

        NSLayoutConstraint.activate([
            toastLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -176),
            toastLabel.widthAnchor.constraint(equalToConstant: 210),
            toastLabel.heightAnchor.constraint(equalToConstant: 30),

            countdownBackdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            countdownBackdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            countdownBackdrop.topAnchor.constraint(equalTo: view.topAnchor),
            countdownBackdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            countdownLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            countdownLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            countdownLabel.widthAnchor.constraint(equalToConstant: 220),
            countdownLabel.heightAnchor.constraint(equalToConstant: 150),

            flashOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            flashOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            flashOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            flashOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            blinkOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blinkOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blinkOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            blinkOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func buildPermissionView() {
        permissionView.translatesAutoresizingMaskIntoConstraints = false
        permissionView.backgroundColor = .black
        permissionView.isHidden = true
        view.addSubview(permissionView)

        let icon = UIImageView(image: UIImage(systemName: "camera.fill",
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 44, weight: .light)))
        icon.tintColor = UIColor.white.withAlphaComponent(0.82)
        icon.contentMode = .scaleAspectFit

        let title = UILabel()
        title.text = "Нет доступа к камере"
        title.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        title.textColor = .white
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = "Разрешите приложению использовать камеру,\nчтобы снимать в стиле iPhone 6."
        subtitle.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        subtitle.textColor = Theme.secondaryText
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        let settingsButton = UIButton(type: .system)
        settingsButton.setTitle("Открыть настройки", for: .normal)
        settingsButton.setTitleColor(.black, for: .normal)
        settingsButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        settingsButton.backgroundColor = Theme.yellow
        settingsButton.layer.cornerRadius = 22
        settingsButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [icon, title, subtitle, settingsButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.setCustomSpacing(26, after: subtitle)
        permissionView.addSubview(stack)

        NSLayoutConstraint.activate([
            permissionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            permissionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            permissionView.topAnchor.constraint(equalTo: view.topAnchor),
            permissionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.centerXAnchor.constraint(equalTo: permissionView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: permissionView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: permissionView.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: permissionView.trailingAnchor, constant: -32),
            icon.widthAnchor.constraint(equalToConstant: 52),
            icon.heightAnchor.constraint(equalToConstant: 52),
            settingsButton.widthAnchor.constraint(equalToConstant: 210),
            settingsButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    // MARK: - Жесты

    private func installGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(previewTapped(_:)))
        tap.delegate = self
        previewView.addGestureRecognizer(tap)
        tapRecognizer = tap

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(previewLongPressed(_:)))
        longPress.minimumPressDuration = 0.55
        longPress.delegate = self
        previewView.addGestureRecognizer(longPress)
        longPressRecognizer = longPress

        let pan = UIPanGestureRecognizer(target: self, action: #selector(exposurePanned(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        previewView.addGestureRecognizer(pan)
        exposurePanRecognizer = pan

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinchChanged(_:)))
        pinch.delegate = self
        previewView.addGestureRecognizer(pinch)
        pinchRecognizer = pinch

        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(swipedUp))
        swipeUp.direction = .up
        swipeUp.delegate = self
        swipeUp.require(toFail: pan)
        previewView.addGestureRecognizer(swipeUp)

        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(swipedDown))
        swipeDown.direction = .down
        swipeDown.delegate = self
        swipeDown.require(toFail: pan)
        previewView.addGestureRecognizer(swipeDown)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === exposurePanRecognizer {
            return lastFocusPoint != nil && !isFocusLocked && !isSettingsOpen && focusReticle.alpha > 0.05
        }
        if gestureRecognizer is UIPinchGestureRecognizer {
            return !isSettingsOpen
        }
        if let swipe = gestureRecognizer as? UISwipeGestureRecognizer {
            if isSettingsOpen {
                return swipe.direction == .down
            }
            return swipe.direction == .up
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    @objc private func previewTapped(_ gesture: UITapGestureRecognizer) {
        if let until = suppressPreviewTapUntil, Date() < until {
            return
        }
        if isSettingsOpen {
            setSettingsOpen(false, animated: true)
            return
        }
        guard !isCountingDown else { return }

        let point = gesture.location(in: previewView)
        guard previewView.bounds.contains(point) else { return }

        if isFocusLocked {
            unlockFocus()
        }

        hideZoomDial(animated: true)
        showFocusReticle(at: point, locked: false)
        focusCamera(at: point, lock: false)
    }

    @objc private func previewLongPressed(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard !isCountingDown, !isCapturing else { return }
            let point = gesture.location(in: previewView)
            guard previewView.bounds.contains(point) else { return }

            // Тап, который UIKit может распознать сразу после long press,
            // не должен сбрасывать только что включённую фиксацию.
            suppressPreviewTapUntil = Date().addingTimeInterval(0.5)
            isFocusLocked = true
            hideZoomDial(animated: true)
            showFocusReticle(at: point, locked: true)
            focusCamera(at: point, lock: true)
            showLockBanner()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .ended, .cancelled, .failed:
            suppressPreviewTapUntil = Date().addingTimeInterval(0.4)
        default:
            break
        }
    }

    @objc private func exposurePanned(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            panStartExposureBias = currentExposureBias
            cancelFocusAutoHide()
            focusReticle.alpha = 1
        case .changed:
            let translation = gesture.translation(in: previewView)
            let delta = Float(-translation.y / 190.0) * 2.0
            let raw = panStartExposureBias + delta
            let stepped = Self.steppedExposure(raw)
            if abs(stepped - currentExposureBias) > 0.001 {
                applyExposureBias(stepped, haptic: true)
            }
        case .ended, .cancelled, .failed:
            scheduleFocusAutoHide()
        default:
            break
        }
    }

    @objc private func pinchChanged(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            pinchStartZoom = currentZoom
            showZoomDial()
        case .changed:
            let target = min(max(pinchStartZoom * gesture.scale, 1.0), 5.0)
            applyZoom(target, haptic: true)
        case .ended, .cancelled, .failed:
            scheduleZoomDialHide()
        default:
            break
        }
    }

    @objc private func swipedUp() {
        setSettingsOpen(true, animated: true)
    }

    @objc private func swipedDown() {
        setSettingsOpen(false, animated: true)
    }

    // MARK: - Камера

    private func startCameraIfPossible() {
        if engine.isConfigured {
            permissionView.isHidden = true
            engine.start()
            return
        }

        #if targetEnvironment(simulator)
        // В симуляторе нет камеры, но интерфейс должен открываться для отладки.
        permissionView.isHidden = true
        return
        #else
        guard !isConfiguringCamera else { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureCamera()
        case .notDetermined:
            CameraEngine.requestCameraAccess { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.configureCamera()
                } else {
                    self.showPermissionView()
                }
            }
        default:
            showPermissionView()
        }
        #endif
    }

    private func configureCamera() {
        guard !isConfiguringCamera else { return }
        isConfiguringCamera = true
        engine.configure { [weak self] result in
            guard let self else { return }
            self.isConfiguringCamera = false
            switch result {
            case .success:
                self.permissionView.isHidden = true
                self.updatePreviewMirroring()
                self.engine.start()
                if self.shutterSpeed.isManual {
                    self.engine.setShutter(self.shutterSpeed) { result in
                        if case .failure = result {
                            self.shutterSpeed = .auto
                            self.settingsPanel.setShutter(.auto)
                            UserDefaults.standard.set(ShutterSpeed.auto.rawValue, forKey: DefaultsKey.shutter)
                        }
                    }
                }
            case .failure(let error):
                self.showErrorAlert(error)
            }
        }
    }

    private func showPermissionView() {
        engine.stop()
        permissionView.isHidden = false
        view.bringSubviewToFront(permissionView)
    }

    private func updatePreviewMirroring() {
        guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = isFrontCamera
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }

    private func focusCamera(at previewPoint: CGPoint, lock: Bool) {
        guard let previewLayer else { return }
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: previewPoint)
        engine.focus(at: devicePoint, lock: lock)
    }

    // MARK: - Кнопки

    @objc private func flashTapped() {
        guard !isFrontCamera else { return }
        setFlash(flashSetting.next)
        selectionFeedback.selectionChanged()
    }

    @objc private func chevronTapped() {
        setSettingsOpen(!isSettingsOpen, animated: true)
        selectionFeedback.selectionChanged()
    }

    @objc private func shutterTapped() {
        guard !isCapturing, !isCountingDown else { return }
        impactFeedback.impactOccurred()

        if timerSetting == .off {
            beginCapture()
        } else {
            startCountdown(seconds: timerSetting.seconds)
        }
    }

    @objc private func thumbnailTapped() {
        guard let lastPhoto else {
            showToast("Снимков пока нет")
            return
        }
        let preview = PhotoPreviewViewController(image: lastPhoto, jpegData: lastPhotoData)
        present(preview, animated: true)
    }

    @objc private func flipTapped() {
        guard !isSwitchingCamera, !isCapturing, !isCountingDown else { return }
        isSwitchingCamera = true
        flipButton.isEnabled = false
        isFocusLocked = false
        hideFocus(animated: true)
        hideLockBanner()

        engine.switchCamera { [weak self] result in
            guard let self else { return }
            self.isSwitchingCamera = false
            self.flipButton.isEnabled = true

            switch result {
            case .success(let position):
                self.isFrontCamera = position == .front
                self.currentExposureBias = 0
                self.currentZoom = 1
                self.shutterSpeed = .auto
                self.focusReticle.setBias(0)
                self.settingsPanel.setExposure(0)
                self.settingsPanel.setShutter(.auto)
                UserDefaults.standard.set(ShutterSpeed.auto.rawValue, forKey: DefaultsKey.shutter)
                self.updateZoomControls()
                self.zoomDial.setZoom(1)
                self.updatePreviewMirroring()
                self.updateFlashControl()

                UIView.transition(with: self.previewView,
                                  duration: 0.38,
                                  options: [.transitionFlipFromLeft, .allowAnimatedContent],
                                  animations: {
                    self.previewView.layoutIfNeeded()
                }, completion: nil)
                UIView.animate(withDuration: 0.38) {
                    self.flipButton.transform = self.flipButton.transform.rotated(by: .pi)
                }
                self.impactFeedback.impactOccurred()
            case .failure(let error):
                self.showErrorAlert(error)
            }
        }
    }

    @objc private func zoomButtonTapped(_ sender: UIButton) {
        if let until = suppressZoomButtonTapUntil, Date() < until {
            return
        }
        applyZoom(CGFloat(sender.tag), haptic: true)
    }

    @objc private func zoomButtonHeld(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            suppressZoomButtonTapUntil = Date().addingTimeInterval(0.7)
            showZoomDial()
            selectionFeedback.selectionChanged()
        case .ended, .cancelled, .failed:
            suppressZoomButtonTapUntil = Date().addingTimeInterval(0.45)
            scheduleZoomDialHide()
        default:
            break
        }
    }

    @objc private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Настройки камеры

    private func setFlash(_ setting: FlashSetting) {
        flashSetting = setting
        UserDefaults.standard.set(setting.rawValue, forKey: DefaultsKey.flash)
        updateFlashControl()
    }

    private func updateFlashControl() {
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        let image = UIImage(systemName: flashSetting.iconName, withConfiguration: config)
            ?? UIImage(systemName: flashSetting == .off ? "bolt.slash.fill" : "bolt.fill", withConfiguration: config)
        flashButton.setImage(image, for: .normal)
        flashButton.tintColor = flashSetting == .on ? Theme.yellow : .white
        flashButton.alpha = isFrontCamera ? 0.38 : 1.0
        flashButton.isEnabled = !isFrontCamera
        flashButton.accessibilityLabel = flashSetting.accessibilityTitle
        settingsPanel.setFlash(flashSetting)
    }

    private func setAspect(_ aspect: CaptureAspect) {
        guard aspect != currentAspect else { return }
        if isFocusLocked {
            unlockFocus()
        }
        currentAspect = aspect
        UserDefaults.standard.set(aspect.rawValue, forKey: DefaultsKey.aspect)
        settingsPanel.setAspect(aspect)
        hideFocus(animated: false)
        hideZoomDial(animated: false)
        applyPreviewFrame(animated: true)
    }

    private func setTimer(_ timer: TimerSetting) {
        timerSetting = timer
        UserDefaults.standard.set(timer.rawValue, forKey: DefaultsKey.timer)
        settingsPanel.setTimer(timer)
    }

    private func setShutter(_ speed: ShutterSpeed) {
        let previous = shutterSpeed
        shutterSpeed = speed
        UserDefaults.standard.set(speed.rawValue, forKey: DefaultsKey.shutter)
        settingsPanel.setShutter(speed)

        engine.setShutter(speed) { [weak self] result in
            guard let self else { return }
            if case .failure(let error) = result {
                self.shutterSpeed = previous
                self.settingsPanel.setShutter(previous)
                UserDefaults.standard.set(previous.rawValue, forKey: DefaultsKey.shutter)
                self.showErrorAlert(error)
            }
        }
    }

    private func setGrid(_ isOn: Bool) {
        isGridOn = isOn
        gridOverlay.isOn = isOn
        UserDefaults.standard.set(isOn, forKey: DefaultsKey.grid)
        settingsPanel.setGrid(isOn)
    }

    private func applyExposureBias(_ value: Float, haptic: Bool) {
        let clamped = min(max(value, -2.0), 2.0)
        guard abs(clamped - currentExposureBias) > 0.001 else { return }
        currentExposureBias = clamped
        focusReticle.setBias(clamped)
        settingsPanel.setExposure(clamped)
        engine.setExposureBias(clamped)
        if haptic {
            selectionFeedback.selectionChanged()
        }
        if !isFocusLocked, lastFocusPoint != nil {
            scheduleFocusAutoHide()
        }
    }

    private func setSettingsOpen(_ open: Bool, animated: Bool) {
        guard open != isSettingsOpen else { return }
        isSettingsOpen = open
        updateChevron()
        selectionFeedback.selectionChanged()

        if open {
            view.bringSubviewToFront(settingsPanel)
            settingsPanel.isHidden = false
            settingsPanel.alpha = 0
            settingsPanel.transform = CGAffineTransform(translationX: 0, y: 24)
            modeLabel.alpha = 1

            let animations = {
                self.settingsPanel.alpha = 1
                self.settingsPanel.transform = .identity
                self.modeLabel.alpha = 0
            }
            if animated {
                UIView.animate(withDuration: 0.34,
                               delay: 0,
                               usingSpringWithDamping: 0.86,
                               initialSpringVelocity: 0.4,
                               options: [.beginFromCurrentState, .allowUserInteraction],
                               animations: animations)
            } else {
                animations()
            }
        } else {
            let animations = {
                self.settingsPanel.alpha = 0
                self.settingsPanel.transform = CGAffineTransform(translationX: 0, y: 24)
                self.modeLabel.alpha = 1
            }
            let completion: (Bool) -> Void = { _ in
                if !self.isSettingsOpen {
                    self.settingsPanel.isHidden = true
                }
            }
            if animated {
                UIView.animate(withDuration: 0.24,
                               delay: 0,
                               options: [.beginFromCurrentState, .allowUserInteraction],
                               animations: animations,
                               completion: completion)
            } else {
                animations()
                completion(true)
            }
        }
    }

    private func updateChevron() {
        let name = isSettingsOpen ? "chevron.down" : "chevron.up"
        chevronButton.setImage(UIImage(systemName: name,
                                       withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)),
                               for: .normal)
        chevronButton.accessibilityLabel = isSettingsOpen ? "Закрыть настройки" : "Открыть настройки"
    }

    // MARK: - Фокус и экспозиция: визуал

    private func showFocusReticle(at point: CGPoint, locked: Bool) {
        let width: CGFloat = 104
        let height: CGFloat = 80
        var x = point.x - 36
        var y = point.y - 40

        x = max(2, min(x, previewView.bounds.width - width - 2))
        y = max(2, min(y, previewView.bounds.height - height - 2))

        focusReticle.frame = CGRect(x: x, y: y, width: width, height: height)
        focusReticle.setLocked(locked)
        focusReticle.setBias(currentExposureBias)
        focusReticle.animateIn()
        lastFocusPoint = point

        if locked {
            cancelFocusAutoHide()
        } else {
            scheduleFocusAutoHide()
        }
    }

    private func scheduleFocusAutoHide() {
        guard !isFocusLocked else { return }
        cancelFocusAutoHide()
        focusReticle.alpha = 1

        let dim = DispatchWorkItem { [weak self] in
            self?.focusReticle.fadeToIdle()
        }
        focusDimWorkItem = dim
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: dim)

        let hide = DispatchWorkItem { [weak self] in
            guard let self, !self.isFocusLocked else { return }
            self.focusReticle.fadeOut()
            self.lastFocusPoint = nil
        }
        focusHideWorkItem = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: hide)
    }

    private func cancelFocusAutoHide() {
        focusDimWorkItem?.cancel()
        focusHideWorkItem?.cancel()
        focusDimWorkItem = nil
        focusHideWorkItem = nil
    }

    private func hideFocus(animated: Bool) {
        cancelFocusAutoHide()
        lastFocusPoint = nil
        focusReticle.setLocked(false)
        if animated {
            focusReticle.fadeOut()
        } else {
            focusReticle.alpha = 0
            focusReticle.isHidden = true
        }
    }

    private func unlockFocus() {
        isFocusLocked = false
        focusReticle.setLocked(false)
        hideLockBanner()
        engine.resetFocusAndExposure()
    }

    private func showLockBanner() {
        lockBanner.isHidden = false
        lockBanner.alpha = 0
        lockBanner.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        UIView.animate(withDuration: 0.22,
                       delay: 0,
                       usingSpringWithDamping: 0.8,
                       initialSpringVelocity: 0.4,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.lockBanner.alpha = 1
            self.lockBanner.transform = .identity
        }
    }

    private func hideLockBanner() {
        UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.lockBanner.alpha = 0
        } completion: { _ in
            self.lockBanner.isHidden = true
        }
    }

    // MARK: - Зум: визуал

    private func applyZoom(_ value: CGFloat, haptic: Bool) {
        let clamped = min(max(value, 1.0), 5.0)
        currentZoom = clamped
        engine.setZoom(clamped)
        zoomDial.setZoom(clamped)
        updateZoomControls()

        if haptic {
            let step = Int((clamped * 10).rounded())
            if step != lastZoomHapticStep {
                lastZoomHapticStep = step
                selectionFeedback.selectionChanged()
            }
        }
        if !zoomDial.isHidden {
            scheduleZoomDialHide()
        }
    }

    private func updateZoomControls() {
        for case let button as UIButton in zoomStack.arrangedSubviews {
            let isSelected = abs(currentZoom - CGFloat(button.tag)) < 0.2
            button.backgroundColor = isSelected ? UIColor(white: 0.94, alpha: 1.0) : Theme.controlBackground
            button.setTitleColor(isSelected ? .black : .white, for: .normal)
        }
    }

    private func showZoomDial() {
        zoomDialHideWorkItem?.cancel()
        zoomDial.setZoom(currentZoom)
        if zoomDial.isHidden {
            zoomDial.isHidden = false
            zoomDial.alpha = 0
            zoomDial.transform = CGAffineTransform(translationX: 0, y: 14).scaledBy(x: 0.96, y: 0.96)
            UIView.animate(withDuration: 0.24,
                           delay: 0,
                           usingSpringWithDamping: 0.84,
                           initialSpringVelocity: 0.4,
                           options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.zoomDial.alpha = 1
                self.zoomDial.transform = .identity
            }
        }
    }

    private func hideZoomDial(animated: Bool) {
        zoomDialHideWorkItem?.cancel()
        guard !zoomDial.isHidden else { return }
        let finish = {
            self.zoomDial.isHidden = true
            self.zoomDial.transform = .identity
        }
        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.zoomDial.alpha = 0
                self.zoomDial.transform = CGAffineTransform(translationX: 0, y: 10)
            } completion: { _ in finish() }
        } else {
            zoomDial.alpha = 0
            finish()
        }
    }

    private func scheduleZoomDialHide() {
        zoomDialHideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hideZoomDial(animated: true)
        }
        zoomDialHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25, execute: work)
    }

    // MARK: - Съёмка

    private func beginCapture() {
        guard !isCapturing else { return }
        isCapturing = true
        blinkScreen()

        let aspectAtCapture = currentAspect
        engine.capturePhoto(flash: flashSetting) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let captured):
                self.processCapturedData(captured.data,
                                         aspect: aspectAtCapture,
                                         exposureStops: captured.exposureStops)
            case .failure(let error):
                self.isCapturing = false
                self.showErrorAlert(error)
            }
        }
    }

    private func processCapturedData(_ data: Data, aspect: CaptureAspect, exposureStops: Float) {
        thumbnailSpinner.startAnimating()
        ImageProcessor.shared.process(jpegData: data,
                                      aspect: aspect,
                                      exposureStops: exposureStops) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let photo):
                self.lastPhoto = photo.image
                self.lastPhotoData = photo.jpegData
                self.updateThumbnail(with: photo.image)
                PhotoLibrarySaver.save(jpegData: photo.jpegData) { [weak self] saveResult in
                    guard let self else { return }
                    self.thumbnailSpinner.stopAnimating()
                    self.isCapturing = false
                    switch saveResult {
                    case .success:
                        self.showToast("Сохранено в «Фото»")
                    case .failure(let error):
                        self.showErrorAlert(error, offerSettings: true)
                    }
                }
            case .failure(let error):
                self.thumbnailSpinner.stopAnimating()
                self.isCapturing = false
                self.showErrorAlert(error)
            }
        }
    }

    private func updateThumbnail(with image: UIImage) {
        thumbnailButton.setImage(image, for: .normal)
        thumbnailButton.tintColor = nil
        thumbnailButton.imageView?.contentMode = .scaleAspectFill
        thumbnailButton.accessibilityLabel = "Открыть последний снимок"
    }

    private func startCountdown(seconds: Int) {
        guard seconds > 0 else {
            beginCapture()
            return
        }
        isCountingDown = true
        countdownBackdrop.isHidden = false
        countdownLabel.isHidden = false
        countdownBackdrop.alpha = 1
        runCountdownTick(seconds)
    }

    private func runCountdownTick(_ remaining: Int) {
        guard isCountingDown, remaining > 0 else {
            finishCountdown()
            beginCapture()
            return
        }

        countdownLabel.text = "\(remaining)"
        countdownLabel.alpha = 0
        countdownLabel.transform = CGAffineTransform(scaleX: 1.28, y: 1.28)
        UIView.animate(withDuration: 0.28,
                       delay: 0,
                       usingSpringWithDamping: 0.72,
                       initialSpringVelocity: 0.5,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.countdownLabel.alpha = 1
            self.countdownLabel.transform = .identity
        }
        flashScreen()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.isCountingDown else { return }
            if remaining <= 1 {
                self.finishCountdown()
                self.beginCapture()
            } else {
                self.runCountdownTick(remaining - 1)
            }
        }
    }

    private func finishCountdown() {
        isCountingDown = false
        countdownLabel.isHidden = true
        countdownLabel.alpha = 0
        countdownBackdrop.isHidden = true
        countdownBackdrop.alpha = 0
    }

    private func cancelCountdown() {
        guard isCountingDown else { return }
        isCountingDown = false
        countdownLabel.isHidden = true
        countdownBackdrop.isHidden = true
        countdownBackdrop.alpha = 0
    }

    private func flashScreen() {
        flashOverlay.alpha = 0
        flashOverlay.isHidden = false
        UIView.animate(withDuration: 0.045, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.flashOverlay.alpha = 0.72
        } completion: { _ in
            UIView.animate(withDuration: 0.20, delay: 0.02, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.flashOverlay.alpha = 0
            } completion: { _ in
                self.flashOverlay.isHidden = true
            }
        }
    }

    private func blinkScreen() {
        blinkOverlay.alpha = 0
        blinkOverlay.isHidden = false
        UIView.animate(withDuration: 0.035, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.blinkOverlay.alpha = 0.86
        } completion: { _ in
            UIView.animate(withDuration: 0.15, delay: 0.015, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.blinkOverlay.alpha = 0
            } completion: { _ in
                self.blinkOverlay.isHidden = true
            }
        }
    }

    // MARK: - Раскладка видоискателя

    private func applyPreviewFrame(animated: Bool) {
        guard previewContainer.bounds.width > 0, previewContainer.bounds.height > 0 else { return }
        let target = targetPreviewFrame()
        guard target != previewView.frame else {
            previewView.previewLayer?.frame = previewView.bounds
            return
        }

        if animated, previewView.window != nil {
            UIView.transition(with: previewView,
                              duration: 0.26,
                              options: [.transitionCrossDissolve, .allowAnimatedContent],
                              animations: {
                self.previewView.frame = target
                self.previewView.previewLayer?.frame = CGRect(origin: .zero, size: target.size)
                self.previewView.layoutIfNeeded()
                self.gridOverlay.frame = self.previewView.bounds
            }, completion: nil)
        } else {
            previewView.frame = target
            previewView.previewLayer?.frame = CGRect(origin: .zero, size: target.size)
            previewView.layoutIfNeeded()
            gridOverlay.frame = previewView.bounds
        }
    }

    private func targetPreviewFrame() -> CGRect {
        let available = previewContainer.bounds
        guard available.width > 0, available.height > 0 else { return .zero }
        let ratio = currentAspect.value
        var width = available.width
        var height = width / ratio
        if height > available.height {
            height = available.height
            width = height * ratio
        }
        return CGRect(x: (available.width - width) / 2.0,
                      y: (available.height - height) / 2.0,
                      width: width,
                      height: height)
    }

    // MARK: - Вспомогательное

    private func restoreSettings() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: DefaultsKey.flash),
           let value = FlashSetting(rawValue: raw) {
            flashSetting = value
        }
        if let raw = defaults.string(forKey: DefaultsKey.aspect),
           let value = CaptureAspect(rawValue: raw) {
            currentAspect = value
        }
        if let value = TimerSetting(rawValue: defaults.integer(forKey: DefaultsKey.timer)) {
            timerSetting = value
        }
        if let value = ShutterSpeed(rawValue: defaults.integer(forKey: DefaultsKey.shutter)) {
            shutterSpeed = value
        }
        isGridOn = defaults.bool(forKey: DefaultsKey.grid)
    }

    private func refreshAllControls() {
        settingsPanel.setFlash(flashSetting)
        settingsPanel.setAspect(currentAspect)
        settingsPanel.setTimer(timerSetting)
        settingsPanel.setShutter(shutterSpeed)
        settingsPanel.setGrid(isGridOn)
        settingsPanel.setExposure(currentExposureBias)
        gridOverlay.isOn = isGridOn
        updateFlashControl()
        updateChevron()
        updateZoomControls()
        zoomDial.setZoom(currentZoom)
        modeLabel.alpha = 1
    }

    private func installAppObservers() {
        let center = NotificationCenter.default
        appObservers.append(center.addObserver(forName: UIApplication.willResignActiveNotification,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            guard let self else { return }
            self.engine.stop()
            self.cancelCountdown()
            self.hideZoomDial(animated: false)
        })
        appObservers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            guard let self, self.view.window != nil else { return }
            self.startCameraIfPossible()
        })
    }

    private func showErrorAlert(_ error: Error, offerSettings: Bool = false) {
        showAlert(title: "Ошибка", message: error.localizedDescription, offerSettings: offerSettings)
    }

    private func showAlert(title: String, message: String, offerSettings: Bool) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        if offerSettings {
            alert.addAction(UIAlertAction(title: "Настройки", style: .default) { _ in
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            })
        }
        present(alert, animated: true)
    }

    private func showToast(_ text: String) {
        toastHideWorkItem?.cancel()
        toastLabel.text = text
        toastLabel.isHidden = false
        toastLabel.alpha = 0
        toastLabel.transform = CGAffineTransform(translationX: 0, y: 6)
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.toastLabel.alpha = 1
            self.toastLabel.transform = .identity
        }
        let work = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.22, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self?.toastLabel.alpha = 0
            } completion: { _ in
                self?.toastLabel.isHidden = true
            }
        }
        toastHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7, execute: work)
    }

    private static func steppedExposure(_ value: Float) -> Float {
        let clamped = min(max(value, -2.0), 2.0)
        if clamped >= 1.95 { return 2.0 }
        if clamped <= -1.95 { return -2.0 }
        return (clamped / 0.3).rounded() * 0.3
    }
}

/// UIView, который сам подгоняет слой превью под свои границы.
final class CameraPreviewView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let previewLayer {
                layer.addSublayer(previewLayer)
            }
            setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}
