//
//  TlsCertificate.swift
//  AnyoneBrowser
//
//  Created by Benjamin Erhart on 30.01.25.
//  Copyright © 2025 Anyone. All rights reserved.
//

import UIKit
import DTFoundation
import OSLog

@objcMembers
class TlsCertificate: NSObject {


	/**
	 X.509 version
	 */
	private(set) var version = 0

	/**
	 Certificate serial number (string of hex bytes)
	 */
	private(set) var serialNumber = ""

	private(set) var signatureAlgorithm = ""

	private(set) var issuer = Entity()

	private(set) var validityNotBefore = Date()
	private(set) var validityNotAfter = Date()

	private(set) var subject = Entity()

	private(set) var isEv = false
	private(set) var evOrgName: String?

	var hasWeakSignatureAlgorithm: Bool {
		signatureAlgorithm.lowercased().contains("sha1")
	}

	var isExpired: Bool {
		Date() > self.validityNotAfter
	}



	private static let cache: NSCache<NSData, TlsCertificate> = {
		let cache = NSCache<NSData, TlsCertificate>()
		cache.countLimit = 32

		return cache
	}()

	private let log = Logger(
		subsystem: Bundle(for: TlsCertificate.self).bundleIdentifier ?? .init(describing: TlsCertificate.self),
		category: .init(describing: TlsCertificate.self))


	class func load(trust: SecTrust) -> TlsCertificate? {
		let cert = unsafeBitCast(CFArrayGetValueAtIndex(SecTrustCopyCertificateChain(trust), 0), to: SecCertificate.self)
		let data = SecCertificateCopyData(cert)

		guard let certHash = (data as NSData).withSHA1Hash() as NSData? else {
			return nil
		}

		let tlsCert = cache.object(forKey: certHash) ?? self.init(data: data as Data)

		let trustDict = SecTrustCopyResult(trust) as NSDictionary?
		let ev = trustDict?[kSecTrustExtendedValidation]

		if let ev = ev, (ev as! CFBoolean) == kCFBooleanTrue {
			tlsCert?.isEv = true
			tlsCert?.evOrgName = trustDict?[kSecTrustOrganizationName] as? String
		}

		if let tlsCert = tlsCert {
			cache.setObject(tlsCert, forKey: certHash)
		}

		return tlsCert
	}


	/* x509 cert structure:

		Certificate
			Data
				Version
				Serial Number
			Signature Algorithm ID
				Issuer
				Validity
					Not Before
					Not After
				Subject
				Subject Public Key Info
					Public Key Algorithm
					Subject Public Key
				Issuer Unique Identifier (optional)
				Subject Unique Identifier (optional)
				Extensions (optional)
					...
			Certificate Signature Algorithm
			Certificate Signature

	*/
	required init?(data: Data) {
		super.init()

		guard let t = DTASN1Serialization.object(with: data),
			  let oidtree = t as? [Any]
		else {
			log.error("OID tree fetching failed")
			return nil
		}

		guard let cert = Self.get(oidtree, i: 0, type: [Any].self) else {
			return nil
		}

		var cData = Self.get(cert, i: 0, type: [Any].self)

		if cData == nil {
			guard let cDic = Self.get(cert, i: 0, type: [AnyHashable: Any].self),
				  let key = cDic.keys.first
			else {
				return nil
			}

			cData = Self.get(cDic[key] as? [Any], i: 0, type: [Any].self)
		}

		guard let cData = cData,
			  let tver = Self.get(cData, i: 0, type: Int.self)
		else {
			return nil
		}

		// 0-based: https://tools.ietf.org/html/rfc2459#section-4.1
		version = tver + 1


		// Serial number

		var tserial = [String]()

		if let tt = Self.get(cert, i: 1, type: Int64.self) {
			var ttn = tt

			while (ttn > 0) {
				tserial.append(.init(format: "%02lx", (ttn & 0xff)))
				ttn >>= 8;
			}

			tserial.reverse()
		}
		else if let tt = Self.get(cert, i: 1, type: Data.self) {
			tserial = tt.map {
				.init(format: "%02x", $0)
			}
		}

		serialNumber = tserial.joined(separator: ":")


		// signature algorithm (string representation - https://tools.ietf.org/html/rfc7427#page-12)

		guard let sigAlgTree = Self.get(cert, i: 2, type: [Any].self),
			  let sigAlgOid = Self.get(sigAlgTree, i: 0, type: String.self)
		else {
			return nil
		}

		signatureAlgorithm = Self.map(sigAlgOid: sigAlgOid)


		// Cert issuer (hash of assorted keys like locale, org, etc.)

		guard let issuer = Self.parseEntity(Self.get(cert, i: 3, type: [Any].self)) else {
			return nil
		}

		self.issuer = issuer


		// Validity Period

		guard let validityPeriod = Self.get(cert, i: 4, type: [Any].self),
			  let validityNotBefore = Self.get(validityPeriod, i: 0, type: Date.self),
			  let validityNotAfter = Self.get(validityPeriod, i: 1, type: Date.self)
		else {
			return nil
		}

		self.validityNotBefore = validityNotBefore
		self.validityNotAfter = validityNotAfter


		// Subject

		guard let subject = Self.parseEntity(Self.get(cert, i: 5, type: [Any].self)) else {
			return nil
		}

		self.subject = subject

		log.trace("Parsed certificate for \(subject.commonName ?? ""): version=\(self.version), serial=\(self.serialNumber), sigalg=\(self.signatureAlgorithm), issuer=\(issuer.commonName ?? ""), valid=\(validityNotBefore) to \(validityNotAfter)")
	}


