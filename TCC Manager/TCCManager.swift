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
        
        let camera = checkPermission(service: "kTCCServiceCamera", bundleId: bundleId)
        let microphone = checkPermission(service: "kTCCServiceMicrophone", bundleId: bundleId)
        
        return PermissionStatus(camera: camera, microphone: microphone, isLoading: false)
    }
    
    private func checkPermission(service: String, bundleId: String) -> Bool {
        // Check user database first
        if FileManager.default.fileExists(atPath: tccDbUser.path) {
            if let result = queryTCCDatabase(at: tccDbUser, service: service, bundleId: bundleId) {
                return result == 2 // 2 means granted
            }
        }
        
        // Check system database
        if FileManager.default.fileExists(atPath: tccDbSystem.path) {
            if let result = queryTCCDatabase(at: tccDbSystem, service: service, bundleId: bundleId) {
                return result == 2 // 2 means granted
            }
        }
        
        return false
    }
    
    private func queryTCCDatabase(at url: URL, service: String, bundleId: String) -> Int? {
        var db: OpaquePointer?
        
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
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
        
        sqlite3_bind_text(statement, 1, service, -1, nil)
        sqlite3_bind_text(statement, 2, bundleId, -1, nil)
        
        if sqlite3_step(statement) == SQLITE_ROW {
            return Int(sqlite3_column_int(statement, 0))
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
            throw TCCError.tccplusNotFound
        }
        
        let action = grant ? "add" : "reset"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tccplusPath)
        process.arguments = [action, service, bundleId]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw TCCError.executionFailed(errorMessage)
            }
        } catch {
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
        
        // Check in common locations (for development)
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let possiblePaths = [
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

