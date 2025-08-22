// Project: NoesisNoema
// File: ModelSpec.swift
// Created by Copilot on 2024-12-22.
// Description: Model specification with auto-detected GGUF parameters for OOM-safe defaults.
// License: MIT License

import Foundation

/// Runtime parameters for OOM-safe model execution
struct RuntimeParams {
    /// Context size (tokens)
    let contextSize: Int32
    /// Batch size for processing
    let batchSize: Int32
    /// Number of GPU layers to offload (0 for CPU-only)
    let gpuLayers: Int32
    /// Number of threads for CPU processing
    let threads: Int32
    /// Memory pool size in MB
    let memoryPoolMB: Int
    /// Whether to use memory mapping
    let useMemoryMapping: Bool
    
    /// Create OOM-safe defaults based on available system memory and model size
    static func safeDefaults(modelSizeGB: Double, availableMemoryGB: Double) -> RuntimeParams {
        let memoryRatio = availableMemoryGB / max(1.0, modelSizeGB)
        
        // Conservative defaults for low memory scenarios
        let contextSize: Int32
        let batchSize: Int32
        let memoryPoolMB: Int
        
        if memoryRatio < 1.5 {
            // Very tight memory - minimum viable settings
            contextSize = 512
            batchSize = 32
            memoryPoolMB = 128
        } else if memoryRatio < 3.0 {
            // Limited memory - conservative settings
            contextSize = 1024
            batchSize = 64
            memoryPoolMB = 256
        } else if memoryRatio < 6.0 {
            // Adequate memory - balanced settings
            contextSize = 2048
            batchSize = 128
            memoryPoolMB = 512
        } else {
            // Abundant memory - optimal settings
            contextSize = 4096
            batchSize = 256
            memoryPoolMB = 1024
        }
        
        #if os(iOS)
        let threads = max(1, min(4, ProcessInfo.processInfo.processorCount))
        let gpuLayers: Int32 = 0 // Force CPU on iOS for stability
        #else
        let threads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        let gpuLayers: Int32 = memoryRatio > 2.0 ? 10 : 0
        #endif
        
        return RuntimeParams(
            contextSize: contextSize,
            batchSize: batchSize,
            gpuLayers: gpuLayers,
            threads: Int32(threads),
            memoryPoolMB: memoryPoolMB,
            useMemoryMapping: memoryRatio > 1.2
        )
    }
}

/// Model specification with auto-detected GGUF parameters
struct ModelSpec: Identifiable, Codable {
    let id: String
    let name: String
    let filePath: String
    let fileSize: UInt64
    
    // GGUF metadata
    let version: String
    let architecture: String
    let parameterCount: UInt64
    let contextLength: Int32
    let embeddingLength: Int32
    let vocabSize: Int32
    let quantization: String
    
    // Auto-calculated OOM-safe defaults
    let defaultRuntimeParams: RuntimeParams
    
    // Model capabilities
    let supportsChat: Bool
    let supportsInstruct: Bool
    let supportsCompletion: Bool
    
    init(
        id: String,
        name: String,
        filePath: String,
        fileSize: UInt64,
        version: String,
        architecture: String,
        parameterCount: UInt64,
        contextLength: Int32,
        embeddingLength: Int32,
        vocabSize: Int32,
        quantization: String,
        availableMemoryGB: Double
    ) {
        self.id = id
        self.name = name
        self.filePath = filePath
        self.fileSize = fileSize
        self.version = version
        self.architecture = architecture
        self.parameterCount = parameterCount
        self.contextLength = contextLength
        self.embeddingLength = embeddingLength
        self.vocabSize = vocabSize
        self.quantization = quantization
        
        // Calculate model size in GB
        let modelSizeGB = Double(fileSize) / (1024.0 * 1024.0 * 1024.0)
        self.defaultRuntimeParams = RuntimeParams.safeDefaults(
            modelSizeGB: modelSizeGB,
            availableMemoryGB: availableMemoryGB
        )
        
        // Detect capabilities based on model name/architecture
        let nameLower = name.lowercased()
        self.supportsChat = nameLower.contains("chat") || nameLower.contains("instruct") || 
                           nameLower.contains("jan") || nameLower.contains("qwen")
        self.supportsInstruct = nameLower.contains("instruct") || self.supportsChat
        self.supportsCompletion = true // All models support basic completion
    }
    
    /// Human-readable model size
    var sizeDescription: String {
        let sizeGB = Double(fileSize) / (1024.0 * 1024.0 * 1024.0)
        return String(format: "%.1f GB", sizeGB)
    }
    
    /// Human-readable parameter count
    var parameterDescription: String {
        let params = Double(parameterCount)
        if params >= 1e9 {
            return String(format: "%.1fB", params / 1e9)
        } else if params >= 1e6 {
            return String(format: "%.0fM", params / 1e6)
        } else {
            return String(format: "%.0fK", params / 1e3)
        }
    }
    
    /// Estimated memory usage in MB
    var estimatedMemoryUsageMB: Int {
        let modelMB = Int(fileSize / (1024 * 1024))
        let contextMB = Int(defaultRuntimeParams.contextSize * Int32(embeddingLength) * 4 / (1024 * 1024))
        return modelMB + contextMB + defaultRuntimeParams.memoryPoolMB
    }
}

// MARK: - RuntimeParams Codable conformance
extension RuntimeParams: Codable {
    enum CodingKeys: String, CodingKey {
        case contextSize, batchSize, gpuLayers, threads, memoryPoolMB, useMemoryMapping
    }
}