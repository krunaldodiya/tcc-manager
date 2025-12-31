//
//  Models.swift
//  TCC Manager
//
//  Created by Krunal Dodiya on 31/12/25.
//

import Foundation

struct AppInfo: Identifiable, Hashable, Codable {
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
    
    // Memberwise initializer for creating AppInfo with all properties
    init(id: String, path: String, name: String, bundleId: String?, permissions: PermissionStatus) {
        self.id = id
        self.path = path
        self.name = name
        self.bundleId = bundleId
        self.permissions = permissions
    }
    
    // Custom Codable implementation to ensure proper encoding/decoding
    enum CodingKeys: String, CodingKey {
        case id, path, name, bundleId, permissions
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        name = try container.decode(String.self, forKey: .name)
        bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId)
        permissions = try container.decode(PermissionStatus.self, forKey: .permissions)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(path, forKey: .path)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(bundleId, forKey: .bundleId)
        try container.encode(permissions, forKey: .permissions)
    }
}

struct PermissionStatus: Hashable, Codable {
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

