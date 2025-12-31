//
//  PermissionChecker.swift
//  TCC Manager
//
//  Created by Krunal Dodiya on 31/12/25.
//

import Foundation
import AppKit

class PermissionChecker {
    nonisolated static let shared = PermissionChecker()
    
    nonisolated private init() {}
    
    /// Check if the app has Full Disk Access by attempting to read the TCC database
    func hasFullDiskAccess() -> Bool {
        let tccDbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
            .path
        
        print("🔍 Checking Full Disk Access...")
        print("   TCC DB Path: \(tccDbPath)")
        print("   File exists: \(FileManager.default.fileExists(atPath: tccDbPath))")
        print("   Is readable: \(FileManager.default.isReadableFile(atPath: tccDbPath))")
        
        // Try to read the database file
        // If we can't access it, we don't have Full Disk Access
        guard FileManager.default.isReadableFile(atPath: tccDbPath) else {
            print("   ❌ Cannot read TCC database file - no Full Disk Access")
            return false
        }
        
        // Try to actually query the database
        // Just reading the file isn't enough - we need to be able to query it
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [tccDbPath, "SELECT 1 LIMIT 1;"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            
            print("   SQLite query exit status: \(process.terminationStatus)")
            if !errorOutput.isEmpty {
                print("   SQLite error: \(errorOutput)")
            }
            
            // If we can execute the query, we have Full Disk Access
            let hasAccess = process.terminationStatus == 0
            print("   ✅ Has Full Disk Access: \(hasAccess)")
            return hasAccess
        } catch {
            print("   ❌ Failed to execute SQLite query: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Show an alert asking the user to grant Full Disk Access
    func requestFullDiskAccess() {
        let alert = NSAlert()
        alert.messageText = "Full Disk Access Required"
        alert.informativeText = """
        TCC Manager needs Full Disk Access to read and manage TCC permissions.
        
        Please grant Full Disk Access:
        1. Click "Open System Settings" below
        2. Find "TCC Manager" in the list
        3. Enable the checkbox
        4. Restart the app
        
        Without this permission, the app cannot check or modify permissions.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // Open System Settings to Full Disk Access page
            openFullDiskAccessSettings()
        }
    }
    
    /// Open System Settings to the Full Disk Access page
    func openFullDiskAccessSettings() {
        // Open System Settings to Privacy & Security → Full Disk Access
        // For macOS 13+ (Ventura and later)
        if #available(macOS 13.0, *) {
            // macOS 13+ uses new System Settings URL scheme
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
        } else {
            // macOS 12 and earlier
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

