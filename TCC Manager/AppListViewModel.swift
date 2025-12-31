//
//  AppListViewModel.swift
//  TCC Manager
//
//  Created by Krunal Dodiya on 31/12/25.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class AppListViewModel: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var filteredApps: [AppInfo] = []
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var updatingPermissions: Set<String> = []
    
    private let appDiscovery = AppDiscoveryService.shared
    private let tccManager = TCCManager.shared
    
    func loadApps() async {
        isLoading = true
        errorMessage = nil
        
        let appPaths = await appDiscovery.getInstalledApps()
        var loadedApps: [AppInfo] = []
        
        // Create AppInfo objects
        for path in appPaths {
            var appInfo = AppInfo(path: path)
            
            // Load bundle ID
            appInfo.bundleId = tccManager.getBundleId(for: path)
            
            // Load permissions
            appInfo.permissions = await tccManager.checkPermissions(for: path)
            
            loadedApps.append(appInfo)
        }
        
        apps = loadedApps
        applySearchFilter()
        isLoading = false
    }
    
    func applySearchFilter() {
        if searchText.isEmpty {
            filteredApps = apps
        } else {
            let searchLower = searchText.lowercased()
            filteredApps = apps.filter { app in
                app.name.lowercased().contains(searchLower) ||
                app.path.lowercased().contains(searchLower) ||
                (app.bundleId?.lowercased().contains(searchLower) ?? false)
            }
        }
    }
    
    func refreshPermissions(for appPath: String) async {
        guard let index = apps.firstIndex(where: { $0.path == appPath }) else { return }
        
        let updatedPermissions = await tccManager.checkPermissions(for: appPath)
        apps[index].permissions = updatedPermissions
        applySearchFilter()
    }
    
    func toggleCameraPermission(for appPath: String, grant: Bool) async {
        guard let index = apps.firstIndex(where: { $0.path == appPath }) else { return }
        
        updatingPermissions.insert(appPath)
        
        do {
            try await tccManager.toggleCameraPermission(for: appPath, grant: grant)
            
            // Wait a bit for TCC database to update
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            
            // Refresh permissions with retries
            var retries = 3
            while retries > 0 {
                await refreshPermissions(for: appPath)
                
                let currentPermission = apps[index].permissions.camera
                if currentPermission == grant {
                    break
                }
                
                try? await Task.sleep(nanoseconds: 200_000_000)
                retries -= 1
            }
            
            updatingPermissions.remove(appPath)
        } catch {
            updatingPermissions.remove(appPath)
            // Refresh to show actual state
            await refreshPermissions(for: appPath)
            errorMessage = "Failed to \(grant ? "grant" : "revoke") camera permission: \(error.localizedDescription)"
        }
    }
    
    func toggleMicrophonePermission(for appPath: String, grant: Bool) async {
        guard let index = apps.firstIndex(where: { $0.path == appPath }) else { return }
        
        updatingPermissions.insert(appPath)
        
        do {
            try await tccManager.toggleMicrophonePermission(for: appPath, grant: grant)
            
            // Wait a bit for TCC database to update
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            
            // Refresh permissions with retries
            var retries = 3
            while retries > 0 {
                await refreshPermissions(for: appPath)
                
                let currentPermission = apps[index].permissions.microphone
                if currentPermission == grant {
                    break
                }
                
                try? await Task.sleep(nanoseconds: 200_000_000)
                retries -= 1
            }
            
            updatingPermissions.remove(appPath)
        } catch {
            updatingPermissions.remove(appPath)
            // Refresh to show actual state
            await refreshPermissions(for: appPath)
            errorMessage = "Failed to \(grant ? "grant" : "revoke") microphone permission: \(error.localizedDescription)"
        }
    }
    
    func copyAppPath(_ path: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }
}

