import UIKit

/// Полноэкранный просмотр последнего снимка с зумом и шарингом.
final class PhotoPreviewViewController: UIViewController, UIScrollViewDelegate {
    private let image: UIImage
    private let jpegData: Data?

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let closeButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)
    private let savedLabel = UILabel()

    init(image: UIImage, jpegData: Data?) {
        self.image = image
        self.jpegData = jpegData
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var prefersStatusBarHidden: Bool { true }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildUI()
    }

    private func buildUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .black
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)

        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark",
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)),
                             for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor(white: 0, alpha: 0.45)
        closeButton.layer.cornerRadius = 22
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.accessibilityLabel = "Закрыть"
        view.addSubview(closeButton)

        shareButton.translatesAutoresizingMaskIntoConstraints = false
        shareButton.setImage(UIImage(systemName: "square.and.arrow.up",
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)),
                             for: .normal)
        shareButton.tintColor = .white
        shareButton.backgroundColor = UIColor(white: 0, alpha: 0.45)
        shareButton.layer.cornerRadius = 22
        shareButton.addTarget(self, action: #selector(shareTapped(_:)), for: .touchUpInside)
        shareButton.accessibilityLabel = "Поделиться"
        view.addSubview(shareButton)

        savedLabel.translatesAutoresizingMaskIntoConstraints = false
        savedLabel.text = "Сохранено в «Фото»"
        savedLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        savedLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        savedLabel.textAlignment = .center
        savedLabel.backgroundColor = UIColor(white: 0, alpha: 0.45)
        savedLabel.layer.cornerRadius = 13
        savedLabel.layer.masksToBounds = true
        view.addSubview(savedLabel)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        imageView.addGestureRecognizer(doubleTap)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            savedLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            savedLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            savedLabel.heightAnchor.constraint(equalToConstant: 26),
            savedLabel.widthAnchor.constraint(equalToConstant: 150),

            shareButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            shareButton.centerYAnchor.constraint(equalTo: savedLabel.centerYAnchor),
            shareButton.widthAnchor.constraint(equalToConstant: 44),
            shareButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if scrollView.zoomScale == 1 {
            imageView.frame = scrollView.bounds
            scrollView.contentSize = scrollView.bounds.size
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) / 2, 0)
        let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(top: offsetY, left: offsetX, bottom: offsetY, right: offsetX)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > 1.01 {
            scrollView.setZoomScale(1, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let size = CGSize(width: scrollView.bounds.width / 2.5,
                              height: scrollView.bounds.height / 2.5)
            scrollView.zoom(to: CGRect(x: point.x - size.width / 2,
                                       y: point.y - size.height / 2,
                                       width: size.width,
                                       height: size.height),
                            animated: true)
        }
    }

    @objc private func shareTapped(_ sender: UIButton) {
        var items: [Any] = [image]
        if let jpegData {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("iPhone6Camera.jpg")
            if (try? jpegData.write(to: url, options: .atomic)) != nil {
                items = [url]
            }
        }

        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = sender
        activity.popoverPresentationController?.sourceRect = sender.bounds
        present(activity, animated: true)
    }
}
