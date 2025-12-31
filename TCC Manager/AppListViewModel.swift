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
            print("✅ Loaded \(cachedApps.count) apps from cache (with permissions)")
            apps = cachedApps
            applySearchFilter()
            isLoading = false
            
            // Permissions are already loaded from cache, show them immediately
            // No need to query SQLite - use cached permissions for instant loading
            // User can click refresh button if they want to update from database
        } else {
            // No cache, load fresh
            print("📂 No cache found, loading from system...")
            await refreshAppsFromSystem()
        }
    }
    
    private func refreshAppsFromSystem() async {
        print("📱 Refresh: Discovering installed apps from system...")
        let appPaths = await appDiscovery.getInstalledApps()
        print("📱 Refresh: Found \(appPaths.count) installed apps")
        
        var loadedApps: [AppInfo] = []
        
        // Create AppInfo objects first (like Electron app - display apps first)
        // This handles new apps (added) and removed apps (not in new list)
        for path in appPaths {
            var appInfo = AppInfo(path: path)
            appInfo.bundleId = tccManager.getBundleId(for: path)
            appInfo.permissions = PermissionStatus(camera: false, microphone: false, isLoading: true)
            loadedApps.append(appInfo)
        }
        
        // Set apps array but keep isLoading = true so UI doesn't show yet
        apps = loadedApps
        
        // Load permissions from SQLite database for all apps
        // This queries the TCC database to get the latest permission status
        print("🔍 Refresh: Querying SQLite database for permissions...")
        await loadPermissionsForApps(appPaths)
        
        // Now show UI with all permissions loaded
        applySearchFilter()
        isLoading = false
        
        print("✅ Refresh: All apps and permissions updated in JSON cache")
    }
    
    private func loadPermissionsForApps(_ appPaths: [String]) async {
        // Query SQLite database for permissions (used when refreshing from system)
        await refreshPermissionsFromDatabase(appPaths)
    }
    
    private func refreshPermissionsFromDatabase(_ appPaths: [String]) async {
        // Query TCC database for latest permissions
        print("🔍 Refresh: Querying permissions for \(appPaths.count) apps...")
        
        // Collect all permissions first (don't update UI yet)
        var permissionsMap: [String: PermissionStatus] = [:]
        
        // Query all permissions in parallel
        await withTaskGroup(of: (String, PermissionStatus).self) { group in
            for appPath in appPaths {
                group.addTask {
                    let permissions = await self.tccManager.checkPermissions(for: appPath)
                    return (appPath, permissions)
                }
            }
            
            // Collect all results
            for await (appPath, permissions) in group {
                permissionsMap[appPath] = permissions
            }
        }
        
        // Now update all apps at once with their permissions
        // This ensures UI only shows once with all checkboxes already set
        await MainActor.run {
            for (index, _) in self.apps.enumerated() {
                let appPath = self.apps[index].path
                if let permissions = permissionsMap[appPath] {
                    self.apps[index].permissions = permissions
                }
            }
        }
        
        // Save updated apps with permissions to cache
        // This ensures JSON has the latest permissions for all apps
        print("💾 Refresh: Saving updated apps with permissions to JSON cache...")
        configManager.saveInstalledApps(apps)
        print("✅ Refresh: JSON cache updated with latest permissions")
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
        
        // Wait a bit longer for TCC database to fully update
        // macOS TCC database sometimes takes a moment to reflect changes
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        // Query SQLite database for latest permissions
        let updatedPermissions = await tccManager.checkPermissions(for: appPath)
        print("🔍 Refreshed permissions for \(appPath): camera=\(updatedPermissions.camera), microphone=\(updatedPermissions.microphone)")
        
        // Create a new AppInfo with updated permissions to trigger SwiftUI update
        var updatedApp = apps[index]
        updatedApp.permissions = updatedPermissions
        apps[index] = updatedApp
        applySearchFilter()
        
        // Update cache with new permissions
        configManager.saveInstalledApps(apps)
    }
    
    func reloadAllApps() async {
        isLoading = true
        errorMessage = nil
        
        // Preserve search filter if active
        let currentSearchText = searchText
        
        print("🔄 Refresh: Removing JSON cache and recreating from system...")
        
        // Simply delete JSON and recreate it from scratch
        configManager.clearCache()
        
        // Refresh apps from system (will recreate JSON with latest apps and permissions)
        await refreshAppsFromSystem()
        
        // Restore search filter
        if !currentSearchText.isEmpty {
            searchText = currentSearchText
            applySearchFilter()
        }
        
        print("✅ Refresh: Completed - JSON cache recreated with latest apps and permissions")
    }
    
    func toggleCameraPermission(for appPath: String, grant: Bool) async {
        guard let index = apps.firstIndex(where: { $0.path == appPath }) else { return }
        
        updatingPermissions.insert(appPath)
        errorMessage = nil
        
        do {
            print("🔄 Toggling camera permission: \(grant ? "grant" : "revoke") for \(appPath)")
            try await tccManager.toggleCameraPermission(for: appPath, grant: grant)
            
            // Wait a bit for TCC database to update
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms - give TCC database time to update
            
            // Refresh permissions with retries
            var retries = 5
            var success = false
            while retries > 0 && !success {
                await refreshPermissions(for: appPath)
                
                let currentPermission = apps[index].permissions.camera
                print("   Current camera permission: \(currentPermission), expected: \(grant)")
                if currentPermission == grant {
                    success = true
                    print("✅ Camera permission successfully \(grant ? "granted" : "revoked")")
                } else {
                    print("⏳ Waiting for permission to update... (retries left: \(retries - 1))")
                    // Wait longer between retries
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                retries -= 1
            }
            
            // Only reload if we really couldn't verify the change
            // But don't reload immediately - just show error
            if !success {
                print("⚠️ Could not verify camera permission change after retries")
                errorMessage = "Permission change may not have taken effect. Please refresh to verify."
            }
            
            updatingPermissions.remove(appPath)
            
            // Update cache after permission change (even if verification failed)
            configManager.saveInstalledApps(apps)
        } catch {
            updatingPermissions.remove(appPath)
            print("❌ Failed to toggle camera permission: \(error.localizedDescription)")
            // Refresh to show actual state
            await refreshPermissions(for: appPath)
            errorMessage = "Failed to \(grant ? "grant" : "revoke") camera permission: \(error.localizedDescription)"
        }
    }
    
    func toggleMicrophonePermission(for appPath: String, grant: Bool) async {
        guard let index = apps.firstIndex(where: { $0.path == appPath }) else { return }
        
        updatingPermissions.insert(appPath)
        errorMessage = nil
        
        do {
            print("🔄 Toggling microphone permission: \(grant ? "grant" : "revoke") for \(appPath)")
            try await tccManager.toggleMicrophonePermission(for: appPath, grant: grant)
            
            // Wait a bit for TCC database to update
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms - give TCC database time to update
            
            // Refresh permissions with retries
            var retries = 5
            var success = false
            while retries > 0 && !success {
                await refreshPermissions(for: appPath)
                
                let currentPermission = apps[index].permissions.microphone
                print("   Current microphone permission: \(currentPermission), expected: \(grant)")
                if currentPermission == grant {
                    success = true
                    print("✅ Microphone permission successfully \(grant ? "granted" : "revoked")")
                } else {
                    print("⏳ Waiting for permission to update... (retries left: \(retries - 1))")
                    // Wait longer between retries
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                retries -= 1
            }
            
            // Only reload if we really couldn't verify the change
            // But don't reload immediately - just show error
            if !success {
                print("⚠️ Could not verify microphone permission change after retries")
                errorMessage = "Permission change may not have taken effect. Please refresh to verify."
            }
            
            updatingPermissions.remove(appPath)
            
            // Update cache after permission change (even if verification failed)
            configManager.saveInstalledApps(apps)
        } catch {
            updatingPermissions.remove(appPath)
            print("❌ Failed to toggle microphone permission: \(error.localizedDescription)")
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

