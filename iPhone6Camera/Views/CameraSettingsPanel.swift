import UIKit

/// Выдвижная панель настроек в духе iOS 15: прокручиваемый ряд инструментов,
/// заголовок выбранного раздела и контекстный контрол.
final class CameraSettingsPanel: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var onFlashChange: ((FlashSetting) -> Void)?
    var onAspectChange: ((CaptureAspect) -> Void)?
    var onExposureChange: ((Float) -> Void)?
    var onTimerChange: ((TimerSetting) -> Void)?
    var onShutterChange: ((ShutterSpeed) -> Void)?
    var onFilterChange: ((CameraFilter) -> Void)?
    var onPaletteChange: ((PaletteTint) -> Void)?
    var onPaletteIntensityChange: ((Float) -> Void)?
    var onRetroChange: ((Float) -> Void)?
    var onGridChange: ((Bool) -> Void)?
    var onContentHeightChange: ((CGFloat) -> Void)?

    private enum Tool: Int, CaseIterable {
        case flash
        case format
        case exposure
        case timer
        case filters
        case retro
        case shutter
        case grid
    }

    private static let toolTitles = ["Вспышка", "Формат", "Экспоз.", "Таймер", "Фильтры", "ВАЙБ 6", "Выдержка", "Сетка"]
    private static let toolIcons = ["bolt.fill", "aspectratio", "plusminus.circle", "timer", "camera.filters", "slider.horizontal.3", "stopwatch", "grid"]
    private static let detailTitles = ["ВСПЫШКА", "ФОРМАТ", "ЭКСПОЗИЦИЯ", "ТАЙМЕР", "ФИЛЬТРЫ", "ВАЙБ 6", "ВЫДЕРЖКА", "СЕТКА"]

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let contentStack = UIStackView()
    private let toolsScroll = UIScrollView()
    private let toolsStack = UIStackView()
    private let titleLabel = UILabel()
    private let detailContainer = UIView()
    private var detailHeightConstraint: NSLayoutConstraint!

    private let flashControl = UISegmentedControl(items: ["Авто", "Вкл", "Выкл"])
    private let aspectControl = UISegmentedControl(items: ["4:3", "16:9", "1:1"])
    private let timerControl = UISegmentedControl(items: ["Выкл", "3 с", "10 с"])
    private let exposureSlider = UISlider()
    private let exposureValueLabel = UILabel()
    private let shutterSlider = UISlider()
    private let shutterValueLabel = UILabel()
    private let retroSlider = UISlider()
    private let retroValueLabel = UILabel()
    private let gridSwitch = UISwitch()
    private let filterCollection: UICollectionView
    private let paletteBar = UIView()
    private let paletteIntensitySlider = UISlider()
    private let paletteValueLabel = UILabel()
    private var paletteButtons: [UIButton] = []

    private var toolButtons: [SettingsToolButton] = []
    private var detailViews: [UIView] = []
    private var selectedTool: Tool = .flash
    private var look = LookSettings.default
    private var currentFlash: FlashSetting = .auto
    private var currentAspect: CaptureAspect = .fourThree
    private var currentTimer: TimerSetting = .off
    private var currentShutter: ShutterSpeed = .auto
    private var currentGrid = false
    private var currentExposure: Float = 0
    private var lastRetroPercent = 65

    var preferredHeight: CGFloat {
        let detailHeight: CGFloat
        switch selectedTool {
        case .filters:
            detailHeight = look.filter == .palette ? 192 : 88
        case .exposure, .retro, .shutter:
            detailHeight = 56
        default:
            detailHeight = 44
        }
        return 10 + 60 + 8 + 16 + 8 + detailHeight + 10
    }

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 70, height: 84)
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
        filterCollection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 70, height: 84)
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
        filterCollection = UICollectionView(frame: .zero, collectionViewLayout: layout)
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

        toolsScroll.translatesAutoresizingMaskIntoConstraints = false
        toolsScroll.showsHorizontalScrollIndicator = false
        toolsScroll.alwaysBounceHorizontal = false
        toolsScroll.heightAnchor.constraint(equalToConstant: 60).isActive = true
        contentStack.addArrangedSubview(toolsScroll)

        toolsStack.translatesAutoresizingMaskIntoConstraints = false
        toolsStack.axis = .horizontal
        toolsStack.spacing = 4
        toolsStack.alignment = .fill
        toolsScroll.addSubview(toolsStack)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = Theme.yellow
        titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        titleLabel.heightAnchor.constraint(equalToConstant: 16).isActive = true
        contentStack.addArrangedSubview(titleLabel)

        detailContainer.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.clipsToBounds = true
        detailHeightConstraint = detailContainer.heightAnchor.constraint(equalToConstant: 44)
        detailHeightConstraint.isActive = true
        contentStack.addArrangedSubview(detailContainer)

        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),

            toolsStack.leadingAnchor.constraint(equalTo: toolsScroll.contentLayoutGuide.leadingAnchor),
            toolsStack.trailingAnchor.constraint(equalTo: toolsScroll.contentLayoutGuide.trailingAnchor),
            toolsStack.topAnchor.constraint(equalTo: toolsScroll.contentLayoutGuide.topAnchor),
            toolsStack.bottomAnchor.constraint(equalTo: toolsScroll.contentLayoutGuide.bottomAnchor),
            toolsStack.heightAnchor.constraint(equalTo: toolsScroll.frameLayoutGuide.heightAnchor)
        ])

        buildTools()
        buildDetailViews()
        styleSegmentedControls()
        filterCollection.dataSource = self
        filterCollection.delegate = self
        filterCollection.register(FilterCell.self, forCellWithReuseIdentifier: "FilterCell")
        filterCollection.backgroundColor = .clear
        filterCollection.showsHorizontalScrollIndicator = false
        filterCollection.decelerationRate = .fast
        selectTool(Tool.flash.rawValue)
    }

    private func buildTools() {
        for (index, title) in Self.toolTitles.enumerated() {
            let button = SettingsToolButton(iconName: Self.toolIcons[index], title: title)
            button.tag = index
            button.widthAnchor.constraint(equalToConstant: 52).isActive = true
            button.addTarget(self, action: #selector(toolTapped(_:)), for: .touchUpInside)
            toolsStack.addArrangedSubview(button)
            toolButtons.append(button)
        }
    }

    private func buildDetailViews() {
        flashControl.addTarget(self, action: #selector(flashChanged), for: .valueChanged)
        aspectControl.addTarget(self, action: #selector(aspectChanged), for: .valueChanged)
        timerControl.addTarget(self, action: #selector(timerChanged), for: .valueChanged)

        configureSlider(exposureSlider, minimum: -2, maximum: 2, value: 0)
        exposureSlider.addTarget(self, action: #selector(exposureChanged), for: .valueChanged)
        exposureValueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        exposureValueLabel.textColor = Theme.yellow
        exposureValueLabel.textAlignment = .right
        exposureValueLabel.text = "+0.0"
        exposureValueLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let exposureTitle = detailLabel("EV")
        let exposureHeader = UIStackView(arrangedSubviews: [exposureTitle, UIView(), exposureValueLabel])
        exposureHeader.axis = .horizontal
        exposureHeader.spacing = 8
        exposureHeader.alignment = .center
        let exposureStack = UIStackView(arrangedSubviews: [exposureHeader, exposureSlider])
        exposureStack.axis = .vertical
        exposureStack.spacing = 0

        configureSlider(shutterSlider, minimum: 0, maximum: Float(ShutterSpeed.allCases.count - 1), value: 0)
        shutterSlider.addTarget(self, action: #selector(shutterChanged), for: .valueChanged)
        shutterValueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        shutterValueLabel.textColor = Theme.yellow
        shutterValueLabel.textAlignment = .right
        shutterValueLabel.text = ShutterSpeed.auto.title
        shutterValueLabel.widthAnchor.constraint(equalToConstant: 68).isActive = true
        let shutterTitle = detailLabel("ВЫДЕРЖКА")
        let shutterHeader = UIStackView(arrangedSubviews: [shutterTitle, UIView(), shutterValueLabel])
        shutterHeader.axis = .horizontal
        shutterHeader.spacing = 8
        shutterHeader.alignment = .center
        let shutterStack = UIStackView(arrangedSubviews: [shutterHeader, shutterSlider])
        shutterStack.axis = .vertical
        shutterStack.spacing = 0

        configureSlider(retroSlider, minimum: 0, maximum: 1, value: 0.65)
        retroSlider.addTarget(self, action: #selector(retroChanged), for: .valueChanged)
        retroValueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        retroValueLabel.textColor = Theme.yellow
        retroValueLabel.textAlignment = .right
        retroValueLabel.text = "65%"
        retroValueLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        let retroTitle = detailLabel("ВАЙБ 6")
        let retroHeader = UIStackView(arrangedSubviews: [retroTitle, UIView(), retroValueLabel])
        retroHeader.axis = .horizontal
        retroHeader.spacing = 8
        retroHeader.alignment = .center
        let retroStack = UIStackView(arrangedSubviews: [retroHeader, retroSlider])
        retroStack.axis = .vertical
        retroStack.spacing = 0

        gridSwitch.onTintColor = Theme.yellow
        gridSwitch.addTarget(self, action: #selector(gridChanged), for: .valueChanged)
        let gridTitle = UILabel()
        gridTitle.text = "Правило третей"
        gridTitle.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        gridTitle.textColor = .white
        let gridStack = UIStackView(arrangedSubviews: [gridTitle, UIView(), gridSwitch])
        gridStack.axis = .horizontal
        gridStack.spacing = 10
        gridStack.alignment = .center

        let filtersView = buildFiltersView()

        detailViews = [flashControl, aspectControl, exposureStack, timerControl, filtersView, retroStack, shutterStack, gridStack]
        for view in detailViews {
            view.translatesAutoresizingMaskIntoConstraints = false
            detailContainer.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor, constant: 4),
                view.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor, constant: -4)
            ])
            if view === filtersView {
                NSLayoutConstraint.activate([
                    view.topAnchor.constraint(equalTo: detailContainer.topAnchor),
                    view.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor)
                ])
            } else {
                view.centerYAnchor.constraint(equalTo: detailContainer.centerYAnchor).isActive = true
            }
            view.isHidden = true
        }
    }

    private func buildFiltersView() -> UIView {
        let wrapper = UIView()
        wrapper.clipsToBounds = true

        filterCollection.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(filterCollection)

        paletteBar.translatesAutoresizingMaskIntoConstraints = false
        paletteBar.isHidden = true
        wrapper.addSubview(paletteBar)

        let tintStack = UIStackView()
        tintStack.translatesAutoresizingMaskIntoConstraints = false
        tintStack.axis = .horizontal
        tintStack.spacing = 4
        tintStack.distribution = .fillEqually
        paletteBar.addSubview(tintStack)

        for (index, tint) in PaletteTint.allCases.enumerated() {
            let button = UIButton(type: .custom)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.tag = index
            button.backgroundColor = tint.color
            button.layer.cornerRadius = 15
            button.layer.borderWidth = 2
            button.layer.borderColor = UIColor.clear.cgColor
            button.accessibilityLabel = tint.title
            button.addTarget(self, action: #selector(paletteTapped(_:)), for: .touchUpInside)
            button.widthAnchor.constraint(equalToConstant: 30).isActive = true
            button.heightAnchor.constraint(equalToConstant: 30).isActive = true
            paletteButtons.append(button)

            let label = UILabel()
            label.text = tint.shortTitle
            label.font = UIFont.systemFont(ofSize: 8.5, weight: .medium)
            label.textColor = UIColor.white.withAlphaComponent(0.65)
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.7

            let item = UIStackView(arrangedSubviews: [button, label])
            item.axis = .vertical
            item.alignment = .center
            item.spacing = 4
            tintStack.addArrangedSubview(item)
        }

        let paletteTitle = detailLabel("НАСЫЩЕННОСТЬ")
        paletteValueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        paletteValueLabel.textColor = Theme.yellow
        paletteValueLabel.textAlignment = .right
        paletteValueLabel.text = "35%"
        paletteValueLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true

        let paletteHeader = UIStackView(arrangedSubviews: [paletteTitle, UIView(), paletteValueLabel])
        paletteHeader.axis = .horizontal
        paletteHeader.spacing = 8
        paletteHeader.alignment = .center

        paletteIntensitySlider.translatesAutoresizingMaskIntoConstraints = false
        configureSlider(paletteIntensitySlider, minimum: 0, maximum: 1, value: 0.35)
        paletteIntensitySlider.addTarget(self, action: #selector(paletteIntensityChanged), for: .valueChanged)
        let intensityStack = UIStackView(arrangedSubviews: [paletteHeader, paletteIntensitySlider])
        intensityStack.translatesAutoresizingMaskIntoConstraints = false
        intensityStack.axis = .vertical
        intensityStack.spacing = 0
        paletteBar.addSubview(intensityStack)

        NSLayoutConstraint.activate([
            filterCollection.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            filterCollection.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            filterCollection.topAnchor.constraint(equalTo: wrapper.topAnchor),
            filterCollection.heightAnchor.constraint(equalToConstant: 84),

            paletteBar.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            paletteBar.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            paletteBar.topAnchor.constraint(equalTo: filterCollection.bottomAnchor, constant: 8),
            paletteBar.heightAnchor.constraint(equalToConstant: 100),

            tintStack.leadingAnchor.constraint(equalTo: paletteBar.leadingAnchor),
            tintStack.trailingAnchor.constraint(equalTo: paletteBar.trailingAnchor),
            tintStack.topAnchor.constraint(equalTo: paletteBar.topAnchor),
            tintStack.heightAnchor.constraint(equalToConstant: 46),

            intensityStack.leadingAnchor.constraint(equalTo: paletteBar.leadingAnchor),
            intensityStack.trailingAnchor.constraint(equalTo: paletteBar.trailingAnchor),
            intensityStack.bottomAnchor.constraint(equalTo: paletteBar.bottomAnchor),
            intensityStack.heightAnchor.constraint(equalToConstant: 46)
        ])

        return wrapper
    }

    private func configureSlider(_ slider: UISlider, minimum: Float, maximum: Float, value: Float) {
        slider.minimumValue = minimum
        slider.maximumValue = maximum
        slider.value = value
        slider.minimumTrackTintColor = Theme.yellow
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.25)
        slider.thumbTintColor = .white
    }

    private func detailLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 10, weight: .semibold)
        label.textColor = UIColor.white.withAlphaComponent(0.65)
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
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
        currentFlash = setting
        flashControl.selectedSegmentIndex = FlashSetting.allCases.firstIndex(of: setting) ?? 0
    }

    func setAspect(_ aspect: CaptureAspect) {
        currentAspect = aspect
        aspectControl.selectedSegmentIndex = CaptureAspect.allCases.firstIndex(of: aspect) ?? 0
    }

    func setTimer(_ timer: TimerSetting) {
        currentTimer = timer
        timerControl.selectedSegmentIndex = TimerSetting.allCases.firstIndex(of: timer) ?? 0
    }

    func setShutter(_ speed: ShutterSpeed) {
        currentShutter = speed
        shutterSlider.value = Float(speed.rawValue)
        shutterValueLabel.text = speed.title
    }

    func setGrid(_ isOn: Bool) {
        currentGrid = isOn
        gridSwitch.isOn = isOn
    }

    func setExposure(_ value: Float) {
        currentExposure = min(max(value, -2), 2)
        exposureSlider.value = currentExposure
        exposureValueLabel.text = Self.formatExposure(currentExposure)
    }

    func setLook(_ newLook: LookSettings) {
        look = newLook
        retroSlider.value = look.retro
        retroValueLabel.text = "\(Int((look.retro * 100).rounded()))%"
        lastRetroPercent = Int((look.retro * 100).rounded())
        paletteIntensitySlider.value = look.paletteIntensity
        paletteValueLabel.text = "\(Int((look.paletteIntensity * 100).rounded()))%"
        updatePaletteButtons()
        filterCollection.reloadData()
        if let index = CameraFilter.allCases.firstIndex(of: look.filter) {
            let indexPath = IndexPath(item: index, section: 0)
            filterCollection.layoutIfNeeded()
            filterCollection.selectItem(at: indexPath, animated: false, scrollPosition: [])
            filterCollection.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: false)
        }
        updatePaletteVisibility()
        if selectedTool == .filters {
            updateDetailHeight()
        }
    }

    func scrollFiltersToSelection() {
        guard let index = CameraFilter.allCases.firstIndex(of: look.filter) else { return }
        filterCollection.layoutIfNeeded()
        filterCollection.scrollToItem(at: IndexPath(item: index, section: 0),
                                      at: .centeredHorizontally,
                                      animated: false)
    }

    func selectTool(_ index: Int) {
        guard let tool = Tool(rawValue: index) else { return }
        selectedTool = tool
        for (buttonIndex, button) in toolButtons.enumerated() {
            button.isSelected = buttonIndex == index
        }
        let title = Self.detailTitles[index]
        titleLabel.attributedText = NSAttributedString(string: title, attributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: Theme.yellow,
            .kern: 1.2
        ])
        for (viewIndex, view) in detailViews.enumerated() {
            view.isHidden = viewIndex != index
        }
        updateDetailHeight()
        scrollToolIntoView(at: index)
        if tool == .filters {
            DispatchQueue.main.async { [weak self] in
                self?.scrollFiltersToSelection()
            }
        }
    }

    private func updateDetailHeight() {
        let height: CGFloat
        switch selectedTool {
        case .filters:
            height = look.filter == .palette ? 192 : 88
        case .exposure, .retro, .shutter:
            height = 56
        default:
            height = 44
        }
        detailHeightConstraint.constant = height
        layoutIfNeeded()
        onContentHeightChange?(preferredHeight)
    }

    private func updatePaletteVisibility() {
        let showsPalette = look.filter == .palette
        paletteBar.isHidden = !showsPalette
        if selectedTool == .filters {
            updateDetailHeight()
        }
    }

    private func updatePaletteButtons() {
        for (index, button) in paletteButtons.enumerated() {
            let tint = PaletteTint.allCases[index]
            let selected = tint == look.palette
            button.layer.borderColor = selected ? Theme.yellow.cgColor : UIColor.clear.cgColor
            button.transform = selected ? CGAffineTransform(scaleX: 1.08, y: 1.08) : .identity
        }
    }

    private func scrollToolIntoView(at index: Int) {
        guard index >= 0, index < toolButtons.count else { return }
        let frame = toolsStack.convert(toolButtons[index].frame, to: toolsScroll)
        toolsScroll.scrollRectToVisible(frame.insetBy(dx: -8, dy: 0), animated: true)
    }

    // MARK: - Действия

    @objc private func toolTapped(_ sender: SettingsToolButton) {
        selectTool(sender.tag)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @objc private func flashChanged() {
        let index = flashControl.selectedSegmentIndex
        guard index >= 0, index < FlashSetting.allCases.count else { return }
        let setting = FlashSetting.allCases[index]
        currentFlash = setting
        onFlashChange?(setting)
    }

    @objc private func aspectChanged() {
        let index = aspectControl.selectedSegmentIndex
        guard index >= 0, index < CaptureAspect.allCases.count else { return }
        let aspect = CaptureAspect.allCases[index]
        currentAspect = aspect
        onAspectChange?(aspect)
    }

    @objc private func timerChanged() {
        let index = timerControl.selectedSegmentIndex
        guard index >= 0, index < TimerSetting.allCases.count else { return }
        let timer = TimerSetting.allCases[index]
        currentTimer = timer
        onTimerChange?(timer)
    }

    @objc private func gridChanged() {
        currentGrid = gridSwitch.isOn
        onGridChange?(gridSwitch.isOn)
    }

    @objc private func exposureChanged() {
        let stepped = (exposureSlider.value / 0.3).rounded() * 0.3
        let clamped = min(max(stepped, -2.0), 2.0)
        exposureSlider.value = clamped
        currentExposure = clamped
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

    @objc private func retroChanged() {
        let stepped = (retroSlider.value * 20.0).rounded() / 20.0
        retroSlider.value = stepped
        look.retro = stepped
        let percent = Int((stepped * 100).rounded())
        retroValueLabel.text = "\(percent)%"
        if percent != lastRetroPercent {
            lastRetroPercent = percent
            UISelectionFeedbackGenerator().selectionChanged()
        }
        onRetroChange?(stepped)
    }

    @objc private func paletteTapped(_ sender: UIButton) {
        guard sender.tag >= 0, sender.tag < PaletteTint.allCases.count else { return }
        let tint = PaletteTint.allCases[sender.tag]
        look.palette = tint
        updatePaletteButtons()
        UISelectionFeedbackGenerator().selectionChanged()
        onPaletteChange?(tint)
    }

    @objc private func paletteIntensityChanged() {
        look.paletteIntensity = paletteIntensitySlider.value
        paletteValueLabel.text = "\(Int((look.paletteIntensity * 100).rounded()))%"
        onPaletteIntensityChange?(look.paletteIntensity)
    }

    private static func formatExposure(_ value: Float) -> String {
        String(format: "%+.1f", Double(value))
    }

    // MARK: - Фильтры

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        CameraFilter.allCases.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "FilterCell", for: indexPath) as! FilterCell
        let filter = CameraFilter.allCases[indexPath.item]
        cell.configure(filter: filter, selected: filter == look.filter)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let filter = CameraFilter.allCases[indexPath.item]
        guard filter != look.filter else { return }
        look.filter = filter
        filterCollection.reloadData()
        filterCollection.selectItem(at: indexPath, animated: false, scrollPosition: [])
        filterCollection.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
        updatePaletteVisibility()
        UISelectionFeedbackGenerator().selectionChanged()
        onFilterChange?(filter)
    }
}

