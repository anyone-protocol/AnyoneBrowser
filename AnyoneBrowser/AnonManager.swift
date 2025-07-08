//
//  AnonManager.swift
//  AnyoneBrowser
//
//  Created by Benjamin Erhart on 28.01.25.
//

import NetworkExtension
import AnyoneKit
import Network


class AnonManager {

	enum Status: String, Codable {
		case stopped = "stopped"
		case starting = "starting"
		case started = "started"
	}

	enum Errors: Error, LocalizedError {
		case noAnonController
		case cookieUnreadable
		case noSocksAddr
		case smartConnectFailed

		var errorDescription: String? {
			switch self {

			case .noAnonController:
				return "No Anon controller"

			case .cookieUnreadable:
				return "Anon cookie unreadable"

			case .noSocksAddr:
				return "No SOCKS port"

			case .smartConnectFailed:
				return "Smart Connect failed"
			}
		}
	}

	static let shared = AnonManager()

	static let localhost = "127.0.0.1"

	var status: Status {
		if !anonRunning {
			return .stopped
		}

		if (anonController?.isConnected ?? false) && anonSocks5 != nil {
			return .started
		}

		return .starting
	}

	private(set) var anonSocks5: Network.NWEndpoint? = nil

	private var anonThread: AnonThread?

	private var anonController: AnonController?

	private var anonConf: AnonConfiguration?

	private var anonRunning: Bool {
		 ((anonThread?.isExecuting ?? false) && (anonConf?.isLocked ?? false))
	}

	private lazy var controllerQueue = DispatchQueue.global(qos: .userInitiated)

	private var ipStatus = IpSupport.Status.unavailable

	private var progressObs: Any?
	private var establishedObs: Any?


	private init() {
		IpSupport.shared.start({ [weak self] status in
			self?.ipStatus = status

			if (self?.anonRunning ?? false) && (self?.anonController?.isConnected ?? false) {
				self?.anonController?.setConfs(status.anonConf(IpSupport.Status.asConf))
				{ success, error in
					if let error = error {
						self?.log("error: \(error)")
					}

					self?.anonController?.resetConnection()
				}
			}
		})
	}

	func start(_ progressCallback: @escaping (_ progress: Int?, _ summary: String?) -> Void,
			   _ completion: @escaping (Error?) -> Void)
	{
		if !anonRunning {
			anonConf = getAnonConf()

//			if let debug = anonConf?.compile().joined(separator: ", ") {
//				Log.debug(for: Self.self, debug)
//			}

			anonThread = AnonThread(configuration: anonConf)

			anonThread?.start()
		}

		controllerQueue.asyncAfter(deadline: .now() + 0.65) {
			if self.anonController == nil, let url = self.anonConf?.controlPortFile {
				self.anonController = AnonController(controlPortFile: url)
			}

			guard let anonController = self.anonController else {
				self.log("#startTunnel error=\(Errors.noAnonController)")

				self.stop()

				return completion(Errors.noAnonController)
			}


			if !anonController.isConnected {
				do {
					try anonController.connect()
				}
				catch let error {
					self.log("#startTunnel error=\(error)")

					self.stop()

					return completion(error)
				}
			}

			guard let cookie = self.anonConf?.cookie else {
				self.log("#startTunnel cookie unreadable")

				self.stop()

				return completion(Errors.cookieUnreadable)
			}

			anonController.authenticate(with: cookie) { success, error in
				if let error = error {
					self.log("#startTunnel error=\(error)")

					self.stop()

					return completion(error)
				}

				self.progressObs = anonController.addObserver(forStatusEvents: {
					[weak self] (type, severity, action, arguments) -> Bool in

					if type == "STATUS_CLIENT" && action == "BOOTSTRAP" {
						self?.log("#startTunnel arguments=\(arguments?.description ?? "(nil)")")

						var progress: Int? = nil
						if let p = arguments?["PROGRESS"] {
							progress = Int(p)
						}

						progressCallback(progress, arguments?["SUMMARY"])

						if progress ?? 0 >= 100 {
							anonController.removeObserver(self?.progressObs)
						}

						return true
					}

					return false
				})

				self.establishedObs = anonController.addObserver(forCircuitEstablished: { [weak self] established in
					guard established else {
						return
					}

					anonController.removeObserver(self?.establishedObs)
					anonController.removeObserver(self?.progressObs)

					anonController.getInfoForKeys(["net/listeners/socks"]) { response in
						guard let parts = response.first?.split(separator: ":"),
							  let host = parts.first,
							  let host = IPv4Address(String(host)),
							  let port = parts.last,
							  let port = NWEndpoint.Port(String(port))
						else {
							self?.stop()

							return completion(Errors.noSocksAddr)
						}

						self?.anonSocks5 = .hostPort(host: NWEndpoint.Host.ipv4(host), port: port)

						completion(nil)
					}
				})
			}
		}
	}

	func stop() {
		anonSocks5 = nil

		anonController?.removeObserver(self.establishedObs)
		anonController?.removeObserver(self.progressObs)

		anonController?.disconnect()
		anonController = nil

		anonThread?.cancel()
		anonThread = nil

		anonConf = nil
	}

	func getCircuits(_ completion: @escaping ([AnonCircuit]) -> Void) {
		if let anonController = anonController {
			anonController.getCircuits(completion)
		}
		else {
			completion([])
		}
	}

	func close(_ circuits: [AnonCircuit], _ completion: ((Bool) -> Void)?) {
		if let anonController = anonController {
			anonController.close(circuits, completion: completion)
		}
		else {
			completion?(false)
		}
	}

	func close(_ ids: [String], _ completion: ((Bool) -> Void)?) {
		if let anonController = anonController {
			anonController.closeCircuits(byIds: ids, completion: completion)
		}
		else {
			completion?(false)
		}
	}

	func session(_ cookies: [HTTPCookie]? = nil, for url: URL? = nil, delegate: URLSessionDelegate? = nil) -> URLSession {
		let conf = URLSessionConfiguration.ephemeral
		conf.waitsForConnectivity = true
		conf.allowsConstrainedNetworkAccess = true
		conf.allowsExpensiveNetworkAccess = true

		if let cookies = cookies {
			conf.httpCookieStorage?.setCookies(cookies, for: url, mainDocumentURL: nil)
		}

		// There should be a started Anon and the correct proxy configuration available.
		// If not, use an invalid one to make the request fail and not leak.
		let proxy = anonSocks5 ?? NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
		conf.proxyConfigurations.append(.init(socksv5Proxy: proxy))

		return .init(configuration: conf, delegate: delegate, delegateQueue: .main)
	}


	/**
	 Check's Anyone's status, and if not working, returns a view controller to show instead of the browser UI.

	 - returns: A view controller to show instead of the browser UI, if status is not good.
	 */
	func checkStatus() -> UIViewController? {
		if !Settings.didWelcome {
			return WelcomeViewController()
		}

		if status == .started {
			// Built-in Anyone running. Ok.
			return nil
		}

		// No built-in Anyone running. Let the user start it!
		return StartTorViewController()
	}

	func allowRequests() -> Bool {
		return status == .started
	}


	// MARK: Private Methods

	private func log(_ message: String) {
		Log.debug(for: Self.self, message)
	}

	private func getAnonConf() -> AnonConfiguration {
		let conf = AnonConfiguration()

		conf.ignoreMissingAnonrc = true
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
		arguments.append(contentsOf: ipStatus.anonConf(IpSupport.Status.asArguments).joined())

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
