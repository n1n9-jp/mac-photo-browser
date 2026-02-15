//
//  LLMService.swift
//  MacPhotoBrowser
//

import Foundation
import UIKit

/// LLMサービスのファサード
/// ユーザー設定と利用可能性に基づいて適切なLLMサービスにルーティング
actor LLMService {
    static let shared = LLMService()

    private var appleService: (any LLMServiceProtocol)?
    private var llamaService: LlamaService?
    private var vlmService: VLMService?
    private var cloudService: CloudLLMService?

    private init() {
        if #available(iOS 26.0, *) {
            appleService = AppleFoundationModelsService()
        }
        llamaService = LlamaService()
        vlmService = VLMService()
        cloudService = CloudLLMService()
    }

    // MARK: - Public Interface

    /// 利用可能なLLMを使用してタグと説明文を抽出
    func extractTags(from ocrText: String) async throws -> ExtractedTagData {
        let preference = await MainActor.run { LLMModelManager.shared.enginePreference }

        switch preference {
        case .none:
            throw LLMError.notAvailable

        case .cloudAPI:
            return try await extractWithCloud(from: ocrText)

        case .appleIntelligence:
            return try await extractWithApple(from: ocrText)

        case .localModel:
            return try await extractWithLlama(from: ocrText)

        case .auto:
            return try await extractWithAuto(from: ocrText)
        }
    }

    /// 現在利用可能なサービスの名前を取得
    func availableServiceName() async -> String? {
        let preference = await MainActor.run { LLMModelManager.shared.enginePreference }

        switch preference {
        case .none:
            return nil
        case .cloudAPI:
            if let service = cloudService, await service.isAvailable {
                return service.serviceName
            }
            return nil
        case .appleIntelligence:
            if #available(iOS 26.0, *), let service = appleService, await service.isAvailable {
                return service.serviceName
            }
            return nil
        case .localModel:
            if let service = llamaService, await service.isAvailable {
                return service.serviceName
            }
            return nil
        case .auto:
            if let service = cloudService, await service.isAvailable {
                return service.serviceName
            }
            if #available(iOS 26.0, *), let service = appleService, await service.isAvailable {
                return service.serviceName
            }
            if let service = llamaService, await service.isAvailable {
                return service.serviceName
            }
            return nil
        }
    }

    /// いずれかのLLMサービスが利用可能かどうか
    func isAnyServiceAvailable() async -> Bool {
        let preference = await MainActor.run { LLMModelManager.shared.enginePreference }
        print("[LLMService] Checking availability, preference: \(preference)")

        switch preference {
        case .none:
            print("[LLMService] LLM disabled by user")
            return false
        case .cloudAPI:
            if let service = cloudService {
                let available = await service.isAvailable
                print("[LLMService] Cloud API available: \(available)")
                return available
            }
            return false
        case .appleIntelligence:
            if #available(iOS 26.0, *), let service = appleService {
                let available = await service.isAvailable
                print("[LLMService] Apple Intelligence available: \(available)")
                return available
            }
            print("[LLMService] Apple Intelligence not available (iOS < 26)")
            return false
        case .localModel:
            if let service = llamaService {
                let available = await service.isAvailable
                print("[LLMService] Local model available: \(available)")
                return available
            }
            print("[LLMService] Local model service not initialized")
            return false
        case .auto:
            if let service = cloudService {
                let cloudAvailable = await service.isAvailable
                print("[LLMService] Auto mode - Cloud API available: \(cloudAvailable)")
                if cloudAvailable { return true }
            }
            if #available(iOS 26.0, *), let service = appleService {
                let appleAvailable = await service.isAvailable
                print("[LLMService] Auto mode - Apple Intelligence available: \(appleAvailable)")
                if appleAvailable { return true }
            }
            if let service = llamaService {
                let llamaAvailable = await service.isAvailable
                print("[LLMService] Auto mode - Local model available: \(llamaAvailable)")
                if llamaAvailable { return true }
            }
            print("[LLMService] No LLM service available")
            return false
        }
    }

    // MARK: - Private Methods

    private func extractWithCloud(from ocrText: String) async throws -> ExtractedTagData {
        guard let service = cloudService else {
            throw LLMError.notAvailable
        }
        guard await service.isAvailable else {
            throw LLMError.extractionFailed("APIキーが設定されていません")
        }
        return try await service.extractTags(from: ocrText)
    }

    private func extractWithApple(from ocrText: String) async throws -> ExtractedTagData {
        guard #available(iOS 26.0, *), let service = appleService else {
            throw LLMError.notAvailable
        }
        guard await service.isAvailable else {
            throw LLMError.notAvailable
        }
        return try await service.extractTags(from: ocrText)
    }

    private func extractWithLlama(from ocrText: String) async throws -> ExtractedTagData {
        guard let service = llamaService else {
            throw LLMError.notAvailable
        }
        guard await service.isAvailable else {
            throw LLMError.modelNotLoaded
        }
        return try await service.extractTags(from: ocrText)
    }

    private func extractWithAuto(from ocrText: String) async throws -> ExtractedTagData {
        // 1. クラウドAPI を試行（最高精度）
        if let service = cloudService, await service.isAvailable {
            do {
                let result = try await service.extractTags(from: ocrText)
                print("[LLMService] Extracted using \(service.serviceName)")
                return result
            } catch {
                print("[LLMService] Cloud API failed: \(error.localizedDescription)")
            }
        }

        // 2. Apple Intelligence を試行
        if #available(iOS 26.0, *), let service = appleService, await service.isAvailable {
            do {
                let result = try await service.extractTags(from: ocrText)
                print("[LLMService] Extracted using \(service.serviceName)")
                return result
            } catch {
                print("[LLMService] Apple Intelligence failed: \(error.localizedDescription)")
            }
        }

        // 3. ローカルモデル（llama.cpp）を試行
        if let service = llamaService, await service.isAvailable {
            do {
                let result = try await service.extractTags(from: ocrText)
                print("[LLMService] Extracted using \(service.serviceName)")
                return result
            } catch {
                print("[LLMService] Local model failed: \(error.localizedDescription)")
            }
        }

        // 4. すべて利用不可
        throw LLMError.notAvailable
    }

    // MARK: - Model Management

    func loadLocalModel() async throws {
        guard let service = llamaService else {
            throw LLMError.notAvailable
        }
        try await service.loadModel()
    }

    func unloadLocalModel() async {
        await llamaService?.unloadModel()
    }

    // MARK: - VLM (Vision Language Model) Methods

    /// 画像から直接タグと説明文を抽出（VLM使用、OCR不要）
    func extractTagsFromImage(_ image: UIImage) async throws -> ExtractedTagData {
        guard let service = vlmService else {
            throw LLMError.notAvailable
        }
        guard await service.isAvailable else {
            throw LLMError.modelNotLoaded
        }
        return try await service.extractTags(from: image)
    }

    func isVLMAvailable() async -> Bool {
        guard let service = vlmService else { return false }
        return await service.isAvailable
    }

    func loadVLMModel() async throws {
        guard let service = vlmService else {
            throw LLMError.notAvailable
        }
        try await service.loadModel()
    }

    func unloadVLMModel() async {
        await vlmService?.unloadModel()
    }
}

