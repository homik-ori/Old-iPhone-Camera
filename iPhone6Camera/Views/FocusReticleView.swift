import UIKit

/// Жёлтый квадрат фокуса с вертикальным индикатором экспозиции справа.
final class FocusReticleView: UIView {
    private let squareView = UIView()
    private let centerDot = UIView()
    private let sunImageView = UIImageView()
    private let trackView = UIView()
    private let knobView = UIView()
    private let lockImageView = UIImageView()

    private var bias: Float = 0
    private(set) var isLocked = false

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
        isUserInteractionEnabled = false
        alpha = 0

        squareView.layer.borderColor = Theme.yellow.cgColor
        squareView.layer.borderWidth = 1.5
        squareView.layer.cornerRadius = 3
        squareView.backgroundColor = .clear

        centerDot.backgroundColor = Theme.yellow.withAlphaComponent(0.9)
        centerDot.layer.cornerRadius = 1.5

        sunImageView.image = UIImage(systemName: "sun.max.fill")
        sunImageView.tintColor = Theme.yellow
        sunImageView.contentMode = .scaleAspectFit

        trackView.backgroundColor = UIColor.white.withAlphaComponent(0.55)
        knobView.backgroundColor = Theme.yellow
        knobView.layer.cornerRadius = 4

        lockImageView.image = UIImage(systemName: "lock.fill")
        lockImageView.tintColor = Theme.yellow
        lockImageView.contentMode = .scaleAspectFit
        lockImageView.isHidden = true

        addSubview(squareView)
        squareView.addSubview(centerDot)
        addSubview(sunImageView)
        addSubview(trackView)
        addSubview(knobView)
        addSubview(lockImageView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let side = min(bounds.height - 8.0, 72.0)
        squareView.frame = CGRect(x: 0,
                                  y: (bounds.height - side) / 2.0,
                                  width: side,
                                  height: side)
        squareView.layer.cornerRadius = 3
        centerDot.frame = CGRect(x: squareView.bounds.midX - 1.5,
                                 y: squareView.bounds.midY - 1.5,
                                 width: 3,
                                 height: 3)
        centerDot.layer.cornerRadius = 1.5

        sunImageView.frame = CGRect(x: side + 7, y: 0, width: 16, height: 16)
        let trackHeight = max(28, bounds.height - 28)
        trackView.frame = CGRect(x: side + 13, y: 20, width: 2, height: trackHeight)
        knobView.frame.size = CGSize(width: 8, height: 8)
        trackView.layer.cornerRadius = 1

        updateKnobPosition()
        lockImageView.frame = CGRect(x: side - 15, y: squareView.frame.minY + 3, width: 12, height: 12)
    }

    func setBias(_ newValue: Float) {
        bias = min(max(newValue, -2), 2)
        updateKnobPosition()
    }

    func setLocked(_ locked: Bool) {
        isLocked = locked
        lockImageView.isHidden = !locked
        squareView.layer.borderColor = Theme.yellow.cgColor
        squareView.layer.borderWidth = locked ? 2.0 : 1.5
    }

    func animateIn() {
        isHidden = false
        alpha = 0
        transform = CGAffineTransform(scaleX: 1.35, y: 1.35)
        UIView.animate(withDuration: 0.24,
                       delay: 0,
                       usingSpringWithDamping: 0.72,
                       initialSpringVelocity: 0.5,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    func fadeToIdle() {
        UIView.animate(withDuration: 0.35, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.alpha = 0.42
        }
    }

    func fadeOut() {
        UIView.animate(withDuration: 0.28, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.alpha = 0
        } completion: { _ in
            self.isHidden = true
            self.transform = .identity
        }
    }

    private func updateKnobPosition() {
        guard trackView.bounds.height > 0 else { return }
        let usable = max(1, trackView.bounds.height - 6)
        let offset = CGFloat(bias / 2.0) * usable / 2.0
        let centerY = trackView.frame.midY - offset
        knobView.center = CGPoint(x: trackView.frame.midX, y: centerY)
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 104, height: 80)
    }
}
