//
//  TorManager.swift
//  Orbot
//
//  Created by Benjamin Erhart on 17.05.21.
//  Copyright © 2021 Guardian Project. All rights reserved.
//

import NetworkExtension
import Tor
import Network


class TorManager {

	enum Status: String, Codable {
		case stopped = "stopped"
		case starting = "starting"
		case started = "started"
	}

	enum Errors: Error, LocalizedError {
		case cookieUnreadable
		case noSocksAddr
		case smartConnectFailed

		var errorDescription: String? {
			switch self {

			case .cookieUnreadable:
				return "Tor cookie unreadable"

			case .noSocksAddr:
				return "No SOCKS port"

			case .smartConnectFailed:
				return "Smart Connect failed"
			}
		}
	}

	static let shared = TorManager()

	static let localhost = "127.0.0.1"

	var status = Status.stopped

	var torSocks5: Network.NWEndpoint? = nil

	private var torThread: Thread?

	private var torController: TorController?

	private var torConf: TorConfiguration?

	private var _torRunning = false
	private var torRunning: Bool {
		 ((torThread?.isExecuting ?? false) && (torConf?.isLocked ?? false)) || _torRunning
	}

	private lazy var controllerQueue = DispatchQueue.global(qos: .userInitiated)

//	private var ipStatus = IpSupport.Status.unavailable

	private var progressObs: Any?
	private var establishedObs: Any?


	private init() {
//		IpSupport.shared.start({ [weak self] status in
//			self?.ipStatus = status
//
//			if (self?.torRunning ?? false) && (self?.torController?.isConnected ?? false) {
//				self?.torController?.setConfs(status.torConf(self?.transport ?? .none, Transport.asConf))
//				{ success, error in
//					if let error = error {
//						self?.log("error: \(error)")
//					}
//
//					self?.torController?.resetConnection()
//				}
//			}
//		})
	}

	func start(_ progressCallback: @escaping (_ progress: Int?) -> Void,
			   _ completion: @escaping (Error?) -> Void)
	{
		status = .starting

		if !torRunning {
			torConf = getTorConf()

//			if let debug = torConf?.compile().joined(separator: ", ") {
//				print(debug)
//			}

			torThread = TorThread(configuration: torConf)

			torThread?.start()
		}

		controllerQueue.asyncAfter(deadline: .now() + 0.65) {
			if self.torController == nil, let url = self.torConf?.controlPortFile {
				self.torController = TorController(controlPortFile: url)
			}

			if !(self.torController?.isConnected ?? false) {
				do {
					try self.torController?.connect()
				}
				catch let error {
					self.log("#startTunnel error=\(error)")

					self.status = .stopped

					return completion(error)
				}
			}

			guard let cookie = self.torConf?.cookie else {
				self.log("#startTunnel cookie unreadable")

				self.stop()

				return completion(Errors.cookieUnreadable)
			}

			self.torController?.authenticate(with: cookie) { success, error in
				if let error = error {
					self.log("#startTunnel error=\(error)")

					self.stop()

					return completion(error)
				}

				self.progressObs = self.torController?.addObserver(forStatusEvents: {
					[weak self] (type, severity, action, arguments) -> Bool in

					if type == "STATUS_CLIENT" && action == "BOOTSTRAP" {
						let progress: Int?

						if let p = arguments?["PROGRESS"] {
							progress = Int(p)
						}
						else {
							progress = nil
						}

						self?.log("#startTunnel progress=\(progress?.description ?? "(nil)")")

						progressCallback(progress)

						if progress ?? 0 >= 100 {
							self?.torController?.removeObserver(self?.progressObs)
						}

						return true
					}

					return false
				})

				self.establishedObs = self.torController?.addObserver(forCircuitEstablished: { [weak self] established in
					guard established else {
						return
					}

					self?.torController?.removeObserver(self?.establishedObs)
					self?.torController?.removeObserver(self?.progressObs)

					self?.torController?.getInfoForKeys(["net/listeners/socks"]) { response in
						guard let parts = response.first?.split(separator: ":"),
							  let host = parts.first,
							  let host = IPv4Address(String(host)),
							  let port = parts.last,
							  let port = NWEndpoint.Port(String(port))
						else {
							self?.stop()

							return completion(Errors.noSocksAddr)
						}

						self?.torSocks5 = .hostPort(host: NWEndpoint.Host.ipv4(host), port: port)

						self?.status = .started

						completion(nil)
					}
				})
			}
		}
	}

	func stop() {
		status = .stopped

		torController?.removeObserver(self.establishedObs)
		torController?.removeObserver(self.progressObs)

		torController?.disconnect()
		torController = nil

		torThread?.cancel()
		torThread = nil

		torConf = nil
	}

	func getCircuits(_ completion: @escaping ([TorCircuit]) -> Void) {
		if let torController = torController {
			torController.getCircuits(completion)
		}
		else {
			completion([])
		}
	}

	func close(_ circuits: [TorCircuit], _ completion: ((Bool) -> Void)?) {
		if let torController = torController {
			torController.close(circuits, completion: completion)
		}
		else {
			completion?(false)
		}
	}

	func close(_ ids: [String], _ completion: ((Bool) -> Void)?) {
		if let torController = torController {
			torController.closeCircuits(byIds: ids, completion: completion)
		}
		else {
			completion?(false)
		}
	}


	// MARK: Private Methods

	private func log(_ message: String) {
		print("[\(String(describing: type(of: self)))] \(message)")
	}

	private func getTorConf() -> TorConfiguration {
		let conf = TorConfiguration()

		conf.ignoreMissingTorrc = true
		conf.cookieAuthentication = true
		conf.autoControlPort = true
		conf.clientOnly = true
		conf.avoidDiskWrites = true
		conf.dataDirectory = FileManager.default.torDir
		conf.clientAuthDirectory = FileManager.default.authDir

		// GeoIP files for circuit node country display.
		conf.geoipFile = Bundle.geoIp?.geoipFile
		conf.geoip6File = Bundle.geoIp?.geoip6File

		var arguments = [String]()
//		arguments.append(contentsOf: ipStatus.torConf(transport, Transport.asArguments).joined())

		// Urgh. Transports and IP settings where ignored on first start.
		// Careful: `arguments as? NSMutableCopy == nil`
		conf.arguments.addObjects(from: arguments)

#if DEBUG
		let log = "notice stdout"
#else
		let log = "err file /dev/null"
#endif

		conf.options = [
			// Log
			"Log": log,
			"LogMessageDomains": "1",
			"SafeLogging": "1",

			// SOCKS5
			"SocksPort": "auto"]

		return conf
	}
}
