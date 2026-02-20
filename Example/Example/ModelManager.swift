//
//  ModelManager.swift
//  Example
//

import Foundation
import ZIPFoundation

class ModelManager: ObservableObject {
    static let shared = ModelManager()
    
    private let modelURL = "https://firebasestorage.googleapis.com/v0/b/my-project-1494707780868.firebasestorage.app/o/fastpitch_hifigan.zip?alt=media&token=d239c2de-fe93-460e-a1e4-044923a1be58"
    private let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private let fileManager = FileManager.default

    private var downloadedModelsDirectory: URL {
        documentsDirectory.appendingPathComponent("TTSModels")
    }
    
    var modelsDirectory: URL {
        bundledModelsDirectory ?? downloadedModelsDirectory
    }
    
    private var zipFileURL: URL {
        documentsDirectory.appendingPathComponent("fastpitch_hifigan.zip")
    }

    private var bundledModelsDirectory: URL? {
        guard let bundleDirectory = Bundle.main.resourceURL else {
            return nil
        }

        let hasFastPitch = modelExists(named: "FastPitch", in: bundleDirectory)
        let hasHiFiGan = modelExists(named: "HiFiGan", in: bundleDirectory)
        let hasTokens = fileManager.fileExists(atPath: bundleDirectory.appendingPathComponent("tokens.txt").path)
        let hasDictionary = fileManager.fileExists(atPath: bundleDirectory.appendingPathComponent("cmudict.json").path)

        guard hasFastPitch, hasHiFiGan, hasTokens, hasDictionary else {
            return nil
        }

        return bundleDirectory
    }
    
    var isModelDownloaded: Bool {
        let fastPitchExists = modelExists(named: "FastPitch", in: modelsDirectory)
        let hifiGanExists = modelExists(named: "HiFiGan", in: modelsDirectory)
        let tokensExists = fileManager.fileExists(atPath: modelsDirectory.appendingPathComponent("tokens.txt").path)
        let dictExists = fileManager.fileExists(atPath: modelsDirectory.appendingPathComponent("cmudict.json").path)
        
        return fastPitchExists && hifiGanExists && tokensExists && dictExists
    }
    
    func downloadModels(progressHandler: @escaping (Double) -> Void) async throws {
        if bundledModelsDirectory != nil {
            await MainActor.run {
                progressHandler(1.0)
            }
            return
        }

        guard !isModelDownloaded else { return }
        
        let session = URLSession.shared
        let (asyncBytes, response) = try await session.bytes(from: URL(string: modelURL)!)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NSError(domain: "ModelManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to download models"])
        }
        
        let totalBytes = httpResponse.expectedContentLength
        var downloadedBytes: Int64 = 0
        var data = Data()
        
        for try await byte in asyncBytes {
            data.append(byte)
            downloadedBytes += 1
            
            if downloadedBytes % 10000 == 0 {
                let progress = Double(downloadedBytes) / Double(totalBytes)
                await MainActor.run {
                    progressHandler(progress)
                }
            }
        }
        
        await MainActor.run {
            progressHandler(1.0)
        }
        
        try data.write(to: zipFileURL)
        
        try await extractModels()
        
        try? FileManager.default.removeItem(at: zipFileURL)
    }
    
    private func extractModels() async throws {
        guard fileManager.fileExists(atPath: zipFileURL.path) else {
            throw NSError(domain: "ModelManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "ZIP file not found"])
        }
        
        try fileManager.createDirectory(at: downloadedModelsDirectory, withIntermediateDirectories: true)
        
        try fileManager.unzipItem(at: zipFileURL, to: downloadedModelsDirectory)
        
        // Remove __MACOSX folder if exists
        let macosxFolder = downloadedModelsDirectory.appendingPathComponent("__MACOSX")
        try? fileManager.removeItem(at: macosxFolder)
        
        // Find the fastpitch_hifigan folder and move its contents to the root
        let fastpitchFolder = downloadedModelsDirectory.appendingPathComponent("fastpitch_hifigan")
        if fileManager.fileExists(atPath: fastpitchFolder.path) {
            let contents = try fileManager.contentsOfDirectory(at: fastpitchFolder, includingPropertiesForKeys: nil)
            
            for item in contents {
                let destinationURL = downloadedModelsDirectory.appendingPathComponent(item.lastPathComponent)
                try? fileManager.removeItem(at: destinationURL)
                try fileManager.moveItem(at: item, to: destinationURL)
            }
            
            try? fileManager.removeItem(at: fastpitchFolder)
        }
    }
    
    func clearModels() throws {
        if fileManager.fileExists(atPath: downloadedModelsDirectory.path) {
            try fileManager.removeItem(at: downloadedModelsDirectory)
        }
        if fileManager.fileExists(atPath: zipFileURL.path) {
            try fileManager.removeItem(at: zipFileURL)
        }
    }

    private func modelExists(named modelName: String, in directory: URL) -> Bool {
        let compiledPath = directory.appendingPathComponent("\(modelName).mlmodelc").path
        if fileManager.fileExists(atPath: compiledPath) {
            return true
        }

        let packagePath = directory.appendingPathComponent("\(modelName).mlpackage").path
        return fileManager.fileExists(atPath: packagePath)
    }
}
