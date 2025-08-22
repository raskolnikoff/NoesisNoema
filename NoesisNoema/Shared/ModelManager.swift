//// Created by [Your Name] on [Date].
///// License: MIT License
import Foundation

class ModelManager: ObservableObject {

    /// The currently selected embedding model.
    var currentEmbeddingModel: EmbeddingModel
    /// The currently selected LLM model.
    var currentLLMModel: LLMModel
    /// Current model specification from registry
    var currentModelSpec: ModelSpec?

    /// LLM generation preset (auto or specific). Exposed to UI.
    private(set) var currentLLMPreset: String = "auto" // auto|factual|balanced|creative|json|code

    /// Model registry for auto-discovery and parameter extraction
    private let modelRegistry = ModelRegistry.shared

    /// The list of available embedding model names.
    /// Intended for use in UI dropdowns for embedding model selection in ContentView.
    let availableEmbeddingModels: [String] = [
        "default-embedding",
        "all-MiniLM-L6-v2",
        "LaBSE",
        "sentence-bert-base-ja"
    ]

    /// The list of available LLM model IDs from the registry.
    /// Dynamically populated from discovered GGUF files.
    var availableLLMModels: [String] {
        return modelRegistry.getAllModels().map { $0.id }
    }

    /// The list of available LLM model names for UI display.
    var availableLLMModelNames: [String] {
        let registeredModels = modelRegistry.getAllModels().map { $0.name }
        let legacyModels = [
            // Keep legacy model names for backward compatibility
            "default-llm",
            "llama3-8b",
            "llama3-70b",
            "gpt4all",
            "openchat",
            "mistral-7b",
            "phi-2",
            "tinyllama"
        ]
        return registeredModels + legacyModels
    }

    /// The list of available LLM presets for UI selection.
    let availableLLMPresets: [String] = ["auto", "factual", "balanced", "creative", "json", "code"]

    /// Initializes a ModelManager with default models.
    init() {
        // Create default embedding model
        self.currentEmbeddingModel = EmbeddingModel(name: "default-embedding")
        
        // Try to find the best available model from registry
        let defaultModel = findBestAvailableModel()
        self.currentLLMModel = defaultModel.llmModel
        self.currentModelSpec = defaultModel.spec
        
        // Start model discovery in background
        Task {
            await modelRegistry.scanForModels()
        }
    }
    
    /// Find the best available model from registry or fall back to legacy default
    private func findBestAvailableModel() -> (llmModel: LLMModel, spec: ModelSpec?) {
        let models = modelRegistry.getAllModels()
        
        // Prefer Jan models first, then other chat models, then any model
        if let janModel = models.first(where: { $0.name.lowercased().contains("jan") && $0.supportsChat }) {
            return (LLMModel(name: janModel.name, modelFile: janModel.filePath, version: janModel.parameterDescription), janModel)
        }
        
        if let chatModel = models.first(where: { $0.supportsChat }) {
            return (LLMModel(name: chatModel.name, modelFile: chatModel.filePath, version: chatModel.parameterDescription), chatModel)
        }
        
        if let anyModel = models.first {
            return (LLMModel(name: anyModel.name, modelFile: anyModel.filePath, version: anyModel.parameterDescription), anyModel)
        }
        
        // Fall back to legacy default if no models found in registry
        return (LLMModel(name: "Jan-V1-4B", modelFile: "Jan-v1-4B-Q4_K_M.gguf", version: "4B"), nil)
    }

    /// Switches the current embedding model to the specified name, if available.
    /// - Parameter name: The name of the embedding model to switch to.
    func switchEmbeddingModel(name: String) {
        if availableEmbeddingModels.contains(name) {
            self.currentEmbeddingModel = EmbeddingModel(name: name)
            // VectorStore の検索用モデルも同期
            VectorStore.shared.embeddingModel = self.currentEmbeddingModel
        }
    }

