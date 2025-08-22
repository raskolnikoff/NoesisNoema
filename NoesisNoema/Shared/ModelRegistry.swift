// Project: NoesisNoema
// File: ModelRegistry.swift
// Created by Copilot on 2024-12-22.
// Description: Model registry with auto-discovery and GGUF parameter extraction.
// License: MIT License

import Foundation

/// Model registry that manages ModelSpec instances with auto-discovery
class ModelRegistry: ObservableObject {
    @Published private(set) var registeredModels: [String: ModelSpec] = [:]
    @Published private(set) var lastScanError: String?
    
    private let modelSearchPaths: [String]
    private var modelFileWatcher: DispatchSourceFileSystemObject?
    
    init() {
        // Initialize search paths for models
        self.modelSearchPaths = ModelRegistry.getDefaultSearchPaths()
        
        // Load any previously registered models and scan for new ones
        loadRegisteredModels()
        Task {
            await scanForModels()
        }
    }
    
    deinit {
        modelFileWatcher?.cancel()
    }
    
    /// Get default search paths for model files
    static func getDefaultSearchPaths() -> [String] {
        var paths: [String] = []
        
        let fm = FileManager.default
        
        // Current working directory
        paths.append(fm.currentDirectoryPath)
        
        // Executable directory
        if let exePath = Bundle.main.executablePath {
            let exeDir = URL(fileURLWithPath: exePath).deletingLastPathComponent().path
            paths.append(exeDir)
        }
        
        // Bundle resources
        if let resourcePath = Bundle.main.resourcePath {
            paths.append(resourcePath)
            paths.append("\(resourcePath)/Models")
            paths.append("\(resourcePath)/Resources/Models")
        }
        
        // Documents directory
        if let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
            paths.append(documentsPath)
        }
        
        // User Downloads (convenience)
        if let homeDir = FileManager.default.homeDirectoryForCurrentUser.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let decodedHome = homeDir.removingPercentEncoding {
            paths.append("\(decodedHome)/Downloads")
        }
        
        // Conventional model directories
        paths.append("./Resources/Models")
        paths.append("./NoesisNoema/Resources/Models")
        paths.append("./models")
        
        return paths
    }
    
    /// Scan for GGUF model files in search paths
    @MainActor
    func scanForModels() async {
        lastScanError = nil
        var newModels: [String: ModelSpec] = [:]
        var scanErrors: [String] = []
        
        for searchPath in modelSearchPaths {
            do {
                let foundModels = try await scanDirectory(searchPath)
                for model in foundModels {
                    newModels[model.id] = model
                }
            } catch {
                scanErrors.append("Error scanning \(searchPath): \(error.localizedDescription)")
            }
        }
        
        // Update the published property
        self.registeredModels = newModels
        
        if !scanErrors.isEmpty {
            self.lastScanError = scanErrors.joined(separator: "\n")
        }
        
        // Save registry to disk
        saveRegisteredModels()
        
        print("ModelRegistry: Found \(newModels.count) models")
        for model in newModels.values.sorted(by: { $0.name < $1.name }) {
            print("  - \(model.name) (\(model.sizeDescription), \(model.parameterDescription) params)")
        }
    }
    
    /// Scan a specific directory for GGUF files
    private func scanDirectory(_ path: String) async throws -> [ModelSpec] {
        let fm = FileManager.default
        
        guard fm.fileExists(atPath: path) else {
            return []
        }
        
        var models: [ModelSpec] = []
        
        // Get directory contents
        let contents = try fm.contentsOfDirectory(atPath: path)
        let ggufFiles = contents.filter { $0.lowercased().hasSuffix(".gguf") }
        
        for fileName in ggufFiles {
            let fullPath = "\(path)/\(fileName)"
            
            do {
                let modelSpec = try GGUFReader.extractModelSpec(from: fullPath)
                models.append(modelSpec)
            } catch {
                print("Warning: Could not read GGUF file \(fullPath): \(error)")
            }
        }
        
        return models
    }
    
    /// Get model by ID
    func getModel(id: String) -> ModelSpec? {
        return registeredModels[id]
    }
    
    /// Get all models
    func getAllModels() -> [ModelSpec] {
        return Array(registeredModels.values).sorted { $0.name < $1.name }
    }
    
    /// Get models filtered by criteria
    func getModels(architecture: String? = nil, maxSizeGB: Double? = nil, supportsChat: Bool? = nil) -> [ModelSpec] {
        return getAllModels().filter { model in
            if let arch = architecture, model.architecture != arch {
                return false
            }
            
            if let maxSize = maxSizeGB {
                let modelSizeGB = Double(model.fileSize) / (1024.0 * 1024.0 * 1024.0)
                if modelSizeGB > maxSize {
                    return false
                }
            }
            
            if let needsChat = supportsChat, model.supportsChat != needsChat {
                return false
            }
            
            return true
        }
    }
    
    /// Register a model manually (for external files)
    func registerModel(_ modelSpec: ModelSpec) {
        registeredModels[modelSpec.id] = modelSpec
        saveRegisteredModels()
    }
    
    /// Unregister a model
    func unregisterModel(id: String) {
        registeredModels.removeValue(forKey: id)
        saveRegisteredModels()
    }
    
    /// Get model info formatted for CLI display
    func getModelInfo(id: String) -> String? {
        guard let model = getModel(id: id) else {
            return nil
        }
        
        var info = """
        Model Information:
        ==================
        ID: \(model.id)
        Name: \(model.name)
        Architecture: \(model.architecture)
        Parameters: \(model.parameterDescription)
        File Size: \(model.sizeDescription)
        Quantization: \(model.quantization)
        Context Length: \(model.contextLength)
        Embedding Length: \(model.embeddingLength)
        Vocab Size: \(model.vocabSize)
        File Path: \(model.filePath)
        
        Capabilities:
        - Chat: \(model.supportsChat ? "✓" : "✗")
        - Instruct: \(model.supportsInstruct ? "✓" : "✗")  
        - Completion: \(model.supportsCompletion ? "✓" : "✗")
        
        OOM-Safe Runtime Defaults:
        - Context Size: \(model.defaultRuntimeParams.contextSize) tokens
        - Batch Size: \(model.defaultRuntimeParams.batchSize)
        - GPU Layers: \(model.defaultRuntimeParams.gpuLayers)
        - CPU Threads: \(model.defaultRuntimeParams.threads)
        - Memory Pool: \(model.defaultRuntimeParams.memoryPoolMB) MB
        - Memory Mapping: \(model.defaultRuntimeParams.useMemoryMapping ? "Enabled" : "Disabled")
        - Estimated Memory Usage: \(model.estimatedMemoryUsageMB) MB
        """
        
        return info
    }
    
    // MARK: - Persistence
    
    private var registryURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("model_registry.json")
    }
    
    private func saveRegisteredModels() {
        do {
            let data = try JSONEncoder().encode(Array(registeredModels.values))
            try data.write(to: registryURL)
        } catch {
            print("Error saving model registry: \(error)")
        }
    }
    
    private func loadRegisteredModels() {
        do {
            let data = try Data(contentsOf: registryURL)
            let models = try JSONDecoder().decode([ModelSpec].self, from: data)
            
            // Convert to dictionary and filter out models that no longer exist
            var validModels: [String: ModelSpec] = [:]
            for model in models {
                if FileManager.default.fileExists(atPath: model.filePath) {
                    validModels[model.id] = model
                }
            }
            
            self.registeredModels = validModels
        } catch {
            // Registry file doesn't exist or is corrupted - start fresh
            self.registeredModels = [:]
        }
    }
    
    /// Singleton instance
    static let shared = ModelRegistry()
}