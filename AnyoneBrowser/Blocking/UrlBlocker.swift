//
//  UrlBlocker.swift
//  AnyoneBrowser
//
//  Created by Benjamin Erhart on 30.01.25.
//  Copyright © 2025 Anyone. All rights reserved.
//

import Foundation

@objcMembers
@objc(URLBlocker)
class UrlBlocker: NSObject {

	static let shared = UrlBlocker()


	var hosts: [String] {
		targets.keys.sorted(using: .localizedStandard)
	}


	private static let disabledUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last?
		.appendingPathComponent("url_blocker_disabled.plist")


	private var targets = [String: String]()

	private var disabled = [String: String]()

	private lazy var ruleCache: NSCache<NSString, NSString> = {
		let cache = NSCache<NSString, NSString>()
		cache.countLimit = 128

		return cache
	}()

	private lazy var titleRegex = try? NSRegularExpression(pattern: "^# Title: (.+)$", options: .caseInsensitive)


	private override init() {
		super.init()

		if let url = Bundle.main.url(forResource: "light-onlydomains", withExtension: "txt") {
			do {
				let blocklist = try String(contentsOf: url, encoding: .utf8)
				var title = "HaGeZi's Light DNS Blocklist"

				for line in blocklist.split(whereSeparator: { $0.isNewline }) {
					guard !line.hasPrefix("#") else {
						let line = String(line)
						if let match = titleRegex?.firstMatch(in: line, range: NSRange(line.startIndex ..< line.endIndex, in: line)),
						   match.numberOfRanges > 1,
						   let range = Range(match.range(at: 1), in: line)
						{
							title = String(line[range])
						}

						continue
					}

					targets[String(line)] = title
				}
			}
			catch {
				assertionFailure("light-onlydomains.txt file could not be found!")

				// Injected for testing.
				targets["twitter.com"] = "Social - Twitter"

				return
			}
		}

		if let disabledUrl = Self.disabledUrl, disabledUrl.exists {
			do {
				let data = try Data(contentsOf: disabledUrl)

				disabled = try PropertyListDecoder().decode([String: String].self, from: data)
			}
			catch {
				assertionFailure(error.localizedDescription)
			}
		}
	}


	// MARK: Public Methods

	func blockRule(for url: URL, withMain mainUrl: URL? = nil) -> String? {
		guard Settings.enableUrlBlocker else {
			return nil
		}

		let rule = blockRule(for: url)

		if let rule = rule, let mainUrl = mainUrl {
			// If this same rule would have blocked our main URL, allow it,
			// since the user is probably viewing this site and this isn't a sneaky tracker.
			if rule == blockRule(for: mainUrl) {
				return nil
			}
		}

		return rule
	}

	func description(for host: String) -> String? {
		targets[host]
	}


	func isDisabled(host: String) -> String? {
		disabled[host]
	}

	func disable(host: String, with reason: String) {
		disabled[host] = reason
		store()

		ruleCache.removeObject(forKey: host as NSString)
	}

	func enable(host: String) {
		disabled.removeValue(forKey: host)
		store()

		ruleCache.removeObject(forKey: host as NSString)
	}


	// MARK: Private Methods

	private func store() {
		guard let disabledUrl = Self.disabledUrl else {
			assertionFailure("url_blocker_disabled.plist file URL could not be constructed!")
			return
		}

		do {
			let data = try PropertyListEncoder().encode(disabled)

			try data.write(to: disabledUrl)
		}
		catch {
			assertionFailure(error.localizedDescription)
		}
	}

	private func blockRule(for url: URL) -> String? {
		guard let host = url.host?.lowercased() else {
			return nil
		}

		if let rule = ruleCache.object(forKey: host as NSString) as String? {
			return rule.isEmpty ? nil : rule
		}

		var rule = ""

		if targets[host] != nil {
			rule = host
		}
		else {
			// now for x.y.z.example.com, try *.y.z.example.com, *.z.example.com, *.example.com, etc.
			let p = host.components(separatedBy: ".")

			if p.count > 2 {
				for i in 1 ..< p.count - 1 {
					let domain = p[i ..< p.count].joined(separator: ".")

					if targets[domain] != nil {
						rule = domain
						break
					}
				}
			}
		}

		if rule.isEmpty || disabled[rule] != nil {
			ruleCache.setObject("", forKey: host as NSString)

			return nil
		}

		ruleCache.setObject(rule as NSString, forKey: host as NSString)

		return rule
	}
}
