//
//  AboutSchemaHandler.swift
//  AnyoneBrowser
//
//  Created by Benjamin Erhart on 16.04.25.
//  Copyright © 2025 Anyone. All rights reserved.
//

import Foundation
import WebKit

public class AboutSchemaHandler: NSObject, WKURLSchemeHandler {

	public class func register(_ conf: WKWebViewConfiguration) {
		let handler = AboutSchemaHandler()

		conf.setURLSchemeHandler(handler, forURLScheme: "anyoneabout")
	}


	public func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
		let url = urlSchemeTask.request.url?.withFixedScheme

		switch url {
		case URL.blank:
			send(url!, .init(), to: urlSchemeTask)

		case URL.aboutAnyoneBrowser, URL.aboutSecurityLevels:
			do {
				let data = try Data(contentsOf: url!.real)

				send(url!, data, to: urlSchemeTask)
			}
			catch {
				urlSchemeTask.didFailWithError(error)
			}

		default:
			urlSchemeTask.didFailWithError(
				NSError(
					domain: NSURLErrorDomain,
					code: NSURLErrorFileDoesNotExist,
					userInfo: [NSLocalizedDescriptionKey : "Not found"]))
		}
	}

	public func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
		// Ignored. All requests are fulfilled immediately.
	}

	private func send(_ url: URL, _ data: Data, to urlSchemeTask: any WKURLSchemeTask) {
		urlSchemeTask.didReceive(.init(
			url: url, mimeType: "text/html",
			expectedContentLength: data.count, textEncodingName: nil))

		urlSchemeTask.didReceive(data)
		urlSchemeTask.didFinish()
	}
}
