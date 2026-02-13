//
//  ViewController.swift
//  SQLiteREST
//
//  Created by Weirui Kong on 11/28/2025.
//  Copyright (c) 2025 Weirui Kong. All rights reserved.
//

import UIKit
import SQLiteREST

class ViewController: UIViewController {

    @IBOutlet weak var logTextView: UITextView!

    private let defaultPort: UInt = 8080
    private let defaultDatabaseName = "Northwind_small.sqlite"

    /// 新版 API 服务（Swift + GCDWebServer，/api/v1/*）
    private let apiServer = SQLiteRESTAPIServer()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupServer()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed || isMovingFromParentViewController {
            apiServer.stop()
        }
    }

    deinit {
        apiServer.stop()
    }

    private func setupUI() {
        // Create log text view if not connected via IB
        if logTextView == nil {
            logTextView = UITextView()
            logTextView.translatesAutoresizingMaskIntoConstraints = false
            logTextView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            logTextView.backgroundColor = UIColor.systemBackground
            logTextView.textColor = UIColor.label
            logTextView.isEditable = false
            logTextView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
            view.addSubview(logTextView)

            NSLayoutConstraint.activate([
                logTextView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                logTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                logTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                logTextView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }

        logTextView.text = "SQLiteREST API Server (v1)\n" + String(repeating: "=", count: 50) + "\n\n"
    }

    private func setupServer() {
        guard let databasePath = Bundle.main.path(forResource: "Northwind_small", ofType: "sqlite") else {
            appendLog("ERROR: Could not find \(defaultDatabaseName) in bundle")
            return
        }

        appendLog("Database: \(databasePath)")
        appendLog("Starting API server on port \(defaultPort)...")

        do {
            try apiServer.start(databasePath: databasePath, port: defaultPort)
            if let url = apiServer.serverURL {
                let base = url.absoluteString.hasSuffix("/") ? url.absoluteString : url.absoluteString + "/"
                let apiBase = base + "api/v1"
                appendLog("Server started: \(url.absoluteString)")
                appendLog("API base: \(apiBase)")
                appendLog("")
                appendLog("Examples:")
                appendLog("  GET  \(apiBase)/db/info")
                appendLog("  GET  \(apiBase)/tables")
                appendLog("  GET  \(apiBase)/tables/Product/rows?_page=1&_per_page=10")
            } else {
                appendLog("Server started (URL unknown)")
            }
        } catch {
            appendLog("ERROR: Failed to start server: \(error.localizedDescription)")
        }
    }
    
    private func appendLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logMessage = "[\(timestamp)] \(message)\n"
        
        if let textView = logTextView {
            textView.text += logMessage
            
            // Auto scroll to bottom
            let bottom = NSRange(location: textView.text.count - 1, length: 1)
            textView.scrollRangeToVisible(bottom)
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}

