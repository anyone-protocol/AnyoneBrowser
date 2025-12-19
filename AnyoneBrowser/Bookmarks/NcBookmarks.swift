//
//  NcBookmarks.swift
//  OnionBrowser
//
//  Created by Benjamin Erhart on 23.10.25.
//  Copyright © 2025 Tigas Ventures, LLC (Mike Tigas). All rights reserved.
//

import Foundation

class NcBookmarks {

	static var rootDir = FileManager.default.docsDir

	static var root: NcFolder = {

		// Migrate from old storage format.
		if let oldStorageFile,
		   let data = NSDictionary(contentsOf: oldStorageFile)
		{
			let root = NcFolder(id: -1, title: "")

			for d in data["bookmarks"] as? [NSDictionary] ?? [] {
				if let url = d["url"] as? String,
				   let title = d["name"] as? String
				{
					let b = NcBookmark(
						url: url,
						title: title,
						lastModified: Int(d["last_updated"] as? TimeInterval ?? Date().timeIntervalSince1970),
						folder: root,
						iconName: d["icon"] as? String)

					root.bookmarks.append(b)
				}
			}

			if let storageFile {
				// Written a second time here to avoid a circular call.
				do {
					try encoder.encode(root).write(to: storageFile, options: .atomic)
				}
				catch {
					Log.error(for: NcBookmarks.self, "\(error)")
				}

				// Successfully stored in new format. Remove old stuff.
				if storageFile.exists {
					try? FileManager.default.removeItem(at: oldStorageFile)
				}
			}

			return root
		}

		if let storageFile,
		   let data = try? Data(contentsOf: storageFile),
		   let root = try? PropertyListDecoder().decode(NcFolder.self, from: data)
		{

			return root
		}

		return .init(id: -1, title: "")
	}()


	private static let storageFile = rootDir?.appendingPathComponent("nc_bookmarks.plist")
	private static let oldStorageFile = rootDir?.appendingPathComponent("bookmarks.plist")

	private static let encoder = PropertyListEncoder()

	private static var startPageNeedsUpdate = true

	private static let defaultBookmarks: [NcBookmark] = {
		var defaults = [NcBookmark]()

		defaults.append(.init(url: "https://anyone.io/", title: "Anyone"))
		defaults.append(.init(url: "http://anyone.anon/", title: "Anyone Foundation"))
		defaults.append(.init(url: "https://docs.anyone.io/", title: "Anyone Docs"))

		return defaults
	}()


	// MARK: Public Methods

	class func store() {
		guard let storageFile else {
			return
		}

		// Trigger update of start page when things changed.
		startPageNeedsUpdate = true

		do {
			try encoder.encode(root).write(to: storageFile, options: .atomic)
		}
		catch {
			Log.error(for: Self.self, "\(error)")
		}
	}

	class func updateStartPage(force: Bool = false) {
		guard let source = Bundle.main.url(forResource: "start", withExtension: "html") else {
			return
		}

		// Always update after start. Language could have been changed.
		if !startPageNeedsUpdate && !force {
			if let dm = (try? URL.start.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
			   let sm = (try? source.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
			{
				if dm > sm {
					return
				}
			}
		}

		guard var template = try? String(contentsOf: source) else {
			return
		}

		if Settings.disableBookmarksOnStartPage {
			template = template.replacingOccurrences(of: "{{ bookmarks_table_style }}", with: "display: none")
		}
		else {
			template = template.replacingOccurrences(of: "{{ bookmarks_table_style }}", with: "")

			let bookmarks = root.bookmarks

			// Render bookmarks.
			for i in 0 ... 5 {
				let url: String
				let name: String
				let icon: UIImage

				if bookmarks.count > i {
					let tempUrl = bookmarks[i].url

					url = tempUrl

					name = bookmarks[i].title.isEmpty ? URL(string: url)?.host ?? "" : bookmarks[i].title
					icon = bookmarks[i].icon ?? NcBookmark.defaultIcon
				}
				else {
					if i < defaultBookmarks.count {
						// Make sure that the first 6 default bookmarks are available!
						url = defaultBookmarks[i].url
						name = defaultBookmarks[i].title.isEmpty ? URL(string: url)?.host ?? "" : defaultBookmarks[i].title
						icon = defaultBookmarks[i].icon ?? NcBookmark.defaultIcon
					}
					else {
						url = ""
						name = ""
						icon = NcBookmark.defaultIcon
					}
				}

				template = template
					.replacingOccurrences(of: "{{ bookmark_url_\(i) }}", with: url)
					.replacingOccurrences(of: "{{ bookmark_name_\(i) }}", with: name)
					.replacingOccurrences(of: "{{ bookmark_icon_\(i) }}",
						with: "data:image/png;base64,\(icon.pngData()?.base64EncodedString() ?? "")")
			}
		}

		template = template
			.replacingOccurrences(of: "{{ Anyone Browser }}",
								  with: Bundle.main.displayName)
			.replacingOccurrences(of: "{{ Learn more about Anyone Browser }}",
								  with: String(format: NSLocalizedString("Learn more about %@", comment: ""), Bundle.main.displayName))
			.replacingOccurrences(of: "{{ security-levels-url }}", with: "anonabout:security-levels")

		try? template.write(to: URL.start, atomically: true, encoding: .utf8)

		startPageNeedsUpdate = false
	}

	class func firstRunSetup() {
		guard !Settings.bookmarkFirstRunDone else {
			return
		}

		// Only set up default list of bookmarks, when there's no others.
		guard root.bookmarks.count < 1 else {
			Settings.bookmarkFirstRunDone = true

			return
		}

		root.bookmarks.append(contentsOf: defaultBookmarks)

		store()

		Task {
			await recurse(root) { bookmark in
				if await bookmark.acquireIcon() {
					store()
				}

				return false
			}

			Settings.bookmarkFirstRunDone = true
		}
	}

	class func find(_ lambda: (_ bookmark: NcBookmark) -> Bool) -> [NcBookmark] {
		return recurse(root, lambda)
	}

	class func find(_ url: URL) -> NcBookmark? {
		let url = url.absoluteString

		return find({ bookmark in
			return bookmark.url == url
		}).first
	}


	// MARK: Private Methods

	@discardableResult
	private class func recurse(_ folder: NcFolder, _ lambda: (_ bookmark: NcBookmark) async -> Bool) async -> NcBookmark? {
		for bookmark in folder.bookmarks {
			if await lambda(bookmark) {
				return bookmark
			}
		}

		for folder in folder.folders {
			if let bookmark = await recurse(folder, lambda) {
				return bookmark
			}
		}

		return nil
	}

	@discardableResult
	private class func recurse(_ folder: NcFolder, _ lambda: (_ bookmark: NcBookmark) -> Bool) -> [NcBookmark] {
		var result = [NcBookmark]()

		for bookmark in folder.bookmarks {
			if lambda(bookmark) {
				result.append(bookmark)
			}
		}

		for folder in folder.folders {
			result.append(contentsOf: recurse(folder, lambda))
		}

		return result
	}
}
