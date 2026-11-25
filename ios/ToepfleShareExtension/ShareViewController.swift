import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

    private let containerCard: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.secondarySystemGroupedBackground
        view.layer.cornerRadius = 24
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.18
        view.layer.shadowRadius = 20
        view.layer.shadowOffset = CGSize(width: 0, height: 10)
        return view
    }()

    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 44, weight: .bold)
        imageView.image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: config)
        imageView.tintColor = UIColor.systemGreen
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "In Töpfle gespeichert"
        label.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        label.textColor = UIColor.label
        label.textAlignment = .center
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Rezept wird lokal vorbereitet…"
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = UIColor.secondaryLabel
        label.textAlignment = .center
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        setupUI()
        extractAndQueueContent()
    }

    private func setupUI() {
        view.addSubview(containerCard)
        containerCard.addSubview(iconImageView)
        containerCard.addSubview(titleLabel)
        containerCard.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            containerCard.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerCard.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerCard.widthAnchor.constraint(equalToConstant: 280),
            containerCard.heightAnchor.constraint(equalToConstant: 180),

            iconImageView.topAnchor.constraint(equalTo: containerCard.topAnchor, constant: 24),
            iconImageView.centerXAnchor.constraint(equalTo: containerCard.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 48),
            iconImageView.heightAnchor.constraint(equalToConstant: 48),

            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: containerCard.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: containerCard.trailingAnchor, constant: -16),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: containerCard.leadingAnchor, constant: 16),
            subtitleLabel.trailingAnchor.constraint(equalTo: containerCard.trailingAnchor, constant: -16)
        ])

        containerCard.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        containerCard.alpha = 0
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.5, options: .curveEaseOut) {
            self.containerCard.transform = .identity
            self.containerCard.alpha = 1.0
        }
    }

    private func extractAndQueueContent() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments,
              !attachments.isEmpty else {
            finishAndDismiss(delay: 0.6)
            return
        }

        let group = DispatchGroup()
        var foundURLString: String?
        var foundPlainText: String?

        for itemProvider in attachments {
            // 1. Direkte Web-URL
            if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    if let url = item as? URL {
                        foundURLString = url.absoluteString
                    } else if let urlStr = item as? String, urlStr.hasPrefix("http") {
                        foundURLString = urlStr
                    }
                }
            }

            // 2. Markierter Text (kann eine eingebettete URL ODER rezepttext sein)
            if itemProvider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                itemProvider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    if let text = item as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        foundPlainText = text
                        if let extractedURL = self.extractFirstURL(from: text) {
                            if foundURLString == nil {
                                foundURLString = extractedURL
                            }
                        }
                    }
                }
            }
        }

        group.notify(queue: .main) {
            if let validURL = foundURLString, !validURL.isEmpty {
                PendingImportStore.shared.addImport(url: validURL, rawText: foundPlainText)
            } else if let text = foundPlainText, !text.isEmpty {
                // Direkter Text-Import ohne URL
                PendingImportStore.shared.addImport(url: "", rawText: text)
            }
            self.finishAndDismiss(delay: 0.6)
        }
    }

    private func extractFirstURL(from text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        for match in matches {
            if let url = match.url, url.scheme == "http" || url.scheme == "https" {
                return url.absoluteString
            }
        }
        return nil
    }

    private func finishAndDismiss(delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            UIView.animate(withDuration: 0.15, animations: {
                self.containerCard.alpha = 0
                self.containerCard.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
            }) { _ in
                self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            }
        }
    }
}
