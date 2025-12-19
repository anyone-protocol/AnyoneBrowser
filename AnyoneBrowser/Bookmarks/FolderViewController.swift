//
//  FolderViewController.swift
//  OnionBrowser
//
//  Created by Benjamin Erhart on 24.10.25.
//  Copyright © 2025 Tigas Ventures, LLC (Mike Tigas). All rights reserved.
//

import UIKit
import Eureka

class FolderViewController: FixedFormViewController {

	var index: Int?
	var parentFolder: NcFolder = NcBookmarks.root
	var delegate: BookmarksViewControllerDelegate?

	private var folder: NcFolder?

	private let favIconRow = FavIconRow() {
		$0.disabled = true
		$0.placeholderImage = NcFolder.icon
	}

	private let titleRow = TextRow() {
		$0.placeholder = NSLocalizedString("Title", comment: "Folder name placeholder")
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		// Was called via "+" (add).
		if let index {
			folder = parentFolder.folders[index]
		}

		navigationItem.title = index == nil
		? NSLocalizedString("Add Folder", comment: "Scene title")
		: NSLocalizedString("Edit Folder", comment: "Scene title")

		if index == nil {
			navigationItem.rightBarButtonItem = UIBarButtonItem(
				barButtonSystemItem: .save, target: self, action: #selector(addNew))

			// Don't allow to store unnamed folders.
			navigationItem.rightBarButtonItem?.isEnabled = titleRow.value != nil
		}

		if let folder = folder {
			titleRow.value = folder.title
		}

		form
		+++ favIconRow
		<<< titleRow
			.onChange { [weak self] row in
				self?.navigationItem.rightBarButtonItem?.isEnabled = row.value != nil
			}
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)

		// Store changes, if user edits an existing folder or folder was created
		// with #addNew.
		if index != nil {
			folder?.title = titleRow.value ?? folder?.title ?? ""

			NcBookmarks.store()

			if let folder {
				Task {
					do {
						if try await folder.upload() {
							NcBookmarks.store()
						}
					}
					catch {
						Log.error(for: Self.self, "\(error)")
					}
				}
			}

			delegate?.needsReload()
		}
	}


	// MARK: Private Methods

	@objc private func addNew() {
		if let title = titleRow.value, !title.isEmpty {
			folder = NcFolder(title: title, parentFolder: parentFolder.id)

			parentFolder.folders.append(folder!)

			// Trigger store in #viewWillDisappear by setting index != nil.
			index = parentFolder.folders.firstIndex(of: folder!)

			navigationController?.popViewController(animated: true)
		}
	}
}
