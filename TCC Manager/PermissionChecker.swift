//
//  PermissionChecker.swift
//  TCC Manager
//
//  Created by Krunal Dodiya on 31/12/25.
//

import Foundation
import AppKit
import SQLite3

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
        
        // Try to actually query the database using native Swift SQLite
        // Just reading the file isn't enough - we need to be able to query it
        var db: OpaquePointer?
        let openResult = sqlite3_open_v2(tccDbPath, &db, SQLITE_OPEN_READONLY, nil)
        
        guard openResult == SQLITE_OK, let db = db else {
            print("   ❌ Failed to open TCC database: \(openResult)")
            return false
        }
        
        defer {
            sqlite3_close(db)
        }
        
        // Try a simple query
        var statement: OpaquePointer?
        let query = "SELECT 1 LIMIT 1;"
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("   ❌ Failed to prepare query")
            return false
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        let stepResult = sqlite3_step(statement)
        let hasAccess = stepResult == SQLITE_ROW || stepResult == SQLITE_DONE
        
        print("   ✅ Has Full Disk Access: \(hasAccess)")
        return hasAccess
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