	// MARK: Private Methods

	private class func get<T>(_ array: [Any]?, i: Int, type: T.Type) -> T? {
		guard let array = array else {
			return nil
		}

		if i >= array.count {
			return nil
		}

		let val = array[i]

		guard let x = val as? T else {
			return nil
		}

		return x
	}

	private class func parseEntity(_ data: [Any]?) -> Entity? {
		guard let data = data else {
			return nil
		}

		let entity = Entity()

		for i in data {
			guard let pairA = i as? [Any] else {
				continue
			}

			for j in pairA {
				guard let oidPair = j as? [Any] else {
					return nil
				}

				guard let oid = get(oidPair, i: 0, type: String.self),
					  let val = get(oidPair, i: 1, type: String.self)
				else {
					continue
				}

				entity.add(oid, val)
			}
		}

		return entity
	}

	private class func map(sigAlgOid: String) -> String {
		switch sigAlgOid {
		case "1.2.840.113549.1.1.5":
			return "sha1WithRSAEncryption"

		case "1.2.840.113549.1.1.11":
			return "sha256WithRSAEncryption"

		case "1.2.840.113549.1.1.12":
			return "sha384WithRSAEncryption"

		case "1.2.840.113549.1.1.13":
			return "sha512WithRSAEncryption"

		case "1.2.840.10040.4.3":
			return "dsa-with-sha1"

		case "2.16.840.1.101.3.4.3.2":
			return "dsa-with-sha256"

		case "1.2.840.10045.4.1":
			return "ecdsa-with-sha1"

		case "1.2.840.10045.4.3.2":
			return "ecdsa-with-sha256"

		case "1.2.840.10045.4.3.3":
			return "ecdsa-with-sha384"

		case "1.2.840.10045.4.3.4":
			return "ecdsa-with-sha512"

		default:
			return .init(format: "Unknown (%@)", sigAlgOid)
		}
	}

	@objc(TlsCertificateEntity)
	@objcMembers
	class Entity: NSObject {

		static let oidCn = "2.5.4.3"
		static let oidSn = "2.5.4.4"
		static let oidSerialNumber = "2.5.4.5"
		static let oidC = "2.5.4.6"
		static let oidL = "2.5.4.7"
		static let oidSt = "2.5.4.8"
		static let oidStreet = "2.5.4.9"
		static let oidO = "2.5.4.10"
		static let oidOu = "2.5.4.11"
		static let oidBusinessCategory = "2.5.4.15"
		static let oidZip = "2.5.4.17"

		static let mainOids = [
			oidCn, oidO, oidOu, oidStreet, oidL, oidSt, oidZip, oidC]

		static let labels = [
			oidCn: "Common Name (CN)",
			oidSn: "Serial Number (SN)",
			oidSerialNumber: "Serial Number",
			oidC: "Country (C)",
			oidL: "Locality (L)",
			oidSt: "State/Province (ST)",
			oidStreet: "Street Address",
			oidO: "Organization (O)",
			oidOu: "Organizational Unit Number (OU)",
			oidBusinessCategory: "Business Category",
			oidZip: "Postal Code",
		]


		private(set) var data = [String: [String]]()

		var commonName: String? {
			data[Self.oidCn]?.first
		}

		var sn: String? {
			data[Self.oidSn]?.first
		}

		var serialNumber: String? {
			data[Self.oidSerialNumber]?.first
		}

		var country: String? {
			data[Self.oidC]?.first
		}

		var locality: String? {
			data[Self.oidL]?.first
		}

		var state: String? {
			data[Self.oidSt]?.first
		}

		var address: String? {
			data[Self.oidStreet]?.first
		}

		var organization: String? {
			data[Self.oidO]?.first
		}

		var orgUnit: String? {
			data[Self.oidOu]?.first
		}

		var businessCategory: String? {
			data[Self.oidBusinessCategory]?.first
		}

		var postalCode: String? {
			data[Self.oidZip]?.first
		}


		class func label(_ oid: String) -> String {
			labels[oid] ?? "Object Identifier \(oid)"
		}

		func add(_ oid: String, _ value: String) {
			if data[oid] == nil {
				data[oid] = []
			}

			data[oid]?.append(value)
		}


		func get(_ oid: String) -> (label: String, value: String)? {
			guard let value = data[oid]?.first else {
				return nil
			}

			return (label: Self.label(oid), value: value)
		}

		func getAll() -> [(label: String, value: String)] {
			var all = [(label: String, value: String)]()

			for oid in Self.mainOids {
				if let pair = get(oid) {
					all.append(pair)
				}
			}

			for oid in data.keys.filter({ !Self.mainOids.contains($0) }) {
				if let pair = get(oid) {
					all.append(pair)
				}
			}

			return all
		}
	}

}
