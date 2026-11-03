//
//  BLButton.swift
//  BiliBiliGlobal
//
//  Created by yicheng on 2022/10/22.
//

import SnapKit
import TVUIKit

@IBDesignable
@MainActor
class BLCustomButton: BLButton {
    @IBInspectable var image: UIImage? {
        didSet { updateButton() }
    }

    @IBInspectable var onImage: UIImage? {
        didSet { updateButton() }
    }

    @IBInspectable var highLightImage: UIImage? {
        didSet { updateButton() }
    }

    @IBInspectable var title: String? {
        didSet {
            accessibilityLabel = title
            updateTitleLabel()
        }
    }

    @IBInspectable var titleColor: UIColor = .label {
        didSet { titleLabel.textColor = titleColor }
    }

    @IBInspectable var titleFont: UIFont = .systemFont(ofSize: 24) {
        didSet { titleLabel.font = titleFont }
    }

    var isOn: Bool = false {
        didSet {
            updateButton()
        }
    }

    private let titleLabel = UILabel()
    private let imageView = UIImageView()

    override func setup() {
        super.setup()
        titleLabel.isUserInteractionEnabled = false
        effectView.contentView.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.height.equalToSuperview().multipliedBy(0.5)
            make.height.equalTo(imageView.snp.width)
        }
        imageView.image = image
        addSubview(titleLabel)
        titleLabel.textAlignment = .center
        titleLabel.font = titleFont
        titleLabel.textColor = titleColor
        updateTitleLabel(force: true)
    }

    private func updateTitleLabel(force: Bool = false) {
        let shouldHide = title == nil || title?.count == 0
        titleLabel.text = title
        if force || titleLabel.isHidden != shouldHide {
            titleLabel.isHidden = shouldHide
            if shouldHide {
                titleLabel.snp.removeConstraints()
            } else {
                titleLabel.snp.makeConstraints { make in
                    make.leading.trailing.bottom.equalToSuperview()
                    make.top.equalTo(effectView.snp.bottom).offset(10)
                }
            }
        }
    }

    private func getImage() -> UIImage? {
        isOn ? onImage : image
    }

    private func updateButton() {
        if isFocused {
            imageView.image = highLightImage ?? getImage()
            imageView.tintColor = .label
        } else {
            imageView.image = getImage()
            imageView.tintColor = .label
        }
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        updateButton()
    }
}

@IBDesignable
@MainActor
class BLCustomTextButton: BLButton {
    private let titleLabel = UILabel()
    var object: Any?

    @IBInspectable var title: String? {
        didSet {
            titleLabel.text = title
            accessibilityLabel = title
        }
    }

    @IBInspectable var titleColor: UIColor = .label {
        didSet { titleLabel.textColor = titleColor }
    }

    @IBInspectable var titleSelectedColor: UIColor = .label {
        didSet { titleLabel.textColor = isFocused ? titleSelectedColor : titleColor }
    }

    @IBInspectable var titleFont: UIFont = .systemFont(ofSize: 28) {
        didSet { titleLabel.font = titleFont }
    }

    override func setup() {
        super.setup()
        effectView.layer.cornerRadius = 24
        effectView.contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview().inset(10)
            make.left.right.equalToSuperview().inset(24)
        }
        titleLabel.text = title
        titleLabel.font = titleFont
        titleLabel.textColor = isFocused ? titleSelectedColor : titleColor
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        titleLabel.textColor = isFocused ? titleSelectedColor : titleColor
    }
}

class BLButton: UIControl {
    private var motionEffect: UIInterpolatingMotionEffect!
    fileprivate let effectView = BLGlassView(cornerRadius: 24)

    var onPrimaryAction: ((BLButton) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var canBecomeFocused: Bool { return isEnabled }

    func setup() {
        isUserInteractionEnabled = true
        motionEffect = UIInterpolatingMotionEffect(keyPath: "center.x", type: .tiltAlongHorizontalAxis)
        motionEffect.maximumRelativeValue = 8
        motionEffect.minimumRelativeValue = -8
        isAccessibilityElement = true
        accessibilityTraits.insert(.button)
        NotificationCenter.default.addObserver(self, selector: #selector(updateMotion), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        addSubview(effectView)
        effectView.isUserInteractionEnabled = false
        effectView.clipsToBounds = true
        effectView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalToSuperview().priority(.high)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func updateMotion() {
        removeMotionEffect(motionEffect)
        transform = .identity
        layer.shadowOpacity = isFocused ? 0.2 : 0
        guard isFocused, !UIAccessibility.isReduceMotionEnabled else { return }
        transform = CGAffineTransform(scaleX: 1.06, y: 1.06)
        layer.shadowOffset = CGSize(width: 0, height: 10)
        layer.shadowRadius = 16
        addMotionEffect(motionEffect)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        super.pressesEnded(presses, with: event)
        if isEnabled, presses.first?.type == .select {
            sendActions(for: .primaryActionTriggered)
            onPrimaryAction?(self)
        }
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations {
            self.effectView.isActive = self.isFocused
            self.updateMotion()
        }
    }
}
