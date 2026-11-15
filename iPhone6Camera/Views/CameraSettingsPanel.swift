import UIKit

/// Выдвижная панель настроек в духе iOS 15: ряд круглых инструментов
/// и контекстная строка параметров под ним.
final class CameraSettingsPanel: UIView {
    var onFlashChange: ((FlashSetting) -> Void)?
    var onAspectChange: ((CaptureAspect) -> Void)?
    var onExposureChange: ((Float) -> Void)?
    var onTimerChange: ((TimerSetting) -> Void)?
    var onShutterChange: ((ShutterSpeed) -> Void)?
    var onGridChange: ((Bool) -> Void)?

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let contentStack = UIStackView()
    private let toolsStack = UIStackView()
    private let detailContainer = UIView()

    private let flashControl = UISegmentedControl(items: ["Авто", "Вкл", "Выкл"])
    private let aspectControl = UISegmentedControl(items: ["4:3", "16:9", "1:1"])
    private let timerControl = UISegmentedControl(items: ["Выкл", "3 с", "10 с"])
    private let exposureSlider = UISlider()
    private let exposureValueLabel = UILabel()
    private let shutterSlider = UISlider()
    private let shutterValueLabel = UILabel()
    private let gridSwitch = UISwitch()

    private var toolButtons: [SettingsToolButton] = []
    private var detailViews: [UIView] = []
    private var selectedTool = 0
    private var currentShutter: ShutterSpeed = .auto

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        clipsToBounds = true

        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 8
        contentStack.alignment = .fill
        addSubview(contentStack)

        toolsStack.translatesAutoresizingMaskIntoConstraints = false
        toolsStack.axis = .horizontal
        toolsStack.spacing = 2
        toolsStack.distribution = .fillEqually
        toolsStack.heightAnchor.constraint(equalToConstant: 58).isActive = true
        contentStack.addArrangedSubview(toolsStack)

