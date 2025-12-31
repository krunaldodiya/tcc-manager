//
//  AppDiscoveryService.swift
//  TCC Manager
//
//  Created by Krunal Dodiya on 31/12/25.
//

import Foundation

class AppDiscoveryService {
    nonisolated static let shared = AppDiscoveryService()
    
    nonisolated private init() {}
    
    func getInstalledApps() async -> [String] {
        var apps: Set<String> = []
        
        // Try mdfind first (preferred method)
        if findCommandPath("mdfind") != nil {
            // Search in ~/Applications
            if let homeApps = executeMDFind(in: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")) {
                apps.formUnion(homeApps)
            }
            
            // Search in /Applications (excluding system apps)
            if let systemApps = executeMDFindSystem() {
                apps.formUnion(systemApps)
            }
        }
        
        // Fallback to find command
        if apps.isEmpty {
            // Search ~/Applications
            if let homeApps = findApps(in: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"), maxDepth: 3) {
                apps.formUnion(homeApps)
            }
            
            // Search /Applications
            if let systemApps = findApps(in: URL(fileURLWithPath: "/Applications"), maxDepth: 1) {
                apps.formUnion(systemApps)
            }
        }
        
        return Array(apps).sorted()
    }
    
    private func executeMDFind(in directory: URL) -> [String]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = [
            "-onlyin", directory.path,
            "kMDItemContentType == 'com.apple.application-bundle'"
        ]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            return output.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } catch {
            return nil
        }
    }
    
    private func executeMDFindSystem() -> [String]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = [
            "-onlyin", "/Applications",
            "kMDItemContentType == 'com.apple.application-bundle' && kMDItemSystemContent != 1"
        ]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            return output.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } catch {
            return nil
        }
    }
    
    private func findApps(in directory: URL, maxDepth: Int) -> [String]? {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return nil
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/find")
        process.arguments = [
            directory.path,
            "-name", "*.app",
            "-type", "d",
            "-maxdepth", "\(maxDepth)"
        ]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            return output.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } catch {
            return nil
        }
    }
    
    private func findCommandPath(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return path?.isEmpty == false ? path : nil
        } catch {
            return nil
        }
    }
}

