//
//  StartTorViewController.swift
//  OnionBrowser
//
//  Created by Benjamin Erhart on 11.10.23.
//  Copyright © 2023 Tigas Ventures, LLC (Mike Tigas)
//
//  This file is part of Onion Browser. See LICENSE file for redistribution terms.
//

import UIKit

class StartTorViewController: UIViewController {

	@IBOutlet weak var titleLb: UILabel! {
		didSet {
			titleLb.text = NSLocalizedString("Starting Anyone…", comment: "")
		}
	}

	@IBOutlet weak var retryBt: UIButton! {
		didSet {
			retryBt.setTitle(NSLocalizedString("Retry", comment: ""))
		}
	}

	@IBOutlet weak var progressView: UIProgressView!

	@IBOutlet weak var statusLb: UILabel!


	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

		retry()
	}


	// MARK: Actions

	@IBAction
	func retry() {
		retryBt.isHidden = true
		progressView.progress = 0
		statusLb.isHidden = true

		AnonManager.shared.start() { [weak self] progress, summary in
			guard let progress = progress else {
				return
			}

			DispatchQueue.main.async {
				self?.progressView.setProgress(Float(progress) / 100, animated: true)

				if let summary = summary, !summary.isEmpty {
					self?.statusLb.text = summary
					self?.statusLb.textColor = .label
					self?.statusLb.isHidden = false
				}
				else {
					self?.statusLb.isHidden = true
				}
			}
		} _: { [weak self] error in
			guard error == nil else {
				DispatchQueue.main.async {
					self?.retryBt.isHidden = false
					self?.statusLb.text = (error ?? AnonManager.Errors.noSocksAddr).localizedDescription
					self?.statusLb.textColor = .systemRed
					self?.statusLb.isHidden = false
				}

				return
			}

			DispatchQueue.main.async {
				AppDelegate.shared?.allOpenTabs.forEach { tab in
					tab.reinitWebView()
				}

				self?.view.sceneDelegate?.show(AnonManager.shared.checkStatus())
			}
		}
	}
}
