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
    private let configManager = ConfigManager.shared
    
    func loadApps() async {
        isLoading = true
        errorMessage = nil
        
        // Try to load from cache first (includes permissions)
        print("📂 Attempting to load from cache...")
        if let cachedApps = configManager.loadInstalledApps(), !cachedApps.isEmpty {
            print("✅ Loaded \(cachedApps.count) apps from cache")
            apps = cachedApps
            applySearchFilter()
            isLoading = false
            
            // Permissions are already loaded from cache, so we can show them immediately
            // Optionally refresh permissions in background to ensure they're up to date
            // (but don't block UI - show cached permissions first)
            Task {
                let appPaths = cachedApps.map { $0.path }
                await refreshPermissionsFromDatabase(appPaths)
            }
        } else {
            // No cache, load fresh
            print("📂 No cache found, loading from system...")
            await refreshAppsFromSystem()
        }
    }
    
    private func refreshAppsFromSystem() async {
        let appPaths = await appDiscovery.getInstalledApps()
        var loadedApps: [AppInfo] = []
        
        // Create AppInfo objects first (like Electron app - display apps first)
        for path in appPaths {
            var appInfo = AppInfo(path: path)
            appInfo.bundleId = tccManager.getBundleId(for: path)
            appInfo.permissions = PermissionStatus(camera: false, microphone: false, isLoading: true)
            loadedApps.append(appInfo)
        }
        
        apps = loadedApps
        applySearchFilter()
        isLoading = false
        
        // Save to cache (synchronous, like docker-desktop-lite)
        print("💾 Attempting to save \(loadedApps.count) apps to cache...")
        configManager.saveInstalledApps(loadedApps)
        print("💾 Save operation completed")
        
        // Load permissions asynchronously after displaying apps (matching Electron behavior)
        await loadPermissionsForApps(appPaths)
    }
    
    private func loadPermissionsForApps(_ appPaths: [String]) async {
        // Query SQLite database for permissions (used when refreshing from system)
        await refreshPermissionsFromDatabase(appPaths)
    }
    
    private func refreshPermissionsFromDatabase(_ appPaths: [String]) async {
        // Query TCC database for latest permissions
        await withTaskGroup(of: Void.self) { group in
            for appPath in appPaths {
                group.addTask {
                    let permissions = await self.tccManager.checkPermissions(for: appPath)
                    
                    // Update permissions in the main array
                    await MainActor.run {
                        if let index = self.apps.firstIndex(where: { $0.path == appPath }) {
                            // Create a new AppInfo with updated permissions to trigger SwiftUI update
                            var updatedApp = self.apps[index]
                            updatedApp.permissions = permissions
                            self.apps[index] = updatedApp
                            self.applySearchFilter()
                        }
                    }
                }
            }
        }
        
        // Save updated apps with permissions to cache
        configManager.saveInstalledApps(apps)
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
        
        // Query SQLite database for latest permissions
        let updatedPermissions = await tccManager.checkPermissions(for: appPath)
        // Create a new AppInfo with updated permissions to trigger SwiftUI update
        var updatedApp = apps[index]
        updatedApp.permissions = updatedPermissions
        apps[index] = updatedApp
        applySearchFilter()
        
        // Update cache with new permissions
        configManager.saveInstalledApps(apps)
    }
    
    func reloadAllApps() async {
        // Preserve search filter if active
        let currentSearchText = searchText
        
        // Refresh apps from system (this will query SQLite for permissions)
        await refreshAppsFromSystem()
        
        // Restore search filter
        if !currentSearchText.isEmpty {
            searchText = currentSearchText
            applySearchFilter()
        }
    }
    
    func toggleCameraPermission(for appPath: String, grant: Bool) async {
        guard let index = apps.firstIndex(where: { $0.path == appPath }) else { return }
        
        updatingPermissions.insert(appPath)
        
        do {
            try await tccManager.toggleCameraPermission(for: appPath, grant: grant)
            
            // Wait a bit for TCC database to update
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            
            // Refresh permissions with retries (matching Electron: 2 retries)
            var retries = 2
            var success = false
            while retries > 0 && !success {
                await refreshPermissions(for: appPath)
                
                let currentPermission = apps[index].permissions.camera
                if currentPermission == grant {
                    success = true
                } else {
                    // Wait a bit more and retry
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                retries -= 1
            }
            
            // If we still didn't get the right value, do a full reload as fallback
            if !success {
                await reloadAllApps()
            }
            
            updatingPermissions.remove(appPath)
            
            // Update cache after successful permission change
            configManager.saveInstalledApps(apps)
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
            
            // Refresh permissions with retries (matching Electron: 2 retries)
            var retries = 2
            var success = false
            while retries > 0 && !success {
                await refreshPermissions(for: appPath)
                
                let currentPermission = apps[index].permissions.microphone
                if currentPermission == grant {
                    success = true
                } else {
                    // Wait a bit more and retry
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                retries -= 1
            }
            
            // If we still didn't get the right value, do a full reload as fallback
            if !success {
                await reloadAllApps()
            }
            
            updatingPermissions.remove(appPath)
            
            // Update cache after successful permission change
            configManager.saveInstalledApps(apps)
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

