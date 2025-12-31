//
//  Models.swift
//  TCC Manager
//
//  Created by Krunal Dodiya on 31/12/25.
//

import Foundation

struct AppInfo: Identifiable, Hashable {
    let id: String
    let path: String
    let name: String
    var bundleId: String?
    var permissions: PermissionStatus
    
    init(path: String) {
        self.id = path
        self.path = path
        self.name = (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
        self.bundleId = nil
        self.permissions = PermissionStatus()
    }
}

struct PermissionStatus: Hashable {
    var camera: Bool = false
    var microphone: Bool = false
    var isLoading: Bool = false
    
    mutating func update(camera: Bool? = nil, microphone: Bool? = nil) {
        if let camera = camera {
            self.camera = camera
        }
        if let microphone = microphone {
            self.microphone = microphone
        }
    }
}

