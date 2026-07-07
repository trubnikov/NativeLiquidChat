import Vision
import UIKit

struct VisionAnalysisResult {
    let classifications: [String]
    let recognizedText: String
    
    // Cognitive helper to determine hypothesis and persona locally
    var cognitiveState: (hypothesis: String, persona: String) {
        let text = recognizedText.lowercased()
        let objects = classifications.map { $0.lowercased() }
        
        // 1. Coding/Tech context
        if objects.contains(where: { $0.contains("computer") || $0.contains("screen") || $0.contains("keyboard") || $0.contains("laptop") || $0.contains("monitor") }) {
            if text.contains("func") || text.contains("import") || text.contains("class") || text.contains("struct") || text.contains("var") || text.contains("let") {
                return (
                    "The user is coding or debugging Swift code.",
                    "You are an expert Swift and iOS developer. Help the user debug their code or explain concepts clearly."
                )
            } else {
                return (
                    "The user is working on their computer.",
                    "You are a productive tech assistant. Help the user organize their thoughts, write emails, or solve problems."
                )
            }
        }
        
        // 2. Document/Writing context
        if objects.contains(where: { $0.contains("paper") || $0.contains("book") || $0.contains("document") || $0.contains("pen") || $0.contains("notebook") }) {
            return (
                "The user is reading, writing, or analyzing a document.",
                "You are an analytical assistant. Help the user summarize, translate, or extract key insights from the text."
            )
        }
        
        // 3. Food/Drink/Kitchen context
        if objects.contains(where: { $0.contains("coffee") || $0.contains("cup") || $0.contains("food") || $0.contains("drink") || $0.contains("bottle") || $0.contains("mug") || $0.contains("glass") }) {
            return (
                "The user is enjoying a drink or meal.",
                "You are a friendly, conversational assistant. Chat casually with the user and keep them company."
            )
        }
        
        // 4. Default fallback
        let dominantObject = classifications.first?.components(separatedBy: " ").first ?? "unknown objects"
        let cleanName = dominantObject.replacingOccurrences(of: "_", with: " ")
        return (
            "The user is showing an image containing: \(cleanName).",
            "You are a helpful visual assistant. Answer questions about the perceived objects: \(cleanName)."
        )
    }
}

class VisionProcessor {

    // MARK: - Visual feature print (instance-level embedding)

    /// Converts a VNFeaturePrintObservation into a plain [Float] vector so it can
    /// be stored in JSON and compared with cosine similarity.
    static func floats(from observation: VNFeaturePrintObservation) -> [Float]? {
        guard observation.elementType == .float, observation.elementCount > 0 else { return nil }
        let count = observation.elementCount
        return observation.data.withUnsafeBytes { raw -> [Float] in
            let buf = raw.bindMemory(to: Float.self)
            return Array(buf.prefix(count))
        }
    }

    /// Visual embedding of the whole image — unlike the classification histogram,
    /// this distinguishes *instances* (your mug vs. another similar mug).
    static func featurePrint(for image: UIImage) -> [Float]? {
        guard let cgImage = image.cgImage else { return nil }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNGenerateImageFeaturePrintRequest()
        do {
            try handler.perform([request])
            if let obs = request.results?.first as? VNFeaturePrintObservation {
                return floats(from: obs)
            }
        } catch {
            print("[VisionProcessor] featurePrint failed: \(error)")
        }
        return nil
    }

    static func analyzeImage(_ image: UIImage) async -> VisionAnalysisResult {
        guard let cgImage = image.cgImage else {
            return VisionAnalysisResult(classifications: [], recognizedText: "")
        }
        
        return await withCheckedContinuation { continuation in
            let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            var classifications: [String] = []
            var recognizedText = ""
            
            // 1. Classification Request
            let classificationRequest = VNClassifyImageRequest { request, error in
                guard error == nil,
                      let results = request.results as? [VNClassificationObservation] else {
                    return
                }
                // Get top 5 classifications with confidence > 5%
                classifications = results
                    .filter { $0.confidence > 0.05 }
                    .prefix(5)
                    .map { "\($0.identifier) (\(Int($0.confidence * 100))%)" }
            }
            
            // 2. Text Recognition Request
            let textRequest = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let results = request.results as? [VNRecognizedTextObservation] else {
                    return
                }
                let lines = results.compactMap { $0.topCandidates(1).first?.string }
                recognizedText = lines.joined(separator: "\n")
            }
            textRequest.recognitionLevel = .accurate
            
            do {
                try requestHandler.perform([classificationRequest, textRequest])
            } catch {
                print("Failed to perform Vision requests: \(error)")
            }
            
            continuation.resume(returning: VisionAnalysisResult(
                classifications: classifications,
                recognizedText: recognizedText
            ))
        }
    }
}
