//
//  SourceManager.swift
//  Aidoku
//
//  Created by Skitty on 1/10/22.
//

import Foundation
import ZIPFoundation

class SourceManager {
    
    static let shared = SourceManager()
    
    static let directory = FileManager.default.documentDirectory.appendingPathComponent("Sources", isDirectory: true)
    
    var sources: [Source] {
        Self.directory.contents.compactMap { try? Source(from: $0) }
    }
    
    func source(for id: String) -> Source? {
        sources.first { $0.info.id == id }
    }
    
    func hasSourceInstalled(id: String) -> Bool {
        sources.firstIndex { $0.info.id == id } != nil
    }
    
    func importSource(from url: URL) async -> Source? {
        Self.directory.createDirctory()
        
        var fileUrl = url
    
        if let temporaryDirectory = FileManager.default.temporaryDirectory {
            if fileUrl.scheme != "file" {
                do {
                    let location = try await URLSession.shared.download(for: URLRequest.from(url))
                    fileUrl = location
                } catch {
                    return nil
                }
            }
            try? FileManager.default.unzipItem(at: fileUrl, to: temporaryDirectory)
            try? FileManager.default.removeItem(at: fileUrl)

            let payload = temporaryDirectory.appendingPathComponent("Payload")
            let source = try? Source(from: payload)
            if let source = source {
                let destination = Self.directory.appendingPathComponent(source.info.id)
                if destination.exists {
                    try? FileManager.default.removeItem(at: destination)
                }
                try? FileManager.default.moveItem(at: payload, to: destination)
                try? FileManager.default.removeItem(at: temporaryDirectory)
                
                NotificationCenter.default.post(name: Notification.Name("updateSourceList"), object: nil)
                
                source.url = destination
                return source
            }
        }
        
        return nil
    }
    
    func importExternalSource(from url: URL) -> Source? {
        Self.directory.createDirctory()

        if let temporaryDirectory = FileManager.default.temporaryDirectory?.appendingPathComponent(UUID().uuidString) {
            try? FileManager.default.unzipItem(at: url, to: temporaryDirectory)
            try? FileManager.default.removeItem(at: url)

            let payload = temporaryDirectory.appendingPathComponent("Payload")
            let source = try? Source(from: payload)
            if let source = source {
                let destination = Self.directory.appendingPathComponent(source.info.id)
                if destination.exists {
                    try? FileManager.default.removeItem(at: destination)
                }
                try? FileManager.default.moveItem(at: payload, to: destination)
                try? FileManager.default.removeItem(at: temporaryDirectory)
                
                NotificationCenter.default.post(name: Notification.Name("updateSourceList"), object: nil)
                
                source.url = destination
                return source
            }
        }
        
        return nil
    }
    
    func clearSources() {
        for source in sources {
            try? FileManager.default.removeItem(at: source.url)
        }
        NotificationCenter.default.post(name: Notification.Name("updateSourceList"), object: nil)
    }
    
    func remove(source: Source) {
        try? FileManager.default.removeItem(at: source.url)
        NotificationCenter.default.post(name: Notification.Name("updateSourceList"), object: nil)
    }
}