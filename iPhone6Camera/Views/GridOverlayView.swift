import UIKit

/// Тонкая сетка правила третей поверх видоискателя.
final class GridOverlayView: UIView {
    var isOn: Bool = false {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    override func draw(_ rect: CGRect) {
        guard isOn, rect.width > 0, rect.height > 0 else { return }

        let path = UIBezierPath()
        let lineWidth: CGFloat = 0.5

        for index in 1...2 {
            let x = rect.width * CGFloat(index) / 3.0
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))

            let y = rect.height * CGFloat(index) / 3.0
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }

        UIColor.white.withAlphaComponent(0.30).setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}