// MARK: - Tool button

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
        circleView.layer.cornerRadius = 22
        circleView.layer.cornerCurve = .continuous

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isUserInteractionEnabled = false
        iconView.image = UIImage(systemName: iconName,
                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
            ?? UIImage(systemName: "camera.fill",
                       withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .white

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isUserInteractionEnabled = false
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 9, weight: .medium)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.65

        addSubview(circleView)
        circleView.addSubview(iconView)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            circleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            circleView.topAnchor.constraint(equalTo: topAnchor),
            circleView.widthAnchor.constraint(equalToConstant: 44),
            circleView.heightAnchor.constraint(equalToConstant: 44),

            iconView.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 21),
            iconView.heightAnchor.constraint(equalToConstant: 21),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            titleLabel.topAnchor.constraint(equalTo: circleView.bottomAnchor, constant: 2),
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

// MARK: - Filter cell

private final class FilterCell: UICollectionViewCell {
    private let swatchView = UIView()
    private let gradientLayer = CAGradientLayer()
    private let titleLabel = UILabel()

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
        swatchView.layer.cornerRadius = 8
        swatchView.layer.cornerCurve = .continuous
        swatchView.clipsToBounds = true
        swatchView.layer.insertSublayer(gradientLayer, at: 0)
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        contentView.addSubview(swatchView)

        titleLabel.font = UIFont.systemFont(ofSize: 8.5, weight: .medium)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        contentView.addSubview(titleLabel)

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        swatchView.frame = CGRect(x: (bounds.width - 54) / 2, y: 0, width: 54, height: 54)
        gradientLayer.frame = swatchView.bounds
        titleLabel.frame = CGRect(x: 0, y: 58, width: bounds.width, height: 24)
    }

    func configure(filter: CameraFilter, selected: Bool) {
        gradientLayer.colors = filter.swatchColors.map(\.cgColor)
        titleLabel.text = filter.title
        titleLabel.textColor = selected ? Theme.yellow : UIColor.white.withAlphaComponent(0.75)
        swatchView.layer.borderWidth = selected ? 2 : 0
        swatchView.layer.borderColor = Theme.yellow.cgColor
        accessibilityLabel = filter.title
        accessibilityTraits = selected ? [.button, .selected] : .button
    }
}
