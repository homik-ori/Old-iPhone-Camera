import UIKit

/// Полукруглое колесо точной настройки зума (1.0x...5.0x).
final class ZoomDialView: UIView {
    var onZoomChanged: ((CGFloat) -> Void)?

    private(set) var zoom: CGFloat = 1.0
    private let valueLabel = UILabel()
    private let captionLabel = UILabel()

    private let startDegrees: CGFloat = 200
    private let endDegrees: CGFloat = 340

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor(white: 0.0, alpha: 0.56)
        layer.cornerRadius = 26
        layer.cornerCurve = .continuous
        clipsToBounds = true
        isHidden = true
        isAccessibilityElement = true
        accessibilityLabel = "Точная настройка зума"

        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.textColor = .white
        valueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 26, weight: .semibold)
        valueLabel.textAlignment = .center
        valueLabel.text = "1.0x"

        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        captionLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        captionLabel.font = UIFont.systemFont(ofSize: 9, weight: .semibold)
        captionLabel.textAlignment = .center
        captionLabel.text = "ЗУМ"

        addSubview(valueLabel)
        addSubview(captionLabel)

        NSLayoutConstraint.activate([
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            valueLabel.topAnchor.constraint(equalTo: topAnchor, constant: 58),
            valueLabel.heightAnchor.constraint(equalToConstant: 34),

            captionLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            captionLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            captionLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 0),
            captionLabel.heightAnchor.constraint(equalToConstant: 12)
        ])
    }

    func setZoom(_ newZoom: CGFloat, notify: Bool = false) {
        let clamped = min(max(newZoom, 1.0), 5.0)
        guard abs(clamped - zoom) > 0.0001 else { return }
        zoom = clamped
        valueLabel.text = String(format: "%.1fx", zoom)
        setNeedsDisplay()
        if notify {
            onZoomChanged?(zoom)
        }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        let center = CGPoint(x: bounds.midX, y: bounds.maxY - 12)
        let radius = min(bounds.width / 2.0 - 38, bounds.height - 48)
        guard radius > 20 else { return }

        let startAngle = startDegrees * .pi / 180.0
        let endAngle = endDegrees * .pi / 180.0
        let currentAngle = startAngle + (zoom - 1.0) / 4.0 * (endAngle - startAngle)

        context.setLineCap(.round)
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.22).cgColor)
        context.setLineWidth(3)
        context.addArc(center: center, radius: radius,
                       startAngle: startAngle, endAngle: endAngle, clockwise: true)
        context.strokePath()

        if zoom > 1.001 {
            context.setStrokeColor(Theme.yellow.cgColor)
            context.setLineWidth(4)
            context.addArc(center: center, radius: radius,
                           startAngle: startAngle, endAngle: currentAngle, clockwise: true)
            context.strokePath()
        }

        // Деления: 1.0, 1.25, ... 5.0.
        for index in 0...16 {
            let fraction = CGFloat(index) / 16.0
            let angle = startAngle + fraction * (endAngle - startAngle)
            let isMajor = index % 4 == 0
            let inner = radius - (isMajor ? 9 : 5)
            let outer = radius + (isMajor ? 10 : 6)
            let start = CGPoint(x: center.x + cos(angle) * inner,
                                y: center.y + sin(angle) * inner)
            let end = CGPoint(x: center.x + cos(angle) * outer,
                              y: center.y + sin(angle) * outer)

            context.setStrokeColor((isMajor ? UIColor.white.withAlphaComponent(0.68)
                                            : UIColor.white.withAlphaComponent(0.32)).cgColor)
            context.setLineWidth(isMajor ? 1.5 : 1.0)
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
        }

        // Подписи 1x...5x.
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: UIColor.white.withAlphaComponent(0.55)
        ]
        for index in 0...4 {
            let fraction = CGFloat(index) / 4.0
            let angle = startAngle + fraction * (endAngle - startAngle)
            let labelRadius = radius + 22
            let point = CGPoint(x: center.x + cos(angle) * labelRadius,
                                y: center.y + sin(angle) * labelRadius)
            let text = "\(index + 1)x" as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: point.x - size.width / 2.0,
                                  y: point.y - size.height / 2.0),
                      withAttributes: attributes)
        }

        // Ручка.
        let knobCenter = CGPoint(x: center.x + cos(currentAngle) * radius,
                                 y: center.y + sin(currentAngle) * radius)
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: CGRect(x: knobCenter.x - 7, y: knobCenter.y - 7, width: 14, height: 14))
        context.setStrokeColor(Theme.yellow.cgColor)
        context.setLineWidth(3)
        context.strokeEllipse(in: CGRect(x: knobCenter.x - 7, y: knobCenter.y - 7, width: 14, height: 14))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateZoom(from: touches.first)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateZoom(from: touches.first)
    }

    private func updateZoom(from touch: UITouch?) {
        guard let touch else { return }
        let point = touch.location(in: self)
        let center = CGPoint(x: bounds.midX, y: bounds.maxY - 12)

        var degrees = atan2(point.y - center.y, point.x - center.x) * 180.0 / .pi
        if degrees < 0 { degrees += 360 }

        if degrees < startDegrees || degrees > endDegrees {
            // Пользователь ушёл с дуги — выбираем ближайший край по стороне.
            degrees = point.x < center.x ? startDegrees : endDegrees
        }

        let fraction = (degrees - startDegrees) / (endDegrees - startDegrees)
        let newZoom = 1.0 + fraction * 4.0
        setZoom(newZoom, notify: true)
    }
}
