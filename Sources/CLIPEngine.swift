import Accelerate
import CoreML
import Foundation
import UIKit
import Vision

/// Zero-shot open-vocabulary recognition via MobileCLIP-S0.
///
/// The idea (the "implanted knowledge parser"): an LLM wrote a vocabulary of
/// ~1200 object names at build time; MobileCLIP's *text* encoder converted them
/// into 512-d vectors on the Mac (precomputed, bundled as a binary). On device
/// only the *image* encoder runs: each camera frame becomes a 512-d vector in
/// the SAME space, and a cosine match against the vocabulary recognizes objects
/// the system was never trained on. Fully offline.
final class CLIPEngine {
    static let shared = CLIPEngine()

    struct Match {
        let label: String
        let score: Float
    }

    private var visionModel: VNCoreMLModel?
    private var labels: [String] = []
    /// Row-major [labels.count x 512], L2-normalized rows.
    private var vocab: [Float] = []
    private let dim = 512

    /// Cosine similarity needed to accept a zero-shot label. Calibrated on real
    /// device frames (see DEBUG log): live cluttered scenes score 0.21–0.28 for
    /// correct labels; the 3-second stability window in the agent loop filters
    /// out flicker between near-synonyms.
    static let acceptThreshold: Float = 0.21

    private init() {
        load()
    }

    var isReady: Bool { visionModel != nil && !labels.isEmpty }

    private func load() {
        // Compiled model (Xcode compiles the bundled .mlpackage to .mlmodelc).
        guard let modelURL = Bundle.main.url(forResource: "mobileclip_s0_image",
                                             withExtension: "mlmodelc") else {
            print("[CLIP] image encoder missing from bundle")
            return
        }
        do {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .all   // let Core ML pick ANE/GPU
            let ml = try MLModel(contentsOf: modelURL, configuration: cfg)
            visionModel = try VNCoreMLModel(for: ml)
        } catch {
            print("[CLIP] model load failed: \(error)")
            return
        }

        guard let labURL = Bundle.main.url(forResource: "clip_vocab_labels", withExtension: "json"),
              let labData = try? Data(contentsOf: labURL),
              let labs = try? JSONDecoder().decode([String].self, from: labData),
              let embURL = Bundle.main.url(forResource: "clip_vocab_embeddings", withExtension: "bin"),
              let embData = try? Data(contentsOf: embURL) else {
            print("[CLIP] vocabulary missing from bundle")
            visionModel = nil
            return
        }

        let count = embData.count / MemoryLayout<Float>.size
        guard count == labs.count * dim else {
            print("[CLIP] vocab size mismatch: \(count) floats vs \(labs.count) labels")
            visionModel = nil
            return
        }
        labels = labs
        vocab = embData.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))   // iOS is little-endian, as written
        }
        print("[CLIP] ready: \(labels.count) labels")
    }

    // MARK: - Embedding

    /// Embeds a camera frame (Vision handles center-crop + resize to 256).
    func embed(pixelBuffer: CVPixelBuffer) -> [Float]? {
        guard let visionModel else { return nil }
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .centerCrop
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        return runEmbed(request: request, handler: handler)
    }

    /// Embeds a still image (chat photos).
    func embed(image: UIImage) -> [Float]? {
        guard let visionModel, let cg = image.cgImage else { return nil }
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .centerCrop
        let handler = VNImageRequestHandler(cgImage: cg)
        return runEmbed(request: request, handler: handler)
    }

    private func runEmbed(request: VNCoreMLRequest, handler: VNImageRequestHandler) -> [Float]? {
        do {
            try handler.perform([request])
            guard let obs = request.results?.first as? VNCoreMLFeatureValueObservation,
                  let arr = obs.featureValue.multiArrayValue else { return nil }
            var v = [Float](repeating: 0, count: dim)
            for i in 0..<dim { v[i] = arr[i].floatValue }
            // L2-normalize so dot product == cosine.
            var norm: Float = 0
            vDSP_svesq(v, 1, &norm, vDSP_Length(dim))
            norm = sqrt(norm)
            guard norm > 0 else { return nil }
            vDSP_vsdiv(v, 1, &norm, &v, 1, vDSP_Length(dim))
            return v
        } catch {
            print("[CLIP] embed failed: \(error)")
            return nil
        }
    }

    // MARK: - Zero-shot classification

    /// Top-k vocabulary matches for a normalized image embedding.
    func classify(_ embedding: [Float], topK: Int = 3) -> [Match] {
        guard embedding.count == dim, !vocab.isEmpty else { return [] }
        var scores = [Float](repeating: 0, count: labels.count)
        // scores = vocab (N x 512) * embedding (512)
        cblas_sgemv(CblasRowMajor, CblasNoTrans,
                    Int32(labels.count), Int32(dim),
                    1.0, vocab, Int32(dim),
                    embedding, 1, 0.0, &scores, 1)
        let idx = scores.indices.sorted { scores[$0] > scores[$1] }.prefix(topK)
        return idx.map { Match(label: labels[$0], score: scores[$0]) }
    }

    /// One-call helper: best accepted label for a frame, or nil.
    func bestLabel(pixelBuffer: CVPixelBuffer) -> Match? {
        guard let emb = embed(pixelBuffer: pixelBuffer) else { return nil }
        let top = classify(emb, topK: 3)
        #if DEBUG
        let s = top.map { "\($0.label)=\(String(format: "%.3f", $0.score))" }.joined(separator: ", ")
        print("[CLIP] top: \(s)")
        #endif
        guard let first = top.first, first.score >= Self.acceptThreshold else { return nil }
        return first
    }

    /// Best accepted label for a still image, or nil.
    func bestLabel(image: UIImage) -> Match? {
        guard let emb = embed(image: image) else { return nil }
        let top = classify(emb, topK: 3)
        guard let first = top.first, first.score >= Self.acceptThreshold else { return nil }
        return first
    }
}
