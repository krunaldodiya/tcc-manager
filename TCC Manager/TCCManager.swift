//
//  TCCManager.swift
//  TCC Manager
//
//  Created by Krunal Dodiya on 31/12/25.
//

import Foundation
import SQLite3
import AppKit

class TCCManager {
    nonisolated static let shared = TCCManager()
    
    private let tccDbUser: URL
    private let tccDbSystem: URL
    
    nonisolated private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        tccDbUser = homeDir.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        tccDbSystem = URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db")
    }
    
    // MARK: - Bundle ID
    
    func getBundleId(for appPath: String) -> String? {
        let infoPlistPath = (appPath as NSString).appendingPathComponent("Contents/Info.plist")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", infoPlistPath, "CFBundleIdentifier"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let bundleId = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return bundleId?.isEmpty == false ? bundleId : nil
        } catch {
            return nil
        }
    }
    
    // MARK: - Check Permissions
    
    func checkPermissions(for appPath: String) async -> PermissionStatus {
        // Use native Swift SQLite for direct database queries
        return await Task.detached {
            guard let bundleId = Self.getBundleIdSync(for: appPath) else {
                return PermissionStatus(camera: false, microphone: false, isLoading: false)
            }
            
            let camera = Self.checkPermission(service: "kTCCServiceCamera", bundleId: bundleId, tccDbUser: Self.tccDbUser, tccDbSystem: Self.tccDbSystem)
            let microphone = Self.checkPermission(service: "kTCCServiceMicrophone", bundleId: bundleId, tccDbUser: Self.tccDbUser, tccDbSystem: Self.tccDbSystem)
            
            print("🔍 TCCManager.checkPermissions for \(appPath): camera=\(camera), microphone=\(microphone)")
            return PermissionStatus(camera: camera, microphone: microphone, isLoading: false)
        }.value
    }
    
    nonisolated private static func getBundleIdSync(for appPath: String) -> String? {
        let infoPlistPath = (appPath as NSString).appendingPathComponent("Contents/Info.plist")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", infoPlistPath, "CFBundleIdentifier"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let bundleId = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return bundleId?.isEmpty == false ? bundleId : nil
        } catch {
            return nil
        }
    }
    
    nonisolated private static var tccDbUser: URL {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
    }
    
    nonisolated private static var tccDbSystem: URL {
        return URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db")
    }
    
    nonisolated private static func checkPermission(service: String, bundleId: String, tccDbUser: URL, tccDbSystem: URL) -> Bool {
        // Use native Swift SQLite for direct database queries
        // Check user database first (most common location)
        if FileManager.default.fileExists(atPath: tccDbUser.path) {
            if let result = queryTCCDatabase(at: tccDbUser, service: service, bundleId: bundleId) {
                let granted = result == 2 // 2 means granted
                print("   📊 checkPermission: \(service) for \(bundleId) in user DB: auth_value=\(result), granted=\(granted)")
                return granted
            } else {
                print("   📊 checkPermission: \(service) for \(bundleId) in user DB: no result (not found or denied)")
            }
        }
        
        // Check system database as fallback
        if FileManager.default.fileExists(atPath: tccDbSystem.path) {
            if let result = queryTCCDatabase(at: tccDbSystem, service: service, bundleId: bundleId) {
                let granted = result == 2 // 2 means granted
                print("   📊 checkPermission: \(service) for \(bundleId) in system DB: auth_value=\(result), granted=\(granted)")
                return granted
            } else {
                print("   📊 checkPermission: \(service) for \(bundleId) in system DB: no result (not found or denied)")
            }
        }
        
        print("   📊 checkPermission: \(service) for \(bundleId): returning false (not found in either DB)")
        return false
    }
    
    nonisolated private static func queryTCCDatabase(at url: URL, service: String, bundleId: String) -> Int? {
        var db: OpaquePointer?
        
        // Try to open database - this requires Full Disk Access
        let dbPath = url.path
        
        // Close any existing connections first to ensure fresh read
        // Use SQLITE_OPEN_READONLY to avoid locking issues
        // Use SQLITE_OPEN_NOMUTEX to avoid connection pooling
        // Use SQLITE_OPEN_FULLMUTEX to ensure thread safety
        let openResult = sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard openResult == SQLITE_OK, let db = db else {
            print("   ❌ Failed to open TCC database at \(dbPath): \(openResult)")
            return nil
        }
        
        defer {
            sqlite3_close(db)
        }
        
        // Force fresh read - completely disable caching and use WAL mode if available
        sqlite3_exec(db, "PRAGMA cache_size = 0;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous = NORMAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, nil) // Use WAL for better read consistency
        sqlite3_exec(db, "PRAGMA read_uncommitted = 0;", nil, nil, nil) // Read only committed data
        
        let query = "SELECT auth_value FROM access WHERE service=? AND client=?;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("   ❌ Failed to prepare query: \(query)")
            return nil
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        // Bind parameters - ensure strings are properly null-terminated
        let serviceCString = service.cString(using: .utf8)
        let bundleIdCString = bundleId.cString(using: .utf8)
        
        guard let serviceCString = serviceCString,
              let bundleIdCString = bundleIdCString,
              sqlite3_bind_text(statement, 1, serviceCString, -1, nil) == SQLITE_OK,
              sqlite3_bind_text(statement, 2, bundleIdCString, -1, nil) == SQLITE_OK else {
            print("   ❌ Failed to bind parameters")
            return nil
        }
        
        let stepResult = sqlite3_step(statement)
        if stepResult == SQLITE_ROW {
            let authValue = sqlite3_column_int(statement, 0)
            print("   ✅ Query result: auth_value=\(authValue) for service=\(service), client=\(bundleId)")
            return Int(authValue)
        } else if stepResult == SQLITE_DONE {
            print("   ⚠️ Query returned no rows for service=\(service), client=\(bundleId)")
        } else {
            print("   ❌ Query step failed with code: \(stepResult)")
        }
        
        return nil
    }
    
    // MARK: - Toggle Permissions
    
    func toggleCameraPermission(for appPath: String, grant: Bool) async throws {
        guard let bundleId = getBundleId(for: appPath) else {
            throw TCCError.couldNotGetBundleId
        }
        
        try await togglePermission(service: "kTCCServiceCamera", bundleId: bundleId, grant: grant)
    }
    
    func toggleMicrophonePermission(for appPath: String, grant: Bool) async throws {
        guard let bundleId = getBundleId(for: appPath) else {
            throw TCCError.couldNotGetBundleId
        }
        
        try await togglePermission(service: "kTCCServiceMicrophone", bundleId: bundleId, grant: grant)
    }
    
    private func togglePermission(service: String, bundleId: String, grant: Bool) async throws {
        print("🔧 TCCManager: \(grant ? "Granting" : "Revoking") \(service) permission for \(bundleId)")
        
        if grant {
            try await grantPermission(service: service, bundleId: bundleId)
        } else {
            try await revokePermission(service: service, bundleId: bundleId)
        }
        
        // Small delay to ensure database changes are fully committed to disk
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Notify TCC daemon and System Settings to refresh
        notifyTCCDaemon()
        
        print("✅ TCCManager: Successfully \(grant ? "granted" : "revoked") \(service) permission for \(bundleId)")
    }
    
    private func grantPermission(service: String, bundleId: String) async throws {
        var db: OpaquePointer?
        let dbPath = tccDbUser.path
        
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw TCCError.databaseNotFound
        }
        
        // Open database with write access
        let openResult = sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard openResult == SQLITE_OK, let db = db else {
            throw TCCError.databaseError("Failed to open TCC database: \(openResult)")
        }
        
        defer {
            sqlite3_close(db)
        }
        
        // INSERT OR REPLACE with auth_value=2 (granted)
        let query = """
            INSERT OR REPLACE INTO access (
                service, 
                client, 
                client_type, 
                auth_value, 
                auth_reason, 
                auth_version, 
                indirect_object_identifier, 
                flags, 
                last_modified
            ) VALUES (?, ?, 0, 2, 4, 1, 'UNUSED', 0, CAST(strftime('%s','now') AS INTEGER));
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw TCCError.databaseError("Failed to prepare INSERT statement")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        // Bind parameters
        let serviceCString = service.cString(using: .utf8)
        let bundleIdCString = bundleId.cString(using: .utf8)
        
        guard let serviceCString = serviceCString,
              let bundleIdCString = bundleIdCString,
              sqlite3_bind_text(statement, 1, serviceCString, -1, nil) == SQLITE_OK,
              sqlite3_bind_text(statement, 2, bundleIdCString, -1, nil) == SQLITE_OK else {
            throw TCCError.databaseError("Failed to bind parameters")
        }
        
        // Execute
        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            throw TCCError.databaseError("Failed to execute INSERT: \(stepResult)")
        }
        
        // Force database to flush changes to disk immediately
        sqlite3_exec(db, "PRAGMA synchronous = FULL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA wal_checkpoint(FULL);", nil, nil, nil)
        
        // Ensure changes are committed
        sqlite3_exec(db, "COMMIT;", nil, nil, nil)
    }
    
    private func revokePermission(service: String, bundleId: String) async throws {
        var db: OpaquePointer?
        let dbPath = tccDbUser.path
        
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw TCCError.databaseNotFound
        }
        
        // Open database with write access
        let openResult = sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard openResult == SQLITE_OK, let db = db else {
            throw TCCError.databaseError("Failed to open TCC database: \(openResult)")
        }
        
        defer {
            sqlite3_close(db)
        }
        
        // DELETE from access table
        let query = "DELETE FROM access WHERE service=? AND client=? AND client_type=0 AND indirect_object_identifier='UNUSED';"
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw TCCError.databaseError("Failed to prepare DELETE statement")
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        // Bind parameters
        let serviceCString = service.cString(using: .utf8)
        let bundleIdCString = bundleId.cString(using: .utf8)
        
        guard let serviceCString = serviceCString,
              let bundleIdCString = bundleIdCString,
              sqlite3_bind_text(statement, 1, serviceCString, -1, nil) == SQLITE_OK,
              sqlite3_bind_text(statement, 2, bundleIdCString, -1, nil) == SQLITE_OK else {
            throw TCCError.databaseError("Failed to bind parameters")
        }
        
        // Execute
        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            throw TCCError.databaseError("Failed to execute DELETE: \(stepResult)")
        }
        
        // Force database to flush changes to disk immediately
        sqlite3_exec(db, "PRAGMA synchronous = FULL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA wal_checkpoint(FULL);", nil, nil, nil)
        
        // Ensure changes are committed
        sqlite3_exec(db, "COMMIT;", nil, nil, nil)
    }
    
    private func notifyTCCDaemon() {
        // Multiple approaches to ensure System Settings updates in real-time
        
        // 1. Touch the database file to trigger file system notifications
        let dbPath = tccDbUser.path
        if FileManager.default.fileExists(atPath: dbPath) {
            do {
                try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: dbPath)
            } catch {
                print("⚠️ Could not touch TCC database file: \(error.localizedDescription)")
            }
        }
        
        // 2. Send SIGHUP to all tccd processes (user and system)
        let killallProcess = Process()
        killallProcess.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killallProcess.arguments = ["-HUP", "tccd"]
        
        do {
            try killallProcess.run()
            killallProcess.waitUntilExit()
        } catch {
            print("⚠️ Could not notify TCC daemon via killall: \(error.localizedDescription)")
        }
        
        // 3. Post distributed notifications to notify System Settings
        // These are the notifications that System Settings listens to for real-time updates
        let notificationCenter = DistributedNotificationCenter.default()
        
        // Try multiple notification names that System Settings might listen to
        let notificationNames = [
            "com.apple.TCC.accessChanged",
            "com.apple.preference.security.privacy",
            "com.apple.TCC.databaseChanged",
            "com.apple.security.TCCChanged"
        ]
        
        for notificationName in notificationNames {
            notificationCenter.post(
                name: NSNotification.Name(notificationName),
                object: nil,
                userInfo: nil
            )
        }
        
        // 4. Also try posting to the local notification center
        NotificationCenter.default.post(
            name: NSNotification.Name("com.apple.TCC.accessChanged"),
            object: nil
        )
        
        // 5. Small delay to ensure database changes are flushed and notifications are processed
        Thread.sleep(forTimeInterval: 0.15)
        
        print("✅ TCC daemon notification sent (killall + notifications)")
    }
}

enum TCCError: LocalizedError {
    case couldNotGetBundleId
    case databaseNotFound
    case databaseError(String)
    
    var errorDescription: String? {
        switch self {
        case .couldNotGetBundleId:
            return "Could not get bundle ID from app"
        case .databaseNotFound:
            return "TCC database not found. Please ensure Full Disk Access is granted."
        case .databaseError(let message):
            return "Database error: \(message)"
        }
    }
}

