//
//  RulesViewController.swift
//  AnyoneBrowser
//
//  Created by Benjamin Erhart on 29.01.25.
//  Copyright © 2025 Anyone. All rights reserved.
//

import UIKit

class RulesViewController: UITableViewController, UISearchResultsUpdating {

	private var rulesInUse = [String]()
	private var rulesAll = [String]()
	private var rulesFiltered = [String]()

	private var filtered: Bool {
		navigationItem.searchController?.isActive ?? false && !(navigationItem.searchController?.searchBar.text?.isEmpty ?? true)
	}

	init() {
		super.init(style: .grouped)
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		let sc = UISearchController(searchResultsController: nil)
		sc.searchResultsUpdater = self
		sc.obscuresBackgroundDuringPresentation = false

		definesPresentationContext = true
		navigationItem.searchController = sc

		rulesInUse = AppDelegate.shared?.browsingUis
			.compactMap({ $0.currentTab })
			.flatMap({ $0.applicableUrlBlockerTargets.allKeys as! [String] }) ?? []

		rulesAll = (URLBlocker.targets() as? [String: String])?.keys.sorted(using: .localizedStandard) ?? []

		navigationItem.title = NSLocalizedString("Blocked 3rd-Party Hosts", comment: "")
	}


	// MARK: UITableViewDataSource

	override func numberOfSections(in tableView: UITableView) -> Int {
		2
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		rules(for: section).count
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		if section == 0 {
			return NSLocalizedString("Rules in use on current page", comment: "")
		}

		return NSLocalizedString("All rules", comment: "")
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "rule") ?? .init(style: .subtitle, reuseIdentifier: "rule")
		cell.selectionStyle = .none

		let rule = rules(for: indexPath.section)[indexPath.row]

		cell.textLabel?.text = rule

		let reason = disabled(rule)
		let detail = (URLBlocker.targets() as? [String: String])?[rule]

		if let reason = reason {
			cell.textLabel?.textColor = .systemRed
			cell.detailTextLabel?.textColor = .systemRed

			if let detail = detail, !detail.isEmpty {
				cell.detailTextLabel?.text = String(format: NSLocalizedString("%1$@ (Disabled: %2$@)", comment: ""), detail, reason)
			}
			else {
				cell.detailTextLabel?.text = String(format: NSLocalizedString("Disabled: %@", comment: ""), reason)
			}
		}
		else {
			cell.textLabel?.textColor = .label
			cell.detailTextLabel?.textColor = .secondaryLabel

			cell.detailTextLabel?.text = detail
		}

		return cell
	}

	override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
		true
	}

	override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
		if editingStyle == .delete {
			toggle(rules(for: indexPath.section)[indexPath.row])
			tableView.reloadRows(at: [indexPath], with: .automatic)
		}
	}

	override func tableView(_ tableView: UITableView, titleForDeleteConfirmationButtonForRowAt indexPath: IndexPath) -> String? {
		if disabled(rules(for: indexPath.section)[indexPath.row]) != nil {
			return NSLocalizedString("Enable", comment: "")
		}

		return NSLocalizedString("Disable", comment: "")
	}


	// MARK: UISearchResultsUpdating

	func updateSearchResults(for searchController: UISearchController) {
		if let search = searchController.searchBar.text, !search.isEmpty {
			rulesFiltered = rulesAll.filter({ $0.localizedCaseInsensitiveContains(search) })
		}
		else {
			rulesFiltered.removeAll()
		}

		tableView.reloadSections([1], with: .automatic)
	}


	// MARK: Private Methods

	private func rules(for section: Int) -> [String] {
		if section == 0 {
			return rulesInUse
		}

		if filtered {
			return rulesFiltered
		}

		return rulesAll
	}

	private func disabled(_ rule: String) -> String? {
		(URLBlocker.disabledTargets() as? [String: String])?[rule]
	}

	private func toggle(_ rule: String) {
		if disabled(rule) != nil {
			URLBlocker.enableTarget(byHost: rule)
		}
		else {
			URLBlocker.disableTarget(byHost: rule, withReason: NSLocalizedString("User disabled", comment: ""))
		}
	}
}
