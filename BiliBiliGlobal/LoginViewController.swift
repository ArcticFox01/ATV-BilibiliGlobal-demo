//
//  LoginViewController.swift
//  BiliBiliGlobal
//
//  Created by Etan Chen on 2021/3/28.
//

import Alamofire
import Foundation
import SnapKit
import SwiftyJSON
import UIKit

class LoginViewController: UIViewController {
    private let initialGuideText = "1. Open the official BiliBili mobile app and scan this QR code.\n\n2. If sign-in fails, select Generate New QR Code and try again."
    private let ciContext = CIContext()

    private let qrcodeImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let regenerateButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = "Generate New QR Code"
        config.contentInsets = NSDirectionalEdgeInsets(top: 20, leading: 40, bottom: 20, trailing: 40)

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let leftContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let dividerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(white: 0.3333333333, alpha: 1)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Sign In"
        label.font = UIFont.preferredFont(forTextStyle: .title1)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let guideLabel: UILabel = {
        let label = UILabel()
        label.text = "1. Open the official BiliBili mobile app and scan this QR code.\n\n2. If sign-in fails, select Generate New QR Code and try again."
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.numberOfLines = 0
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    var currentLevel: Int = 0, finalLevel: Int = 200
    var timer: Timer?
    var oauthKey: String = ""
    private var validationGeneration = 0
    private var isPolling = false
    private var isCompletingLogin = false

    static func create() -> LoginViewController {
        LoginViewController()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        initValidation()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        qrcodeImageView.image = nil
        invalidateValidation()
    }

    func generateQRCode(from string: String) -> UIImage? {
        guard
            let data = string.data(using: .ascii),
            let filter = CIFilter(name: "CIQRCodeGenerator")
        else {
            return nil
        }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }
        let extent = outputImage.extent.integral
        guard !extent.isEmpty else { return nil }

        let targetSize: CGFloat = 540
        let scale = max(1, floor(targetSize / max(extent.width, extent.height)))
        let width = Int(extent.width * scale)
        let height = Int(extent.height * scale)

        guard
            let cgImage = ciContext.createCGImage(outputImage, from: extent),
            let bitmapContext = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        else {
            return nil
        }

        bitmapContext.interpolationQuality = .none
        bitmapContext.scaleBy(x: scale, y: scale)
        bitmapContext.draw(cgImage, in: extent)

        guard let scaledImage = bitmapContext.makeImage() else { return nil }
        return UIImage(cgImage: scaledImage)
    }

    func initValidation() {
        invalidateValidation()
        currentLevel = 0
        guideLabel.text = initialGuideText
        qrcodeImageView.image = nil
        let generation = validationGeneration
        ApiRequest.requestWebLoginQR { [weak self] code, url in
            guard let self, generation == self.validationGeneration else { return }
            guard !code.isEmpty, !url.isEmpty else {
                self.guideLabel.text = "Could not generate a sign-in QR code. Select Generate New QR Code and try again."
                return
            }
            let image = self.generateQRCode(from: url)
            self.qrcodeImageView.image = image
            self.oauthKey = code
            self.startValidationTimer(generation: generation)
        }
    }

    func startValidationTimer(generation: Int) {
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard generation == self.validationGeneration,
                  !self.isCompletingLogin,
                  !self.isPolling,
                  !self.oauthKey.isEmpty
            else { return }
            self.currentLevel += 1
            if self.currentLevel > self.finalLevel {
                self.initValidation()
                return
            }
            self.loopValidation(generation: generation)
        }
    }

    func stopValidationTimer() {
        timer?.invalidate()
        timer = nil
    }

    func invalidateValidation() {
        stopValidationTimer()
        validationGeneration += 1
        oauthKey = ""
        isPolling = false
        isCompletingLogin = false
    }

    func didValidationSuccess() {
        qrcodeImageView.image = nil
        AppDelegate.shared.showTabBar()
        stopValidationTimer()
    }

    func loopValidation(generation: Int) {
        isPolling = true
        ApiRequest.verifyWebLoginQR(code: oauthKey) {
            [weak self] state in
            guard let self, generation == self.validationGeneration else { return }
            self.isPolling = false
            switch state {
            case .expire:
                self.initValidation()
            case .waiting:
                break
            case let .success(mid, cookies):
                self.isCompletingLogin = true
                self.stopValidationTimer()
                AccountManager.shared.registerWebAccount(mid: mid, cookies: cookies) { [weak self] _ in
                    self?.didValidationSuccess()
                }
            case .unsupported:
                self.stopValidationTimer()
                self.guideLabel.text = "BiliBili rejected this web login. Generate a new QR code and try again."
            case .fail:
                self.guideLabel.text = "Sign-in verification failed. Retrying…"
            }
        }
    }

    @objc private func actionStart() {
        initValidation()
    }

    private func setupUI() {
        view.backgroundColor = .black

        view.addSubview(leftContainerView)
        view.addSubview(dividerView)
        view.addSubview(titleLabel)
        view.addSubview(guideLabel)

        let qrStackView = UIStackView(arrangedSubviews: [qrcodeImageView, regenerateButton])
        qrStackView.axis = .vertical
        qrStackView.alignment = .center
        qrStackView.spacing = 50
        qrStackView.translatesAutoresizingMaskIntoConstraints = false
        leftContainerView.addSubview(qrStackView)

        regenerateButton.addTarget(self, action: #selector(actionStart), for: .primaryActionTriggered)

        leftContainerView.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.bottom.equalToSuperview()
            make.width.equalToSuperview().multipliedBy(0.5)
        }

        qrStackView.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        qrcodeImageView.snp.makeConstraints { make in
            make.width.height.equalTo(540)
        }

        dividerView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.bottom.equalTo(view.safeAreaLayoutGuide)
            make.width.equalTo(2)
        }

        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(dividerView.snp.trailing).offset(100)
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(120)
        }

        guideLabel.snp.makeConstraints { make in
            make.leading.equalTo(dividerView.snp.trailing).offset(100)
            make.top.equalTo(titleLabel.snp.bottom).offset(50)
            make.trailing.lessThanOrEqualTo(view.safeAreaLayoutGuide.snp.trailing).offset(-100)
        }
    }
}
