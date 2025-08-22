// Project: NoesisNoema
// File: GGUFReader.swift  
// Created by Copilot on 2024-12-22.
// Description: GGUF file reader for extracting model metadata and parameters.
// License: MIT License

import Foundation
import llama

/// Errors that can occur during GGUF reading
enum GGUFReaderError: Error {
    case fileNotFound(String)
    case invalidFormat(String)
    case readError(String)
    case unsupportedVersion(UInt32)
    case keyNotFound(String)
}

/// Reader for GGUF (GGML Universal Format) files to extract model metadata
class GGUFReader {
    
    /// Extract model specifications from a GGUF file
    static func extractModelSpec(from filePath: String) throws -> ModelSpec {
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw GGUFReaderError.fileNotFound("File not found: \(filePath)")
        }
        
        // Get file size
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: filePath)
        let fileSize = fileAttributes[.size] as? UInt64 ?? 0
        
        // Initialize GGUF context
        var initParams = gguf_init_params()
        initParams.no_alloc = true  // Don't allocate tensor data, just read metadata
        initParams.ctx = nil
        
        guard let ggufCtx = gguf_init_from_file(filePath, initParams) else {
            throw GGUFReaderError.invalidFormat("Could not initialize GGUF context for: \(filePath)")
        }
        defer {
            gguf_free(ggufCtx)
        }
        
        // Extract basic file info
        let version = gguf_get_version(ggufCtx)
        guard version == UInt32(GGUF_VERSION) else {
            throw GGUFReaderError.unsupportedVersion(version)
        }
        
        // Get available memory for OOM-safe calculations
        let availableMemoryGB = getAvailableMemoryGB()
        
        // Extract metadata
        let fileName = URL(fileURLWithPath: filePath).lastPathComponent
        let modelId = fileName.replacingOccurrences(of: ".gguf", with: "")
        
        let architecture = try readStringValue(from: ggufCtx, key: "general.architecture") ?? "unknown"
        let name = try readStringValue(from: ggufCtx, key: "general.name") ?? modelId
        let parameterCount = try readUInt64Value(from: ggufCtx, key: "\(architecture).block_count") ?? 0
        let contextLength = try readInt32Value(from: ggufCtx, key: "\(architecture).context_length") ?? 2048
        let embeddingLength = try readInt32Value(from: ggufCtx, key: "\(architecture).embedding_length") ?? 4096
        let vocabSize = try readInt32Value(from: ggufCtx, key: "tokenizer.ggml.tokens.count") ?? 32000
        
        // Try to determine quantization from filename or metadata
        var quantization = "unknown"
        if fileName.contains("Q4_K_M") {
            quantization = "Q4_K_M"
        } else if fileName.contains("Q4_0") {
            quantization = "Q4_0"
        } else if fileName.contains("Q8_0") {
            quantization = "Q8_0"
        } else if fileName.contains("Q5_K_M") {
            quantization = "Q5_K_M"
        } else if fileName.contains("F16") || fileName.contains("f16") {
            quantization = "F16"
        } else if fileName.contains("F32") || fileName.contains("f32") {
            quantization = "F32"
        }
        
        // If we have parameter count, calculate more accurately
        let estimatedParams: UInt64
        if parameterCount > 0 {
            estimatedParams = parameterCount
        } else {
            // Estimate based on file size and quantization
            estimatedParams = estimateParameterCount(fileSize: fileSize, quantization: quantization)
        }
        
        return ModelSpec(
            id: modelId,
            name: name,
            filePath: filePath,
            fileSize: fileSize,
            version: String(version),
            architecture: architecture,
            parameterCount: estimatedParams,
            contextLength: contextLength,
            embeddingLength: embeddingLength,
            vocabSize: vocabSize,
            quantization: quantization,
            availableMemoryGB: availableMemoryGB
        )
    }
    
    /// Read string value from GGUF context
    private static func readStringValue(from ctx: OpaquePointer, key: String) throws -> String? {
        let keyCount = gguf_get_n_kv(ctx)
        
        for i in 0..<keyCount {
            if let keyPtr = gguf_get_key(ctx, i),
               let keyStr = String(validatingUTF8: keyPtr),
               keyStr == key {
                
                let valueType = gguf_get_kv_type(ctx, i)
                if valueType == GGUF_TYPE_STRING,
                   let valuePtr = gguf_get_val_str(ctx, i) {
                    return String(cString: valuePtr)
                }
            }
        }
        return nil
    }
    
    /// Read UInt64 value from GGUF context
    private static func readUInt64Value(from ctx: OpaquePointer, key: String) throws -> UInt64? {
        let keyCount = gguf_get_n_kv(ctx)
        
        for i in 0..<keyCount {
            if let keyPtr = gguf_get_key(ctx, i),
               let keyStr = String(validatingUTF8: keyPtr),
               keyStr == key {
                
                let valueType = gguf_get_kv_type(ctx, i)
                if valueType == GGUF_TYPE_UINT64 {
                    return gguf_get_val_u64(ctx, i)
                } else if valueType == GGUF_TYPE_INT64 {
                    let val = gguf_get_val_i64(ctx, i)
                    return val >= 0 ? UInt64(val) : 0
                } else if valueType == GGUF_TYPE_UINT32 {
                    return UInt64(gguf_get_val_u32(ctx, i))
                } else if valueType == GGUF_TYPE_INT32 {
                    let val = gguf_get_val_i32(ctx, i)
                    return val >= 0 ? UInt64(val) : 0
                }
            }
        }
        return nil
    }
    
    /// Read Int32 value from GGUF context
    private static func readInt32Value(from ctx: OpaquePointer, key: String) throws -> Int32? {
        let keyCount = gguf_get_n_kv(ctx)
        
        for i in 0..<keyCount {
            if let keyPtr = gguf_get_key(ctx, i),
               let keyStr = String(validatingUTF8: keyPtr),
               keyStr == key {
                
                let valueType = gguf_get_kv_type(ctx, i)
                if valueType == GGUF_TYPE_INT32 {
                    return gguf_get_val_i32(ctx, i)
                } else if valueType == GGUF_TYPE_UINT32 {
                    return Int32(gguf_get_val_u32(ctx, i))
                } else if valueType == GGUF_TYPE_INT64 {
                    let val = gguf_get_val_i64(ctx, i)
                    return Int32(clamping: val)
                } else if valueType == GGUF_TYPE_UINT64 {
                    let val = gguf_get_val_u64(ctx, i)
                    return Int32(clamping: val)
                }
            }
        }
        return nil
    }
    
    /// Estimate parameter count based on file size and quantization
    private static func estimateParameterCount(fileSize: UInt64, quantization: String) -> UInt64 {
        let fileSizeGB = Double(fileSize) / (1024.0 * 1024.0 * 1024.0)
        
        // Rough estimates based on typical quantization ratios
        switch quantization {
        case "Q4_K_M", "Q4_0":
            return UInt64(fileSizeGB * 1.8 * 1e9) // ~1.8B params per GB for Q4
        case "Q5_K_M":
            return UInt64(fileSizeGB * 1.5 * 1e9) // ~1.5B params per GB for Q5
        case "Q8_0":
            return UInt64(fileSizeGB * 1.0 * 1e9) // ~1B params per GB for Q8
        case "F16":
            return UInt64(fileSizeGB * 0.5 * 1e9) // ~0.5B params per GB for F16
        case "F32":
            return UInt64(fileSizeGB * 0.25 * 1e9) // ~0.25B params per GB for F32
        default:
            return UInt64(fileSizeGB * 1.2 * 1e9) // Default estimate
        }
    }
    
    /// Get available system memory in GB
    private static func getAvailableMemoryGB() -> Double {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let memoryGB = Double(physicalMemory) / (1024.0 * 1024.0 * 1024.0)
        
        #if os(iOS)
        // On iOS, be more conservative due to system restrictions
        return memoryGB * 0.3 // Assume only 30% is available for our app
        #else
        // On macOS/Linux, be less conservative but still leave room
        return memoryGB * 0.6 // Assume 60% is available
        #endif
    }
}

