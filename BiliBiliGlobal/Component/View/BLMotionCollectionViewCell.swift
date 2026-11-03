//
//  BLMotionCollectionViewCell.swift
//  BiliBiliGlobal
//
//  Created by yicheng on 2022/10/23.
//

import TVUIKit
import UIKit

class BLMotionCollectionViewCell: UICollectionViewCell {
    private var motionEffectV: UIInterpolatingMotionEffect!
    private var motionEffectH: UIInterpolatingMotionEffect!
    var scaleFactor: CGFloat = 1.1
    var usesSystemImageFocus = false
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func setup() {
        NotificationCenter.default.addObserver(self, selector: #selector(updateMotion), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        motionEffectV = UIInterpolatingMotionEffect(keyPath: "center.y", type: .tiltAlongVerticalAxis)
        motionEffectV.maximumRelativeValue = 8
        motionEffectV.minimumRelativeValue = -8
        motionEffectH = UIInterpolatingMotionEffect(keyPath: "center.x", type: .tiltAlongHorizontalAxis)
        motionEffectH.maximumRelativeValue = 8
        motionEffectH.minimumRelativeValue = -8
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations {
            self.updateMotion()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func updateMotion() {
        removeMotionEffect(motionEffectH)
        removeMotionEffect(motionEffectV)
        updateTransform()
        if isFocused, !usesSystemImageFocus, !UIAccessibility.isReduceMotionEnabled {
            addMotionEffect(motionEffectH)
            addMotionEffect(motionEffectV)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        removeMotionEffect(motionEffectH)
        removeMotionEffect(motionEffectV)
        transform = .identity
        layer.shadowOpacity = 0
    }

    func updateTransform() {
        if isFocused, !usesSystemImageFocus, !UIAccessibility.isReduceMotionEnabled {
            transform = CGAffineTransformMakeScale(scaleFactor, scaleFactor)
            let scaleDiff = (bounds.size.height * scaleFactor - bounds.size.height) / 2
            transform = CGAffineTransformTranslate(transform, 0, -scaleDiff)
            layer.shadowOffset = CGSizeMake(0, 16)
            layer.shadowOpacity = 0.2
            layer.shadowRadius = 18.0
        } else {
            transform = CGAffineTransformIdentity
            layer.shadowOpacity = 0
            layer.shadowOffset = CGSizeMake(0, 0)
        }
    }
}
