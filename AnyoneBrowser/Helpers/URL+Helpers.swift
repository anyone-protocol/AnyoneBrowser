//
//  URL+Helpers.swift
//  OnionBrowser2
//
//  Created by Benjamin Erhart on 21.11.19.
//  Copyright © 2012 - 2023, Tigas Ventures, LLC (Mike Tigas)
//
//  This file is part of Onion Browser. See LICENSE file for redistribution terms.
//

import Foundation

extension URL {

	static let blank = URL(string: "about:blank")!

	static let aboutAnyoneBrowser = URL(string: "about:anyone-browser")!
	static let credits = Bundle.main.url(forResource: "credits", withExtension: "html")!

	static let aboutSecurityLevels = URL(string: "about:security-levels")!
	static let securityLevels = Bundle.main.url(forResource: "security-levels", withExtension: "html")!

	static let start = FileManager.default.cacheDir!.appendingPathComponent("start.html")

	var withFixedScheme: URL? {
		switch scheme?.lowercased() {
		case "anonhttp":
			var urlc = URLComponents(url: self, resolvingAgainstBaseURL: true)
			urlc?.scheme = "http"

			return urlc?.url

		case "anonhttps":
			var urlc = URLComponents(url: self, resolvingAgainstBaseURL: true)
			urlc?.scheme = "https"

			return urlc?.url

		case "anonabout":
			var urlc = URLComponents(url: self, resolvingAgainstBaseURL: true)
			urlc?.scheme = "about"

			return urlc?.url

		default:
			return self
		}
	}

	var real: URL {
		switch self {
		case URL.aboutAnyoneBrowser:
			return URL.credits

		case URL.aboutSecurityLevels:
			return URL.securityLevels

		default:
			return self
		}
	}

	var clean: URL? {
		switch self {
		case URL.credits:
			return URL.aboutAnyoneBrowser

		case URL.securityLevels:
			return URL.aboutSecurityLevels

		case URL.start:
			return nil

		default:
			if self.scheme == "anonabout" {
				return self.withFixedScheme
			}

			return self
		}
	}

	var isSpecial: Bool {
		switch scheme?.lowercased() {
		case "http", "https", "anonhttp", "anonhttps":
			break

		default:
			return true
		}

		switch self {
		case URL.blank, URL.aboutAnyoneBrowser, URL.credits, URL.aboutSecurityLevels, URL.securityLevels, URL.start:
			return true

		default:
			return false
		}
	}

	var isSearchable: Bool {
		switch self {
		case URL.blank, URL.start:
			return false

		default:
			return true
		}
	}

	var isHttp: Bool {
		["http", "anonhttp"].contains(scheme?.lowercased())
	}

	var isHttps: Bool {
		["https", "anonhttps"].contains(scheme?.lowercased())
	}

	var isAnon: Bool {
		host?.lowercased().hasSuffix(".anon") ?? false
	}

	var exists: Bool {
		(try? self.checkResourceIsReachable()) ?? false
	}
}

@objc
extension NSURL {

	var withFixedScheme: NSURL? {
		return (self as URL).withFixedScheme as NSURL?
	}
}