// MARK: - C API Bridge Functions
extension GGUFReader {
    /// Get key at index from GGUF context
    private static func gguf_get_key(_ ctx: OpaquePointer, _ i: Int64) -> UnsafePointer<CChar>? {
        // Bridge to the actual C function - this might need adjustment based on the exact API
        return llama.gguf_get_key(ctx, i)
    }
    
    /// Get key-value type at index
    private static func gguf_get_kv_type(_ ctx: OpaquePointer, _ i: Int64) -> gguf_type {
        return llama.gguf_get_kv_type(ctx, i)
    }
    
    /// Get string value at index
    private static func gguf_get_val_str(_ ctx: OpaquePointer, _ i: Int64) -> UnsafePointer<CChar>? {
        return llama.gguf_get_val_str(ctx, i)
    }
    
    /// Get UInt64 value at index
    private static func gguf_get_val_u64(_ ctx: OpaquePointer, _ i: Int64) -> UInt64 {
        return llama.gguf_get_val_u64(ctx, i)
    }
    
    /// Get Int64 value at index
    private static func gguf_get_val_i64(_ ctx: OpaquePointer, _ i: Int64) -> Int64 {
        return llama.gguf_get_val_i64(ctx, i)
    }
    
    /// Get UInt32 value at index
    private static func gguf_get_val_u32(_ ctx: OpaquePointer, _ i: Int64) -> UInt32 {
        return llama.gguf_get_val_u32(ctx, i)
    }
    
    /// Get Int32 value at index
    private static func gguf_get_val_i32(_ ctx: OpaquePointer, _ i: Int64) -> Int32 {
        return llama.gguf_get_val_i32(ctx, i)
    }
}