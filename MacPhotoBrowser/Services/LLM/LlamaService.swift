//
//  LlamaService.swift
//  MacPhotoBrowser
//
//  llama.cpp Swift統合
//

import Foundation

#if ENABLE_LLAMA
import llama
#endif

/// llama.cpp を使用したローカルLLMサービス
actor LlamaService: LLMServiceProtocol {
    nonisolated let serviceName = "Local LLM (Gemma 2B)"

    private var isModelLoaded = false

    #if ENABLE_LLAMA
    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    #endif

    init() {}

    nonisolated var isAvailable: Bool {
        get async {
            await MainActor.run {
                LLMModelManager.shared.isModelDownloaded
            }
        }
    }

    /// モデルをメモリに読み込む
    func loadModel() async throws {
        let isDownloaded = await MainActor.run {
            LLMModelManager.shared.isModelDownloaded
        }
        guard isDownloaded else {
            throw LLMError.modelNotLoaded
        }

        guard !isModelLoaded else { return }

        let modelPath = await MainActor.run {
            LLMModelManager.shared.modelPath
        }
        guard let path = modelPath else {
            throw LLMError.modelNotLoaded
        }

        #if ENABLE_LLAMA
        llama_backend_init()

        var model_params = llama_model_default_params()
        model_params.n_gpu_layers = 0

        model = llama_model_load_from_file(path, model_params)
        guard model != nil else {
            print("[\(serviceName)] Failed to load model from \(path)")
            throw LLMError.modelNotLoaded
        }

        var ctx_params = llama_context_default_params()
        ctx_params.n_ctx = 2048
        ctx_params.n_threads = 4
        ctx_params.n_threads_batch = 4

        ctx = llama_init_from_model(model, ctx_params)
        guard ctx != nil else {
            llama_model_free(model)
            model = nil
            print("[\(serviceName)] Failed to create context")
            throw LLMError.modelNotLoaded
        }

        isModelLoaded = true
        print("[\(serviceName)] Model loaded successfully from \(path)")
        #else
        print("[\(serviceName)] llama package not enabled. Add -DENABLE_LLAMA to Swift flags.")
        throw LLMError.notAvailable
        #endif
    }

    /// モデルをメモリから解放
    func unloadModel() {
        #if ENABLE_LLAMA
        if ctx != nil {
            llama_free(ctx)
            ctx = nil
        }
        if model != nil {
            llama_model_free(model)
            model = nil
        }
        llama_backend_free()
        #endif
        isModelLoaded = false
        print("[\(serviceName)] Model unloaded")
    }

    func extractTags(from ocrText: String) async throws -> ExtractedTagData {
        if !isModelLoaded {
            try await loadModel()
        }

        #if ENABLE_LLAMA
        guard let ctx = ctx, let model = model else {
            throw LLMError.modelNotLoaded
        }

        let userPrompt = TaggingPrompts.userPromptForOCR(ocrText)
        let prompt = "<start_of_turn>user\n\(userPrompt)<end_of_turn>\n<start_of_turn>model\n"

        print("[\(serviceName)] Prompt: \(prompt.prefix(200))...")

        let response = try await generateText(prompt: prompt, ctx: ctx, model: model)
        print("[\(serviceName)] Generated response: \(response.prefix(300))...")

        let result = TaggingPrompts.parseJSONResponse(response)
        if result.hasValidData {
            return result
        }
        return extractTagsFromPlainText(response)
        #else
        print("[\(serviceName)] llama package not enabled")
        throw LLMError.notAvailable
        #endif
    }

    #if ENABLE_LLAMA
    private func generateText(prompt: String, ctx: OpaquePointer, model: OpaquePointer) async throws -> String {
        let vocab = llama_model_get_vocab(model)

        let n_ctx = llama_n_ctx(ctx)
        var tokens = [llama_token](repeating: 0, count: Int(n_ctx))
        let n_tokens = llama_tokenize(vocab, prompt, Int32(prompt.utf8.count), &tokens, Int32(n_ctx), true, false)

        guard n_tokens > 0 else {
            throw LLMError.extractionFailed("トークン化に失敗しました")
        }

        var batch = llama_batch_init(512, 0, 1)
        defer { llama_batch_free(batch) }

        batch.n_tokens = n_tokens
        for i in 0..<Int(n_tokens) {
            batch.token[i] = tokens[i]
            batch.pos[i] = Int32(i)
            batch.n_seq_id[i] = 1
            batch.seq_id[i]![0] = 0
            batch.logits[i] = 0
        }
        batch.logits[Int(batch.n_tokens) - 1] = 1

        if llama_decode(ctx, batch) != 0 {
            throw LLMError.extractionFailed("デコードに失敗しました")
        }

        var result = ""
        let maxTokens = 512
        var n_cur = Int(n_tokens)

        for _ in 0..<maxTokens {
            let n_vocab = llama_vocab_n_tokens(vocab)
            let logits = llama_get_logits_ith(ctx, Int32(batch.n_tokens) - 1)

            var max_logit: Float = -Float.infinity
            var max_id: llama_token = 0
            for i in 0..<Int(n_vocab) {
                if logits![i] > max_logit {
                    max_logit = logits![i]
                    max_id = llama_token(i)
                }
            }

            if llama_vocab_is_eog(vocab, max_id) {
                break
            }

            var buf = [CChar](repeating: 0, count: 256)
            let len = llama_token_to_piece(vocab, max_id, &buf, Int32(buf.count), 0, false)
            if len > 0 {
                let piece = String(cString: buf)
                result += piece

                if piece.contains("}") && result.contains("{") {
                    if let lastBrace = result.lastIndex(of: "}") {
                        result = String(result[...lastBrace])
                        break
                    }
                }
            }

            batch.n_tokens = 1
            batch.token[0] = max_id
            batch.pos[0] = Int32(n_cur)
            batch.n_seq_id[0] = 1
            batch.seq_id[0]![0] = 0
            batch.logits[0] = 1
            n_cur += 1

            if llama_decode(ctx, batch) != 0 {
                break
            }
        }

        return result
    }
    #endif

    // MARK: - Private Helpers

    /// JSONパース失敗時のフォールバック（小型モデル向け）
    private func extractTagsFromPlainText(_ text: String) -> ExtractedTagData {
        var tags: [String] = []

        // "tags": [...] パターン
        if let regex = try? NSRegularExpression(pattern: "\"tags\"\\s*:\\s*\\[([^\\]]+)\\]", options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            let tagsStr = String(text[range])
            tags = tagsStr.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
                .filter { !$0.isEmpty }
        }

        // リスト形式のフォールバック
        if tags.isEmpty {
            let lines = text.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("-") || trimmed.hasPrefix("*") || trimmed.hasPrefix("•") {
                    let tag = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                    if !tag.isEmpty && tag.count < 30 {
                        tags.append(tag)
                    }
                }
            }
        }

        return ExtractedTagData(
            tags: tags,
            description: nil,
            confidence: 0.3
        )
    }
}

// MARK: - Model Information

extension LlamaService {
    struct ModelInfo {
        static let name = "Gemma 2B Instruct"
        static let fileName = "gemma-2b-it-q4_k_m.gguf"
        static let fileSize: Int64 = 1_500_000_000
        static let downloadURL = "https://huggingface.co/lmstudio-ai/gemma-2b-it-GGUF/resolve/main/gemma-2b-it-q4_k_m.gguf"

        static var displayFileSize: String {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useGB, .useMB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: fileSize)
        }
    }
}
