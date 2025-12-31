//
//  TCCManager.swift
//  TCC Manager
//
//  Created by Krunal Dodiya on 31/12/25.
//

import Foundation
import SQLite3

class TCCManager {
    static let shared = TCCManager()
    
    private let tccDbUser: URL
    private let tccDbSystem: URL
    
    private init() {
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
        guard let bundleId = getBundleId(for: appPath) else {
            return PermissionStatus()
        }
        
        // Run database queries on a background thread to avoid blocking
        return await Task.detached { [tccDbUser, tccDbSystem] in
            let camera = Self.checkPermission(service: "kTCCServiceCamera", bundleId: bundleId, tccDbUser: tccDbUser, tccDbSystem: tccDbSystem)
            let microphone = Self.checkPermission(service: "kTCCServiceMicrophone", bundleId: bundleId, tccDbUser: tccDbUser, tccDbSystem: tccDbSystem)
            return PermissionStatus(camera: camera, microphone: microphone, isLoading: false)
        }.value
    }
    
    nonisolated private static func checkPermission(service: String, bundleId: String, tccDbUser: URL, tccDbSystem: URL) -> Bool {
        // Check user database first (most common location)
        if FileManager.default.fileExists(atPath: tccDbUser.path) {
            if let result = queryTCCDatabase(at: tccDbUser, service: service, bundleId: bundleId) {
                return result == 2 // 2 means granted
            }
        }
        
        // Check system database as fallback
        if FileManager.default.fileExists(atPath: tccDbSystem.path) {
            if let result = queryTCCDatabase(at: tccDbSystem, service: service, bundleId: bundleId) {
                return result == 2 // 2 means granted
            }
        }
        
        return false
    }
    
    nonisolated private static func queryTCCDatabase(at url: URL, service: String, bundleId: String) -> Int? {
        var db: OpaquePointer?
        
        // Try to open database - this requires Full Disk Access
        let dbPath = url.path
        let openResult = sqlite3_open(dbPath, &db)
        guard openResult == SQLITE_OK else {
            // Database might be locked or inaccessible (needs Full Disk Access)
            return nil
        }
        
        defer {
            sqlite3_close(db)
        }
        
        let query = "SELECT auth_value FROM access WHERE service=? AND client=?;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        // Bind parameters - ensure strings are properly null-terminated
        // Using -1 for length means SQLite computes the length automatically
        // Using nil for destructor means SQLite won't free the string (Swift owns it)
        let serviceCString = service.cString(using: .utf8)
        let bundleIdCString = bundleId.cString(using: .utf8)
        
        guard let serviceCString = serviceCString,
              let bundleIdCString = bundleIdCString,
              sqlite3_bind_text(statement, 1, serviceCString, -1, nil) == SQLITE_OK,
              sqlite3_bind_text(statement, 2, bundleIdCString, -1, nil) == SQLITE_OK else {
            return nil
        }
        
        let stepResult = sqlite3_step(statement)
        if stepResult == SQLITE_ROW {
            let authValue = sqlite3_column_int(statement, 0)
            return Int(authValue)
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
        let command = "\(tccplusPath) \(action) \(service) \(bundleId)"
        print("🔧 TCCManager: Executing command: \(command)")
        print("   Binary path: \(tccplusPath)")
        print("   Arguments: [\(action), \(service), \(bundleId)]")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tccplusPath)
        process.arguments = [action, service, bundleId]
        
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