        detailContainer.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.heightAnchor.constraint(equalToConstant: 50).isActive = true
        detailContainer.clipsToBounds = true
        contentStack.addArrangedSubview(detailContainer)

        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8)
        ])

        buildTools()
        buildDetailViews()
        styleSegmentedControls()
        selectTool(0)
    }

    private func buildTools() {
        let definitions: [(String, String)] = [
            ("bolt.fill", "Вспышка"),
            ("aspectratio", "Формат"),
            ("plusminus.circle", "Экспоз."),
            ("timer", "Таймер"),
            ("stopwatch", "ВЫДЕРЖКА"),
            ("grid", "Сетка")
        ]

        for (index, definition) in definitions.enumerated() {
            let button = SettingsToolButton(iconName: definition.0, title: definition.1)
            button.tag = index
            button.addTarget(self, action: #selector(toolTapped(_:)), for: .touchUpInside)
            toolsStack.addArrangedSubview(button)
            toolButtons.append(button)
        }
    }

    private func buildDetailViews() {
        flashControl.addTarget(self, action: #selector(flashChanged), for: .valueChanged)
        aspectControl.addTarget(self, action: #selector(aspectChanged), for: .valueChanged)
        timerControl.addTarget(self, action: #selector(timerChanged), for: .valueChanged)

        exposureSlider.minimumValue = -2.0
        exposureSlider.maximumValue = 2.0
        exposureSlider.value = 0
        exposureSlider.minimumTrackTintColor = Theme.yellow
        exposureSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.25)
        exposureSlider.thumbTintColor = .white
        exposureSlider.addTarget(self, action: #selector(exposureChanged), for: .valueChanged)

        exposureValueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        exposureValueLabel.textColor = Theme.yellow
        exposureValueLabel.textAlignment = .right
        exposureValueLabel.text = "+0.0"

        let exposureTitle = UILabel()
        exposureTitle.text = "EV"
        exposureTitle.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        exposureTitle.textColor = UIColor.white.withAlphaComponent(0.65)
        exposureTitle.setContentHuggingPriority(.required, for: .horizontal)

        exposureValueLabel.setContentHuggingPriority(.required, for: .horizontal)
        exposureValueLabel.widthAnchor.constraint(equalToConstant: 42).isActive = true

        let exposureHeader = UIStackView(arrangedSubviews: [exposureTitle, UIView(), exposureValueLabel])
        exposureHeader.axis = .horizontal
        exposureHeader.spacing = 8
        exposureHeader.alignment = .center

        let exposureStack = UIStackView(arrangedSubviews: [exposureHeader, exposureSlider])
        exposureStack.axis = .vertical
        exposureStack.spacing = 0
        exposureStack.alignment = .fill

        shutterSlider.minimumValue = 0
        shutterSlider.maximumValue = Float(ShutterSpeed.allCases.count - 1)
        shutterSlider.value = 0
        shutterSlider.minimumTrackTintColor = Theme.yellow
        shutterSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.25)
        shutterSlider.thumbTintColor = .white
        shutterSlider.addTarget(self, action: #selector(shutterChanged), for: .valueChanged)

        shutterValueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        shutterValueLabel.textColor = Theme.yellow
        shutterValueLabel.textAlignment = .right
        shutterValueLabel.text = ShutterSpeed.auto.title

        let shutterTitle = UILabel()
        shutterTitle.text = "ВЫДЕРЖКА"
        shutterTitle.font = UIFont.systemFont(ofSize: 10, weight: .semibold)
        shutterTitle.textColor = UIColor.white.withAlphaComponent(0.65)
        shutterTitle.setContentHuggingPriority(.required, for: .horizontal)

        shutterValueLabel.setContentHuggingPriority(.required, for: .horizontal)
        shutterValueLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true

        let shutterHeader = UIStackView(arrangedSubviews: [shutterTitle, UIView(), shutterValueLabel])
        shutterHeader.axis = .horizontal
        shutterHeader.spacing = 8
        shutterHeader.alignment = .center

        let shutterStack = UIStackView(arrangedSubviews: [shutterHeader, shutterSlider])
        shutterStack.axis = .vertical
        shutterStack.spacing = 0
        shutterStack.alignment = .fill

        gridSwitch.onTintColor = Theme.yellow
        gridSwitch.addTarget(self, action: #selector(gridChanged), for: .valueChanged)

        let gridTitle = UILabel()
        gridTitle.text = "Правило третей"
        gridTitle.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        gridTitle.textColor = .white

        let spacer = UIView()
        let gridStack = UIStackView(arrangedSubviews: [gridTitle, spacer, gridSwitch])
        gridStack.axis = .horizontal
        gridStack.spacing = 10
        gridStack.alignment = .center

        detailViews = [flashControl, aspectControl, exposureStack, timerControl, shutterStack, gridStack]
        for view in detailViews {
            view.translatesAutoresizingMaskIntoConstraints = false
            detailContainer.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor, constant: 4),
                view.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor, constant: -4),
                view.centerYAnchor.constraint(equalTo: detailContainer.centerYAnchor)
            ])
            view.isHidden = true
        }
    }

    private func styleSegmentedControls() {
        for control in [flashControl, aspectControl, timerControl] {
            control.selectedSegmentTintColor = Theme.yellow
            control.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
            control.setTitleTextAttributes([
                .foregroundColor: UIColor.white,
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold)
            ], for: .normal)
            control.setTitleTextAttributes([
                .foregroundColor: UIColor.black,
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold)
            ], for: .selected)
        }
    }

    // MARK: - Публичное состояние

    func setFlash(_ setting: FlashSetting) {
        flashControl.selectedSegmentIndex = FlashSetting.allCases.firstIndex(of: setting) ?? 0
    }

    func setAspect(_ aspect: CaptureAspect) {
        aspectControl.selectedSegmentIndex = CaptureAspect.allCases.firstIndex(of: aspect) ?? 0
    }

    func setTimer(_ timer: TimerSetting) {
        timerControl.selectedSegmentIndex = TimerSetting.allCases.firstIndex(of: timer) ?? 0
    }

    func setGrid(_ isOn: Bool) {
        gridSwitch.isOn = isOn
    }

    func setExposure(_ value: Float) {
        exposureSlider.value = min(max(value, -2), 2)
        exposureValueLabel.text = Self.formatExposure(exposureSlider.value)
    }

    func setShutter(_ speed: ShutterSpeed) {
        currentShutter = speed
        shutterSlider.value = Float(speed.rawValue)
        shutterValueLabel.text = speed.title
    }

    func selectTool(_ index: Int) {
        guard index >= 0, index < detailViews.count else { return }
        selectedTool = index
        for (buttonIndex, button) in toolButtons.enumerated() {
            button.isSelected = buttonIndex == index
        }
        for (viewIndex, view) in detailViews.enumerated() {
            view.isHidden = viewIndex != index
        }
    }

    // MARK: - Действия

    @objc private func toolTapped(_ sender: SettingsToolButton) {
        selectTool(sender.tag)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @objc private func flashChanged() {
        let index = flashControl.selectedSegmentIndex
        guard index >= 0, index < FlashSetting.allCases.count else { return }
        onFlashChange?(FlashSetting.allCases[index])
    }

    @objc private func aspectChanged() {
        let index = aspectControl.selectedSegmentIndex
        guard index >= 0, index < CaptureAspect.allCases.count else { return }
        onAspectChange?(CaptureAspect.allCases[index])
    }

    @objc private func timerChanged() {
        let index = timerControl.selectedSegmentIndex
        guard index >= 0, index < TimerSetting.allCases.count else { return }
        onTimerChange?(TimerSetting.allCases[index])
    }

    @objc private func gridChanged() {
        onGridChange?(gridSwitch.isOn)
    }

    @objc private func exposureChanged() {
        let stepped = (exposureSlider.value / 0.3).rounded() * 0.3
        let clamped = min(max(stepped, -2.0), 2.0)
        exposureSlider.value = clamped
        exposureValueLabel.text = Self.formatExposure(clamped)
        onExposureChange?(clamped)
    }

    @objc private func shutterChanged() {
        let index = Int(shutterSlider.value.rounded())
        guard let speed = ShutterSpeed(rawValue: index) else { return }
        shutterSlider.value = Float(index)
        guard speed != currentShutter else { return }
        currentShutter = speed
        shutterValueLabel.text = speed.title
        UISelectionFeedbackGenerator().selectionChanged()
        onShutterChange?(speed)
    }

    private static func formatExposure(_ value: Float) -> String {
        String(format: "%+.1f", Double(value))
    }
}

