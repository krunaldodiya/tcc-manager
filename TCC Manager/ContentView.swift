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
                
                TextField("Search applications...", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
                    .onChange(of: viewModel.searchText) {
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
    
    var isUpdating: Bool {
        viewModel.updatingPermissions.contains(app.path)
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 15) {
            // App info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(app.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                    
                    if let bundleId = app.bundleId {
                        Text("— \(bundleId)")
                            .font(.system(size: 12, family: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                
                Text(app.path)
                    .font(.system(size: 13, family: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.copyAppPath(app.path)
            }
            
            // Permissions
            HStack(spacing: 20) {
                // Microphone
                VStack(spacing: 5) {
                    Text("🎤 MICROPHONE")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Toggle("", isOn: Binding(
                        get: { app.permissions.microphone },
                        set: { newValue in
                            pendingMicrophoneGrant = newValue
                            showMicrophoneConfirmation = true
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .disabled(isUpdating || app.permissions.isLoading)
                }
                
                // Camera
                VStack(spacing: 5) {
                    Text("📷 CAMERA")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Toggle("", isOn: Binding(
                        get: { app.permissions.camera },
                        set: { newValue in
                            pendingCameraGrant = newValue
                            showCameraConfirmation = true
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .disabled(isUpdating || app.permissions.isLoading)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        .padding(.leading, -3)
                )
        )
        .alert("Confirm Microphone Permission", isPresented: $showMicrophoneConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingMicrophoneGrant = nil
            }
            Button(pendingMicrophoneGrant == true ? "Grant" : "Revoke") {
                if let grant = pendingMicrophoneGrant {
                    Task {
                        await viewModel.toggleMicrophonePermission(for: app.path, grant: grant)
                    }
                }
                pendingMicrophoneGrant = nil
            }
        } message: {
            if let grant = pendingMicrophoneGrant {
                let message = grant
                    ? "Are you sure you want to grant microphone access to \"\(app.name)\"?\n\nThis will allow the app to access your microphone."
                    : "Are you sure you want to revoke microphone access from \"\(app.name)\"?\n\nThis will remove the permission and the app will need to request access again."
                Text(message)
            }
        }
        .alert("Confirm Camera Permission", isPresented: $showCameraConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingCameraGrant = nil
            }
            Button(pendingCameraGrant == true ? "Grant" : "Revoke") {
                if let grant = pendingCameraGrant {
                    Task {
                        await viewModel.toggleCameraPermission(for: app.path, grant: grant)
                    }
                }
                pendingCameraGrant = nil
            }
        } message: {
            if let grant = pendingCameraGrant {
                let message = grant
                    ? "Are you sure you want to grant camera access to \"\(app.name)\"?\n\nThis will allow the app to access your camera."
                    : "Are you sure you want to revoke camera access from \"\(app.name)\"?\n\nThis will remove the permission and the app will need to request access again."
                Text(message)
            }
        }
    }
}

#Preview {
    ContentView()
}
