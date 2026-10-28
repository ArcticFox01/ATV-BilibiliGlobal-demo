import Kingfisher
import SnapKit
import UIKit

final class AnimeArtworkCell: BLMotionCollectionViewCell {
    private let artwork = UIImageView()
    private let gradient = CAGradientLayer()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let badgeLabel = UILabel()
    private let eyebrowLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private var featured = false

    override func setup() {
        super.setup()
        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.layer.cornerRadius = 18
        artwork.backgroundColor = UIColor(white: 0.12, alpha: 1)
        contentView.addSubview(artwork)
        gradient.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.25).cgColor, UIColor.black.withAlphaComponent(0.95).cgColor]
        gradient.locations = [0, 0.35, 1]
        artwork.layer.addSublayer(gradient)
        for label in [titleLabel, subtitleLabel, badgeLabel, eyebrowLabel] {
            label.textColor = .white
            contentView.addSubview(label)
        }
        titleLabel.numberOfLines = 2
        subtitleLabel.textColor = UIColor(white: 0.8, alpha: 1)
        subtitleLabel.font = .systemFont(ofSize: 23)
        subtitleLabel.numberOfLines = 2
        badgeLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        badgeLabel.backgroundColor = .systemPink
        badgeLabel.layer.cornerRadius = 7
        badgeLabel.clipsToBounds = true
        badgeLabel.textAlignment = .center
        eyebrowLabel.text = "ANIME · FEATURED"
        eyebrowLabel.textColor = .systemPink
        eyebrowLabel.font = .systemFont(ofSize: 21, weight: .bold)
        progressView.progressTintColor = .systemPink
        progressView.trackTintColor = UIColor.white.withAlphaComponent(0.3)
        contentView.addSubview(progressView)
    }

    func configure(_ card: AnimeCard, featured: Bool) {
        self.featured = featured
        scaleFactor = featured ? 1.025 : 1.06
        titleLabel.text = card.title
        titleLabel.font = .systemFont(ofSize: featured ? 48 : 27, weight: .bold)
        subtitleLabel.text = featured ? [card.ownerName, "Select to explore episodes  ›"].filter { !$0.isEmpty }.joined(separator: "   ·   ") : card.ownerName
        badgeLabel.text = card.badge.isEmpty ? nil : "  \(card.badge)  "
        badgeLabel.isHidden = card.badge.isEmpty
        eyebrowLabel.isHidden = !featured
        progressView.isHidden = card.progress == nil
        progressView.progress = card.progress ?? 0
        artwork.kf.cancelDownloadTask()
        artwork.image = nil
        artwork.kf.setImage(with: card.pic?.addSchemeIfNeed(), options: [
            .processor(DownsamplingImageProcessor(size: CGSize(width: featured ? 1500 : 600, height: featured ? 600 : 338))),
            .cacheOriginalImage,
        ])
        accessibilityLabel = [card.title, card.ownerName, card.badge].filter { !$0.isEmpty }.joined(separator: ", ")
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width
        let height = contentView.bounds.height
        let imageHeight = featured ? height : width * 9 / 16
        artwork.frame = CGRect(x: 0, y: 0, width: width, height: imageHeight)
        gradient.frame = artwork.bounds
        gradient.isHidden = !featured
        badgeLabel.frame = CGRect(x: 20, y: 18, width: min(badgeLabel.intrinsicContentSize.width, width - 40), height: 32)
        if featured {
            eyebrowLabel.frame = CGRect(x: 38, y: height - 172, width: width - 76, height: 28)
            titleLabel.frame = CGRect(x: 38, y: height - 138, width: width - 76, height: 66)
            subtitleLabel.frame = CGRect(x: 38, y: height - 58, width: width - 76, height: 32)
        } else {
            titleLabel.frame = CGRect(x: 0, y: imageHeight + 12, width: width, height: 62)
            subtitleLabel.frame = CGRect(x: 0, y: imageHeight + 77, width: width, height: 56)
        }
        progressView.frame = CGRect(x: 14, y: imageHeight - 12, width: width - 28, height: 4)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        artwork.kf.cancelDownloadTask()
        artwork.image = nil
    }
}

final class AnimeMenuCell: BLMotionCollectionViewCell {
    private let icon = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var accent = UIColor.systemPink
    private var selectedDay = false

    override func setup() {
        super.setup()
        scaleFactor = 1.06
        contentView.layer.cornerRadius = 16
        contentView.layer.borderWidth = 2
        let stack = UIStackView(arrangedSubviews: [icon, titleLabel, subtitleLabel])
        stack.axis = .horizontal
        stack.spacing = 16
        stack.alignment = .center
        contentView.addSubview(stack)
        stack.snp.makeConstraints { $0.edges.equalToSuperview().inset(20) }
        icon.contentMode = .scaleAspectFit
        icon.snp.makeConstraints { $0.width.height.equalTo(36) }
        titleLabel.font = .systemFont(ofSize: 25, weight: .semibold)
        titleLabel.numberOfLines = 3
        titleLabel.textColor = .white
        subtitleLabel.font = .systemFont(ofSize: 20)
        subtitleLabel.textColor = UIColor(white: 0.75, alpha: 1)
    }

    func configure(title: String, subtitle: String?, symbol: String?, color: UIColor, selected: Bool = false) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
        icon.image = symbol.flatMap { UIImage(systemName: $0) }
        icon.isHidden = symbol == nil
        icon.tintColor = color
        accent = color
        selectedDay = selected
        // Date buttons stack their date below the weekday to keep seven days readable.
        if let stack = titleLabel.superview as? UIStackView {
            stack.axis = subtitle == nil ? .horizontal : .vertical
            stack.spacing = subtitle == nil ? 16 : 6
            stack.snp.updateConstraints { $0.edges.equalToSuperview().inset(subtitle == nil ? 20 : 12) }
        }
        accessibilityLabel = [title, subtitle].compactMap { $0 }.joined(separator: ", ")
        updateAppearance()
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations { self.updateAppearance() }
    }

    private func updateAppearance() {
        contentView.backgroundColor = selectedDay ? accent.withAlphaComponent(0.28) : UIColor(white: isFocused ? 0.23 : 0.12, alpha: 1)
        contentView.layer.borderColor = (isFocused || selectedDay ? accent : UIColor.clear).cgColor
    }
}
