# ModelRegistry Implementation

This implementation adds a Model Registry with GGUF auto-params and `nn model info <id>` CLI functionality for OOM-safe defaults.

## New Files Added

### Core Implementation
- `NoesisNoema/Shared/ModelSpec.swift` - Model specification with auto-detected GGUF parameters
- `NoesisNoema/Shared/GGUFReader.swift` - GGUF file reader for extracting model metadata  
- `NoesisNoema/Shared/ModelRegistry.swift` - Model registry with auto-discovery

### Updated Files
- `NoesisNoema/Shared/ModelManager.swift` - Updated to use registry instead of hardcoded models
- `LlamaBridgeTest/main.swift` - Added CLI commands for model information

## Features

### ModelSpec Structure
- Auto-detected GGUF parameters (architecture, parameter count, context length, etc.)
- OOM-safe runtime defaults based on available system memory
- Model capabilities detection (chat, instruct, completion support)
- Human-readable size and parameter descriptions

### RuntimeParams
- Context size, batch size, GPU layers, thread count
- Memory pool size and memory mapping settings
- Platform-specific defaults (iOS uses more conservative settings)
- Memory safety levels based on available memory to model size ratio

### ModelRegistry
- Auto-discovery of GGUF files in standard search paths
- Persistent registry with JSON storage
- Model filtering by architecture, size, capabilities
- Background scanning with file system watching

### CLI Commands
```bash
# List all discovered models
nn model list

# Show detailed model information with OOM-safe defaults
nn model info <model-id>
```

## OOM-Safe Defaults

The system calculates safe runtime parameters based on:
- Available system memory
- Model file size  
- Target platform (iOS vs macOS/Linux)
- Memory ratio (available memory / model size)

### Memory Safety Levels
- **Ratio < 1.5x**: Minimal settings (512 ctx, 32 batch, 128MB pool)
- **Ratio < 3.0x**: Conservative settings (1024 ctx, 64 batch, 256MB pool)  
- **Ratio < 6.0x**: Balanced settings (2048 ctx, 128 batch, 512MB pool)
- **Ratio >= 6.0x**: Optimal settings (4096 ctx, 256 batch, 1024MB pool)

## Usage

### From Code
```swift
let registry = ModelRegistry.shared
await registry.scanForModels()

let models = registry.getAllModels()
let modelInfo = registry.getModelInfo(id: "jan-v1-4b-q4_k_m")

// Use with ModelManager
let manager = ModelManager.shared
manager.switchLLMModel(name: "jan-v1-4b-q4_k_m")
let runtimeParams = manager.getCurrentModelRuntimeParams()
```

### From CLI
```bash
# List available models
./LlamaBridgeTest model list

# Get model information  
./LlamaBridgeTest model info jan-v1-4b-q4_k_m

# Use model for inference with auto-detected params
./LlamaBridgeTest -m auto -p "Hello, world!"
```

## Search Paths

The registry automatically searches for GGUF files in:
- Current working directory
- Executable directory  
- Bundle resources and Models subdirectories
- Documents directory
- User Downloads folder
- Conventional model directories (./models, ./Resources/Models, etc.)

## Benefits

1. **Automatic Discovery**: No need to manually configure model paths
2. **OOM Safety**: Prevents out-of-memory crashes with conservative defaults  
3. **Platform Awareness**: Different settings for iOS vs desktop platforms
4. **Metadata Extraction**: Rich model information from GGUF files
5. **CLI Integration**: Easy model inspection and management
6. **Backward Compatibility**: Existing hardcoded models still work as fallbacks

This implementation provides a solid foundation for model management with automatic parameter tuning and memory safety.