    /// Switches the current LLM model to the specified name or ID, if available.
    /// - Parameter name: The name or ID of the LLM model to switch to.
    func switchLLMModel(name: String) {
        // First try to find by ID in registry
        if let modelSpec = modelRegistry.getModel(id: name) {
            self.currentLLMModel = LLMModel(
                name: modelSpec.name,
                modelFile: modelSpec.filePath,
                version: modelSpec.parameterDescription
            )
            self.currentModelSpec = modelSpec
            return
        }
        
        // Then try to find by name in registry
        if let modelSpec = modelRegistry.getAllModels().first(where: { $0.name == name }) {
            self.currentLLMModel = LLMModel(
                name: modelSpec.name,
                modelFile: modelSpec.filePath,
                version: modelSpec.parameterDescription
            )
            self.currentModelSpec = modelSpec
            return
        }
        
        // Fall back to legacy model mapping for backward compatibility
        var modelFile = ""
        var version = ""
        switch name {
        case "Jan-V1-4B":
            modelFile = "Jan-v1-4B-Q4_K_M.gguf"
            version = "4B"
        case "Llama-3":
            modelFile = "llama3-8b.gguf"
            version = "8B"
        case "Phi-3-mini":
            modelFile = "phi-3-mini.gguf"
            version = "mini"
        case "Gemma-2B":
            modelFile = "gemma-2b.gguf"
            version = "2B"
        case "GPT-OSS-20B":
            modelFile = "gpt-oss-20b-Q4_K_S.gguf"
            version = "20B"
        default:
            // Try to find a similar model in registry
            let similarModel = modelRegistry.getAllModels().first { model in
                model.name.lowercased().contains(name.lowercased()) ||
                model.id.lowercased().contains(name.lowercased())
            }
            
            if let similar = similarModel {
                self.currentLLMModel = LLMModel(
                    name: similar.name,
                    modelFile: similar.filePath,
                    version: similar.parameterDescription
                )
                self.currentModelSpec = similar
                return
            }
            
            modelFile = ""
            version = ""
        }
        
        if !modelFile.isEmpty {
            self.currentLLMModel = LLMModel(name: name, modelFile: modelFile, version: version)
            self.currentModelSpec = nil
        }
    }

    /// Set the current LLM preset (UI-driven). Unknown values fallback to 'auto'.
    func setLLMPreset(name: String) {
        if availableLLMPresets.contains(name.lowercased()) {
            self.currentLLMPreset = name.lowercased()
        } else {
            self.currentLLMPreset = "auto"
        }
    }

    /// Stub for importing a new model resource.
    /// - Parameter file: The file to import (type depends on UI implementation).
    /// This method should handle loading a new model file (embedding or LLM), register it,
    /// and update the available model lists for UI selection. The implementation should
    /// handle validation, file storage, and updating `availableEmbeddingModels` or `availableLLMModels`.
    func importModelResource(file: Any) {
        // TODO: Implement model file import, registration, and update model lists.
        // This should trigger a registry rescan after importing the file
        Task {
            await modelRegistry.scanForModels()
        }
    }
    
    /// Get model information for a given model ID
    /// - Parameter modelId: The ID of the model to get info for
    /// - Returns: Formatted model information string, or nil if not found
    func getModelInfo(modelId: String) -> String? {
        return modelRegistry.getModelInfo(id: modelId)
    }
    
    /// Get current model's OOM-safe runtime parameters
    /// - Returns: RuntimeParams for the current model, or default safe params
    func getCurrentModelRuntimeParams() -> RuntimeParams? {
        return currentModelSpec?.defaultRuntimeParams
    }
    
    /// Force a rescan of available models
    func rescanModels() async {
        await modelRegistry.scanForModels()
    }

    /// Generates an embedding for the given text using the current embedding model.
    /// - Parameter text: The text to embed.
    /// - Returns: An array of floats representing the embedding.
    func generateEmbedding(for text: String) -> [Float] {
        return currentEmbeddingModel.embed(text: text)
    }

    /// Generates a response from the current LLM model based on the provided prompt.
    /// - Parameter prompt: The prompt to generate a response for.
    /// - Returns: A string containing the generated response.
    func generateResponse(for prompt: String) -> String {
        return currentLLMModel.generate(prompt: prompt)
    }

    /// Generates an answer to a question using the LLM model (asynchronous)
    func generateAsyncAnswer(question: String) async -> String {
        // RAG文脈を構築
        let embedding = self.currentEmbeddingModel.embed(text: question)
        let topChunks = VectorStore.shared.findRelevant(queryEmbedding: embedding, topK: 6)
        var context = topChunks.map { $0.content }.joined(separator: "\n---\n")
        if context.isEmpty { context = "" }
        // コンテキストの安全上限（簡易）
        if context.count > 2000 { context = String(context.prefix(2000)) }

        // @Sendable 回避: モデルをローカルへ
        let model = self.currentLLMModel
        let ctx = context.isEmpty ? nil : context
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let result = model.generate(prompt: question, context: ctx)
                continuation.resume(returning: result)
            }
        }
    }

    /// Loads a model from a file.
    /// - Parameter file: The file to load the model from.
    /// This method should be implemented to handle different model types.
    func loadModel(from file: Any) {
        // TODO: Implement if needed.
    }

    static let shared = ModelManager()
} // Example usage of the ModelManager
