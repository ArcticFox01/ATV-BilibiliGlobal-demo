import UIKit

enum BLAppearance {
    static let background = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.035, green: 0.045, blue: 0.065, alpha: 1)
            : UIColor(white: 0.96, alpha: 1)
    }
}

/// A control surface. Artwork and full-screen content keep their own backgrounds.
final class BLGlassView: UIVisualEffectView {
    var isActive = false {
        didSet { if oldValue != isActive { updateAppearance() } }
    }

    var isSelected = false {
        didSet { if oldValue != isSelected { updateAppearance() } }
    }

    init(cornerRadius: CGFloat = 20) {
        super.init(effect: nil)
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        clipsToBounds = true
        isUserInteractionEnabled = false
        NotificationCenter.default.addObserver(self, selector: #selector(updateAppearance), name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAppearance), name: UIAccessibility.darkerSystemColorsStatusDidChangeNotification, object: nil)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateAppearance()
    }

    @objc private func updateAppearance() {
        if UIAccessibility.isReduceTransparencyEnabled {
            effect = nil
            let active = isActive
            backgroundColor = UIColor { traits in
                UIColor(white: traits.userInterfaceStyle == .dark ? (active ? 0.22 : 0.12) : (active ? 1 : 0.92), alpha: 1)
            }
        } else {
            backgroundColor = .clear
            if #available(tvOS 26.0, *), isActive {
                // Only the focused control gets glass; idle surfaces use standard material.
                let glass = UIGlassEffect(style: .regular)
                glass.isInteractive = true
                effect = glass
            } else {
                effect = UIBlurEffect(style: .regular)
            }
        }
        // Selection remains visible after focus moves into the adjacent content.
        let needsBorder = isSelected || isActive || UIAccessibility.isDarkerSystemColorsEnabled
        layer.borderWidth = needsBorder ? 2 : 0
        layer.borderColor = UIColor.label.withAlphaComponent(isSelected ? 0.7 : 0.3).resolvedColor(with: traitCollection).cgColor
    }
}
