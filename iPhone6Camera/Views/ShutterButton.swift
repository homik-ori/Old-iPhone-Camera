import UIKit

/// Большая белая кнопка спуска с внутренним кольцом и мягким сжатием.
final class ShutterButton: UIControl {
    private let ringView = UIView()
    private let innerView = UIView()

    override var isHighlighted: Bool {
        didSet {
            let pressed = isHighlighted
            UIView.animate(withDuration: pressed ? 0.08 : 0.18,
                           delay: 0,
                           usingSpringWithDamping: 0.7,
                           initialSpringVelocity: 0.4,
                           options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.transform = pressed ? CGAffineTransform(scaleX: 0.92, y: 0.92) : .identity
                self.innerView.transform = pressed ? CGAffineTransform(scaleX: 0.86, y: 0.86) : .identity
            }
        }
    }

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
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "Спуск затвора"

        ringView.translatesAutoresizingMaskIntoConstraints = false
        ringView.isUserInteractionEnabled = false
        ringView.layer.borderColor = UIColor.white.cgColor
        ringView.layer.borderWidth = 4

        innerView.translatesAutoresizingMaskIntoConstraints = false
        innerView.isUserInteractionEnabled = false
        innerView.backgroundColor = .white

        addSubview(ringView)
        addSubview(innerView)

        NSLayoutConstraint.activate([
            ringView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            ringView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            ringView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            ringView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),

            innerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            innerView.centerYAnchor.constraint(equalTo: centerYAnchor),
            innerView.widthAnchor.constraint(equalTo: widthAnchor, constant: -22),
            innerView.heightAnchor.constraint(equalTo: heightAnchor, constant: -22)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        ringView.layer.cornerRadius = ringView.bounds.width / 2.0
        innerView.layer.cornerRadius = innerView.bounds.width / 2.0
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 82, height: 82)
    }
}
