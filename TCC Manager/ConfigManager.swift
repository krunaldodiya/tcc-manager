//
//  ConfigManager.swift
//  TCC Manager
//
//  Created by Krunal Dodiya on 31/12/25.
//

import Foundation

class ConfigManager {
    static let shared = ConfigManager()
    
    private let configFileName = "installed_apps.json"
    
    // Use Application Support directory (same approach as docker-desktop-lite)
    private var configURL: URL {
        let fileManager = FileManager.default
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupportDir.appendingPathComponent("TCC Manager", isDirectory: true)
        
        // Create directory if it doesn't exist (synchronously, like docker-desktop-lite)
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true, attributes: nil)
        
        return appDir.appendingPathComponent(configFileName)
    }
    
    private init() {}
    
    // MARK: - Get Config Path (for debugging/verification)
    
    func getConfigPath() -> String {
        return configURL.deletingLastPathComponent().path
    }
    
    func getInstalledAppsFilePath() -> String {
        return configURL.path
    }
    
    // MARK: - Save Installed Apps (synchronous, like docker-desktop-lite)
    
    func saveInstalledApps(_ apps: [AppInfo]) {
        print("💾 ConfigManager.saveInstalledApps called with \(apps.count) apps")
        
        // Guard against empty array
        guard !apps.isEmpty else {
            print("   ⚠️ Warning: Attempted to save empty apps array, skipping save")
            return
        }
        
        print("   Config file path: \(configURL.path)")
        
        // Ensure directory exists
        let fileManager = FileManager.default
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupportDir.appendingPathComponent("TCC Manager", isDirectory: true)
        
        do {
            try fileManager.createDirectory(at: appDir, withIntermediateDirectories: true, attributes: nil)
            print("   ✅ Directory created/verified: \(appDir.path)")
        } catch {
            print("   ❌ Failed to create directory: \(error.localizedDescription)")
            return
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let data = try encoder.encode(apps)
            print("   ✅ Encoded \(data.count) bytes of JSON data")
            
            // Write with atomic option (like docker-desktop-lite)
            try data.write(to: configURL, options: .atomic)
            print("✅ Successfully saved \(apps.count) apps to: \(configURL.path)")
            
            // Verify file was created
            if fileManager.fileExists(atPath: configURL.path) {
                if let attributes = try? fileManager.attributesOfItem(atPath: configURL.path),
                   let fileSize = attributes[.size] as? Int {
                    print("   ✅ File verified: \(fileSize) bytes")
                } else {
                    print("   ✅ File verified: exists")
                }
            } else {
                print("   ⚠️ WARNING: File was not created at \(configURL.path)!")
            }
        } catch let encodingError as EncodingError {
            print("❌ Failed to encode apps to JSON: \(encodingError)")
            if case .invalidValue(let value, let context) = encodingError {
                print("   Invalid value: \(value)")
                print("   Context: \(context)")
            }
        } catch {
            print("❌ Failed to save installed apps: \(error.localizedDescription)")
            print("   Error type: \(type(of: error))")
            print("   Full error: \(error)")
        }
    }
    
    // MARK: - Load Installed Apps (synchronous, like docker-desktop-lite)
    
    func loadInstalledApps() -> [AppInfo]? {
        guard let data = try? Data(contentsOf: configURL),
              let apps = try? JSONDecoder().decode([AppInfo].self, from: data) else {
            // Return nil if file doesn't exist or can't be decoded
            return nil
        }
        return apps
    }
    
    // MARK: - Clear Cache
    
    func clearCache() {
        try? FileManager.default.removeItem(at: configURL)
    }
}

