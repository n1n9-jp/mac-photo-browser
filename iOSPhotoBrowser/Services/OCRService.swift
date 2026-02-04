//
//  OCRService.swift
//  iOSPhotoBrowser
//

import Foundation
import Vision
import UIKit

actor OCRService {
    static let shared = OCRService()

    private init() {}

    func recognizeText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                let recognizedText = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")

                continuation.resume(returning: recognizedText)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func extractISBN(from text: String) -> String? {
        // ISBN-13: 978 or 979 followed by 10 digits (with optional hyphens/spaces)
        // Pattern matches: 978-4-12-345678-9, 9784123456789, 978 4 12 345678 9, etc.
        let patterns = [
            // ISBN-13 with various separators
            "97[89][-\\s]?\\d[-\\s]?\\d{2,5}[-\\s]?\\d{2,7}[-\\s]?\\d",
            // ISBN-13 without separators (13 consecutive digits starting with 978 or 979)
            "97[89]\\d{10}"
        ]

        for pattern in patterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                let matched = String(text[range])
                // Remove all non-digit characters to get clean ISBN
                let cleanISBN = matched.filter { $0.isNumber }
                if cleanISBN.count == 13 {
                    return cleanISBN
                }
            }
        }

        // Also try to find ISBN-10 and convert to ISBN-13
        let isbn10Pattern = "\\d[-\\s]?\\d{2,5}[-\\s]?\\d{2,7}[-\\s]?[\\dX]"
        if let range = text.range(of: isbn10Pattern, options: .regularExpression) {
            let matched = String(text[range])
            let cleanISBN = matched.filter { $0.isNumber || $0 == "X" }
            if cleanISBN.count == 10 {
                if let isbn13 = convertISBN10to13(cleanISBN) {
                    return isbn13
                }
            }
        }

        return nil
    }

    private func convertISBN10to13(_ isbn10: String) -> String? {
        guard isbn10.count == 10 else { return nil }

        let prefix = "978"
        let isbn10Body = String(isbn10.prefix(9))
        let isbn13WithoutCheckDigit = prefix + isbn10Body

        // Calculate ISBN-13 check digit
        var sum = 0
        for (index, char) in isbn13WithoutCheckDigit.enumerated() {
            guard let digit = Int(String(char)) else { return nil }
            let multiplier = (index % 2 == 0) ? 1 : 3
            sum += digit * multiplier
        }

        let checkDigit = (10 - (sum % 10)) % 10
        return isbn13WithoutCheckDigit + String(checkDigit)
    }
}

enum OCRError: Error, LocalizedError {
    case invalidImage
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "画像の読み込みに失敗しました"
        case .recognitionFailed:
            return "テキストの認識に失敗しました"
        }
    }
}
