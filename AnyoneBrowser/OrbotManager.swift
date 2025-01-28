//
//  OrbotManager.swift
//  OnionBrowser
//
//  Copyright © 2012 - 2023, Tigas Ventures, LLC (Mike Tigas)
//
//  This file is part of Onion Browser. See LICENSE file for redistribution terms.
//

import Foundation

class OrbotManager : NSObject {

	static let shared = OrbotManager()

	// MARK: Public Methods

	/**
	 Check's Orbot's status, and if not working, returns a view controller to show instead of the browser UI.

	 Starts a continuous Orbot status change check, if successful.

	 - returns: A view controller to show instead of the browser UI, if status is not good.
	 */
	func checkStatus() -> UIViewController? {
		if !Settings.didWelcome {
			return WelcomeViewController()
		}

		if AnonManager.shared.status == .started {
			// Built-in Anyone running. Ok.
			return nil
		}

		// No built-in Anyone running. Let the user start it!
		return StartTorViewController()
	}

	func allowRequests() -> Bool {
		return AnonManager.shared.status == .started
	}


	// MARK: Private Methods

	/**
	Cancel all connections and re-evalutate Orbot situation and show respective UI.
	*/
	private func fullStop() {
		DispatchQueue.main.async {
			for tab in AppDelegate.shared?.allOpenTabs ?? [] {
				tab.stop()
			}
		}
	}
}
