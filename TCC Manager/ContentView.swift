//
//  ContentView.swift
//  TCC Manager
//
//  Created by Krunal Dodiya on 31/12/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppListViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Main content
            if viewModel.isLoading {
                loadingView
            } else if let errorMessage = viewModel.errorMessage {
                errorView(message: errorMessage)
            } else {
                appListView
            }
        }
        .frame(minWidth: 900, minHeight: 700)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color(red: 0.4, green: 0.49, blue: 0.92), Color(red: 0.46, green: 0.29, blue: 0.64)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .task {
            await viewModel.loadApps()
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 8) {
            Text("🎤📷 macOS TCC Plus")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.white)
            
            Text("Manage microphone and camera access for installed applications")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.top, 40)
        .padding(.bottom, 20)
    }
    
    private var loadingView: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading applications...")
                .font(.system(size: 16))
                .foregroundColor(.white)
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(message: String) -> some View {
        VStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.white)
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .padding()
                .background(Color.red.opacity(0.2))
                .cornerRadius(8)
                .padding()
            
            Button("Retry") {
                Task {
                    await viewModel.loadApps()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var appListView: some View {
        VStack(spacing: 0) {
            // Search and count
            HStack {
                Text("\(viewModel.filteredApps.count) application\(viewModel.filteredApps.count != 1 ? "s" : "")")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button("Refresh") {
                    Task {
                        await viewModel.reloadAllApps()
                    }
                }
                .buttonStyle(.bordered)
                
                TextField("Search applications...", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
                    .onChange(of: viewModel.searchText) { oldValue, newValue in
                        viewModel.applySearchFilter()
                    }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // App list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.filteredApps) { app in
                        AppRowView(
                            app: app,
                            viewModel: viewModel
                        )
                    }
                }
                .padding()
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
        )
        .padding(20)
    }
}

struct AppRowView: View {
    let app: AppInfo
    @ObservedObject var viewModel: AppListViewModel
    @State private var showCameraConfirmation = false
    @State private var showMicrophoneConfirmation = false
    @State private var pendingCameraGrant: Bool?
    @State private var pendingMicrophoneGrant: Bool?
    @State private var isCopied = false
    
    // Get current app from viewModel to ensure we have latest permissions
    // This ensures the view updates when permissions are loaded
    private var currentApp: AppInfo {
        viewModel.filteredApps.first(where: { $0.path == app.path }) ?? app
    }
    
    var isUpdating: Bool {
        viewModel.updatingPermissions.contains(app.path)
    }
    
    var body: some View {
        mainContent
            .background(backgroundView)
            .alert("Confirm Microphone Permission", isPresented: $showMicrophoneConfirmation) {
                microphoneAlertButtons
            } message: {
                microphoneAlertMessage
            }
            .alert("Confirm Camera Permission", isPresented: $showCameraConfirmation) {
                cameraAlertButtons
            } message: {
                cameraAlertMessage
            }
    }
    
    private var mainContent: some View {
        HStack(alignment: .center, spacing: 15) {
            appInfoView
            permissionsView
        }
        .padding(12)
    }
    
    private var appInfoView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(app.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
                
                if let bundleId = app.bundleId {
                    Text("— \(bundleId)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            
            Text(app.path)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(isCopied ? Color.green.opacity(0.3) : Color.clear)
        .animation(.easeOut(duration: 0.5), value: isCopied)
        .onTapGesture {
            viewModel.copyAppPath(app.path)
            // Visual feedback (green background flash)
            isCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isCopied = false
            }
        }
    }
    
    private var permissionsView: some View {
        HStack(spacing: 20) {
            microphoneToggle
            cameraToggle
        }
    }
    
    private var microphoneToggle: some View {
        VStack(spacing: 5) {
            Text("🎤 MICROPHONE")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            Toggle("", isOn: microphoneBinding)
                .toggleStyle(.checkbox)
                .disabled(isUpdating || currentApp.permissions.isLoading)
        }
    }
    
    private var cameraToggle: some View {
        VStack(spacing: 5) {
            Text("📷 CAMERA")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            Toggle("", isOn: cameraBinding)
                .toggleStyle(.checkbox)
                .disabled(isUpdating || currentApp.permissions.isLoading)
        }
    }
    
    private var microphoneBinding: Binding<Bool> {
        Binding(
            get: { currentApp.permissions.microphone },
            set: { newValue in
                pendingMicrophoneGrant = newValue
                showMicrophoneConfirmation = true
            }
        )
    }
    
    private var cameraBinding: Binding<Bool> {
        Binding(
            get: { currentApp.permissions.camera },
            set: { newValue in
                pendingCameraGrant = newValue
                showCameraConfirmation = true
            }
        )
    }
    
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(NSColor.controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    .padding(.leading, -3)
            )
    }
    
    @ViewBuilder
    private var microphoneAlertButtons: some View {
        Button("Cancel", role: .cancel) {
            pendingMicrophoneGrant = nil
        }
        Button(buttonTitle(for: pendingMicrophoneGrant)) {
            handleMicrophonePermissionChange()
        }
    }
    
    @ViewBuilder
    private var microphoneAlertMessage: some View {
        if let grant = pendingMicrophoneGrant {
            Text(alertMessage(for: .microphone, grant: grant))
        }
    }
    
    @ViewBuilder
    private var cameraAlertButtons: some View {
        Button("Cancel", role: .cancel) {
            pendingCameraGrant = nil
        }
        Button(buttonTitle(for: pendingCameraGrant)) {
            handleCameraPermissionChange()
        }
    }
    
    @ViewBuilder
    private var cameraAlertMessage: some View {
        if let grant = pendingCameraGrant {
            Text(alertMessage(for: .camera, grant: grant))
        }
    }
    
    private func buttonTitle(for grant: Bool?) -> String {
        grant == true ? "Grant" : "Revoke"
    }
    
    private func alertMessage(for permission: PermissionType, grant: Bool) -> String {
        let permissionName = permission == .microphone ? "microphone" : "camera"
        if grant {
            return "Are you sure you want to grant \(permissionName) access to \"\(app.name)\"?\n\nThis will allow the app to access your \(permissionName)."
        } else {
            return "Are you sure you want to revoke \(permissionName) access from \"\(app.name)\"?\n\nThis will remove the permission and the app will need to request access again."
        }
    }
    
    private func handleMicrophonePermissionChange() {
        if let grant = pendingMicrophoneGrant {
            Task {
                await viewModel.toggleMicrophonePermission(for: app.path, grant: grant)
            }
        }
        pendingMicrophoneGrant = nil
    }
    
    private func handleCameraPermissionChange() {
        if let grant = pendingCameraGrant {
            Task {
                await viewModel.toggleCameraPermission(for: app.path, grant: grant)
            }
        }
        pendingCameraGrant = nil
    }
    
    private enum PermissionType {
        case microphone
        case camera
    }
}

#Preview {
    ContentView()
}
