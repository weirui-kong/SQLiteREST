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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupServer()
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
        
        logTextView.text = "SQLiteREST Server Log\n" + String(repeating: "=", count: 50) + "\n\n"
    }
    
    private func setupServer() {
        let server = SQLiteRESTServer.sharedInstance()
        
        // Set up log handler
        server.logHandler = { [weak self] message in
            DispatchQueue.main.async {
                self?.appendLog(message)
            }
        }
        
        // Get database path
        guard let databasePath = Bundle.main.path(forResource: "Northwind_small", ofType: "sqlite") else {
            appendLog("ERROR: Could not find \(defaultDatabaseName) in bundle")
            return
        }
        
        appendLog("Starting server on port \(defaultPort)...")
        appendLog("Database: \(databasePath)")
        server.stop()
        // Start server
        server.start(onPort: defaultPort, withPath: databasePath)
        server.start(onPort: defaultPort, withPath: databasePath)
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