private final class SettingsToolButton: UIControl {
    private let circleView = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    override var isSelected: Bool {
        didSet { updateAppearance() }
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12) {
                self.alpha = self.isHighlighted ? 0.65 : 1.0
            }
        }
    }

    init(iconName: String, title: String) {
        super.init(frame: .zero)
        setup(iconName: iconName, title: title)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(iconName: String, title: String) {
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button

        circleView.translatesAutoresizingMaskIntoConstraints = false
        circleView.isUserInteractionEnabled = false
        circleView.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        circleView.layer.cornerRadius = 20
        circleView.layer.cornerCurve = .continuous

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isUserInteractionEnabled = false
        iconView.image = UIImage(systemName: iconName,
                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .white

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isUserInteractionEnabled = false
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 9.5, weight: .medium)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8

        addSubview(circleView)
        circleView.addSubview(iconView)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            circleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            circleView.topAnchor.constraint(equalTo: topAnchor),
            circleView.widthAnchor.constraint(equalToConstant: 40),
            circleView.heightAnchor.constraint(equalToConstant: 40),

            iconView.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            titleLabel.topAnchor.constraint(equalTo: circleView.bottomAnchor, constant: 3),
            titleLabel.heightAnchor.constraint(equalToConstant: 12)
        ])

        updateAppearance()
    }

    private func updateAppearance() {
        circleView.backgroundColor = isSelected ? Theme.yellow : UIColor(white: 1.0, alpha: 0.12)
        iconView.tintColor = isSelected ? .black : .white
        titleLabel.textColor = isSelected ? Theme.yellow : UIColor.white.withAlphaComponent(0.65)
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}
