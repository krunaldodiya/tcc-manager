//
//  TCCManager.swift
//  TCC Manager
//
//  Created by Krunal Dodiya on 31/12/25.
//

import Foundation
import SQLite3

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
        // Use the same shell script as Electron app for consistency
        // This ensures we get the exact same results
        return await Task.detached {
            let scriptPath = Self.findCheckPermissionsScriptPath()
            guard let scriptPath = scriptPath, FileManager.default.fileExists(atPath: scriptPath) else {
                print("⚠️ check_permissions.sh not found, falling back to direct query")
                // Fallback to direct query if script not found
                guard let bundleId = Self.getBundleIdSync(for: appPath) else {
                    return PermissionStatus(camera: false, microphone: false, isLoading: false)
                }
                let camera = Self.checkPermission(service: "kTCCServiceCamera", bundleId: bundleId, tccDbUser: Self.tccDbUser, tccDbSystem: Self.tccDbSystem)
                let microphone = Self.checkPermission(service: "kTCCServiceMicrophone", bundleId: bundleId, tccDbUser: Self.tccDbUser, tccDbSystem: Self.tccDbSystem)
                return PermissionStatus(camera: camera, microphone: microphone, isLoading: false)
            }
            
            // Execute the shell script (exactly like Electron does)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptPath, appPath]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                
                print("   📜 Script output: '\(output)' (exit: \(process.terminationStatus))")
                
                // Parse JSON output (same format as Electron)
                if let jsonData = output.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    let camera = (json["camera"] as? Int) == 1 || (json["camera"] as? Bool) == true
                    let microphone = (json["microphone"] as? Int) == 1 || (json["microphone"] as? Bool) == true
                    print("🔍 TCCManager.checkPermissions (via script) for \(appPath): camera=\(camera), microphone=\(microphone)")
                    return PermissionStatus(camera: camera, microphone: microphone, isLoading: false)
                } else {
                    print("   ⚠️ Failed to parse JSON from script output: '\(output)'")
                }
            } catch {
                print("❌ Failed to execute check_permissions.sh: \(error.localizedDescription)")
            }
            
            // Fallback to direct query
            guard let bundleId = Self.getBundleIdSync(for: appPath) else {
                return PermissionStatus(camera: false, microphone: false, isLoading: false)
            }
            let camera = Self.checkPermission(service: "kTCCServiceCamera", bundleId: bundleId, tccDbUser: Self.tccDbUser, tccDbSystem: Self.tccDbSystem)
            let microphone = Self.checkPermission(service: "kTCCServiceMicrophone", bundleId: bundleId, tccDbUser: Self.tccDbUser, tccDbSystem: Self.tccDbSystem)
            return PermissionStatus(camera: camera, microphone: microphone, isLoading: false)
        }.value
    }
    
    nonisolated private static func findCheckPermissionsScriptPath() -> String? {
        // Check in app bundle resources (for production)
        if let bundlePath = Bundle.main.resourcePath {
            let resourcePath = (bundlePath as NSString).appendingPathComponent("check_permissions.sh")
            if FileManager.default.fileExists(atPath: resourcePath) {
                return resourcePath
            }
        }
        
        // Check in project source directory (for development)
        let sourceFile = #file
        let sourceFileURL = URL(fileURLWithPath: sourceFile)
        let currentPath = sourceFileURL.deletingLastPathComponent().path
        let scriptPath = (currentPath as NSString).appendingPathComponent("check_permissions.sh")
        if FileManager.default.fileExists(atPath: scriptPath) {
            return scriptPath
        }
        
        // Check in common development locations
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let possiblePaths = [
            (homeDir as NSString).appendingPathComponent("WorkSpace/Code/TCC Manager/TCC Manager/check_permissions.sh"),
            (homeDir as NSString).appendingPathComponent("WorkSpace/Code/tcc-permissions-manager/check_permissions.sh")
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        return nil
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
        // Use shell command to query (like Electron does) to avoid SQLite connection caching issues
        // This ensures we always get fresh data from the database
        
        // Check user database first (most common location)
        if FileManager.default.fileExists(atPath: tccDbUser.path) {
            if let result = queryTCCDatabaseViaShell(at: tccDbUser, service: service, bundleId: bundleId) {
                let granted = result == 2 // 2 means granted
                print("   📊 checkPermission: \(service) for \(bundleId) in user DB: auth_value=\(result), granted=\(granted)")
                return granted
            } else {
                print("   📊 checkPermission: \(service) for \(bundleId) in user DB: no result (not found or denied)")
            }
        }
        
        // Check system database as fallback
        if FileManager.default.fileExists(atPath: tccDbSystem.path) {
            if let result = queryTCCDatabaseViaShell(at: tccDbSystem, service: service, bundleId: bundleId) {
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
    
    nonisolated private static func queryTCCDatabaseViaShell(at url: URL, service: String, bundleId: String) -> Int? {
        // Use sqlite3 shell command (like Electron's check_permissions.sh) to avoid connection caching
        let dbPath = url.path
        
        // Escape single quotes in bundleId for SQL
        let escapedBundleId = bundleId.replacingOccurrences(of: "'", with: "''")
        let query = "SELECT auth_value FROM access WHERE service='\(service)' AND client='\(escapedBundleId)';"
        let command = "sqlite3 \"\(dbPath)\" \"\(query)\""
        
        print("   🔍 Shell query: \(command)")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let error = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            print("   🔍 Shell output: '\(output)' (exit: \(process.terminationStatus))")
            if !error.isEmpty {
                print("   🔍 Shell error: '\(error)'")
            }
            
            if let authValue = Int(output), !output.isEmpty {
                print("   ✅ Parsed auth_value: \(authValue)")
                return authValue
            }
            
            print("   ⚠️ Could not parse auth_value from output: '\(output)'")
            return nil
        } catch {
            print("   ❌ Shell command failed: \(error.localizedDescription)")
            return nil
        }
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
        
        try await togglePermission(service: "Camera", bundleId: bundleId, grant: grant)
    }
    
    func toggleMicrophonePermission(for appPath: String, grant: Bool) async throws {
        guard let bundleId = getBundleId(for: appPath) else {
            throw TCCError.couldNotGetBundleId
        }
        
        try await togglePermission(service: "Microphone", bundleId: bundleId, grant: grant)
    }
    
    private func togglePermission(service: String, bundleId: String, grant: Bool) async throws {
        // Try to find tccplus in bundle resources first, then in common locations
        let tccplusPath = findTCCPlusPath()
        
        guard let tccplusPath = tccplusPath else {
            print("❌ TCCManager: tccplus binary not found")
            throw TCCError.tccplusNotFound
        }
        
        // Verify binary is executable
        guard FileManager.default.isExecutableFile(atPath: tccplusPath) else {
            print("❌ TCCManager: tccplus binary is not executable at: \(tccplusPath)")
            throw TCCError.executionFailed("tccplus binary is not executable")
        }
        
        let action = grant ? "add" : "reset"
        // Build command (tccplus handles path escaping internally)
        let command = "\"\(tccplusPath)\" \(action) \(service) \"\(bundleId)\""
        print("🔧 TCCManager: Executing command: \(command)")
        print("   Binary path: \(tccplusPath)")
        print("   Arguments: [\(action), \(service), \(bundleId)]")
        
        // Run through shell like Electron does (using /bin/bash)
        // This ensures proper path handling and environment setup
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            
            print("   Exit status: \(process.terminationStatus)")
            if !output.isEmpty {
                print("   stdout: \(output)")
            }
            if !errorOutput.isEmpty {
                print("   stderr: \(errorOutput)")
            }
            
            if process.terminationStatus != 0 {
                print("❌ TCCManager: tccplus failed with status \(process.terminationStatus)")
                let errorMsg = errorOutput.isEmpty ? output : errorOutput
                throw TCCError.executionFailed("tccplus exited with status \(process.terminationStatus): \(errorMsg)")
            } else {
                print("✅ TCCManager: tccplus executed successfully")
            }
        } catch {
            print("❌ TCCManager: Failed to execute tccplus: \(error.localizedDescription)")
            throw TCCError.executionFailed(error.localizedDescription)
        }
    }
    
    private func findTCCPlusPath() -> String? {
        // Check in app bundle resources (for production)
        if let bundlePath = Bundle.main.resourcePath {
            let resourcePath = (bundlePath as NSString).appendingPathComponent("bin/tccplus")
            if FileManager.default.fileExists(atPath: resourcePath) {
                return resourcePath
            }
        }
        
        // Check in app bundle (alternative location)
        let bundlePath = Bundle.main.bundlePath
        let bundleResourcePath = (bundlePath as NSString).appendingPathComponent("Contents/Resources/bin/tccplus")
        if FileManager.default.fileExists(atPath: bundleResourcePath) {
            return bundleResourcePath
        }
        
        // Check in project source directory (for development when running from Xcode)
        // Get the source file location and work backwards to find bin directory
        let sourceFile = #file
        let sourceFileURL = URL(fileURLWithPath: sourceFile)
        let currentPath = sourceFileURL.deletingLastPathComponent().path
        
        // The source file is in "TCC Manager/TCC Manager/TCCManager.swift"
        // So we need to go to "TCC Manager/TCC Manager/bin/tccplus"
        let binPath = (currentPath as NSString).appendingPathComponent("bin/tccplus")
        if FileManager.default.fileExists(atPath: binPath) {
            return binPath
        }
        
        // Check in common development locations
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let possiblePaths = [
            (homeDir as NSString).appendingPathComponent("WorkSpace/Code/TCC Manager/TCC Manager/bin/tccplus"),
            "/usr/local/bin/tccplus",
            "/opt/homebrew/bin/tccplus",
            (homeDir as NSString).appendingPathComponent("bin/tccplus"),
            (homeDir as NSString).appendingPathComponent("WorkSpace/Code/tcc-permissions-manager/bin/tccplus"),
            "/Users/\(NSUserName())/WorkSpace/Code/tcc-permissions-manager/bin/tccplus"
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        return nil
    }
}

enum TCCError: LocalizedError {
    case couldNotGetBundleId
    case tccplusNotFound
    case executionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .couldNotGetBundleId:
            return "Could not get bundle ID from app"
        case .tccplusNotFound:
            return "tccplus binary not found. Please ensure it's available in the app bundle or system PATH."
        case .executionFailed(let message):
            return "Failed to execute tccplus: \(message)"
        }
    }
}