// MARK: - Convenience Extension

extension LLMService {
    /// OCRテキストからタグを抽出（失敗時は空のデータを返す）
    func extractTagsOrEmpty(from ocrText: String) async -> ExtractedTagData {
        do {
            return try await extractTags(from: ocrText)
        } catch {
            print("[LLMService] Extraction failed: \(error.localizedDescription)")
            return ExtractedTagData()
        }
    }

    /// 画像からタグを抽出（失敗時は空のデータを返す）
    func extractTagsFromImageOrEmpty(_ image: UIImage) async -> ExtractedTagData {
        do {
            return try await extractTagsFromImage(image)
        } catch {
            print("[LLMService] VLM extraction failed: \(error.localizedDescription)")
            return ExtractedTagData()
        }
    }

    /// クラウドAPIで画像から直接タグを抽出
    func extractTagsFromImageWithCloud(_ image: UIImage) async throws -> ExtractedTagData {
        guard let service = cloudService else {
            throw LLMError.notAvailable
        }
        guard await service.isAvailable else {
            throw LLMError.extractionFailed("APIキーが設定されていません")
        }
        return try await service.extractTagsFromImage(image)
    }

    func isCloudAPIAvailable() async -> Bool {
        guard let service = cloudService else { return false }
        return await service.isAvailable
    }

    /// 最適な方法でタグを抽出（クラウドAPI → VLM → OCR+LLM）
    func extractTagsBestMethod(image: UIImage, ocrText: String?) async -> ExtractedTagData {
        // 1. クラウドAPIが利用可能なら画像から直接抽出（最高精度）
        if await isCloudAPIAvailable() {
            do {
                let result = try await extractTagsFromImageWithCloud(image)
                if result.hasValidData {
                    print("[LLMService] Extracted using Cloud API (image)")
                    return result
                }
            } catch {
                print("[LLMService] Cloud API image extraction failed: \(error.localizedDescription)")
            }
        }

        // 2. VLMが利用可能なら画像から直接抽出
        if await isVLMAvailable() {
            let result = await extractTagsFromImageOrEmpty(image)
            if result.hasValidData {
                print("[LLMService] Extracted using VLM")
                return result
            }
        }

        // 3. OCRテキストがあればLLMで処理
        if let ocrText = ocrText, !ocrText.isEmpty {
            let result = await extractTagsOrEmpty(from: ocrText)
            if result.hasValidData {
                print("[LLMService] Extracted using OCR+LLM")
                return result
            }
        }

        // 4. 抽出失敗
        print("[LLMService] No valid extraction result")
        return ExtractedTagData()
    }
}
