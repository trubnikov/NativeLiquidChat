import Foundation

struct TrainedObject: Codable, Identifiable {
    let id: UUID
    let customLabel: String
    let featureVector: [String: Double] // legacy: classification histogram ["chair": 0.85]
    /// v2: visual feature print of the actual image (VNGenerateImageFeaturePrintRequest).
    /// Distinguishes instances (your mug vs. a similar mug), unlike the histogram.
    /// Optional so objects trained before this upgrade still decode and match.
    let featurePrint: [Float]?
    let timestamp: Date

    init(id: UUID = UUID(), customLabel: String, featureVector: [String: Double],
         featurePrint: [Float]? = nil, timestamp: Date = Date()) {
        self.id = id
        self.customLabel = customLabel
        self.featureVector = featureVector
        self.featurePrint = featurePrint
        self.timestamp = timestamp
    }
}

class TrainedObjectsManager: ObservableObject {
    static let shared = TrainedObjectsManager()
    
    @Published var trainedObjects: [TrainedObject] = []
    
    private let fileName = "trained_objects.json"
    
    private var fileURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent(fileName)
    }
    
    init() {
        load()
    }
    
    /// Cosine similarity needed on the visual feature print to count as the same
    /// object instance. Prints of the same object across angles typically score
    /// well above this; different objects of the same type fall below.
    static let featurePrintThreshold: Float = 0.75
    /// Legacy histogram threshold (kept for objects trained before feature prints).
    static let histogramThreshold: Double = 0.65

    func train(customLabel: String, classifications: [String: Double], featurePrint: [Float]? = nil) {
        // Remove prior items with exactly the same custom label to avoid duplication
        trainedObjects.removeAll { $0.customLabel.lowercased() == customLabel.lowercased() }

        let newObj = TrainedObject(customLabel: customLabel,
                                   featureVector: classifications,
                                   featurePrint: featurePrint)
        trainedObjects.append(newObj)
        save()

        // Register in Knowledge Graph
        if !KnowledgeGraphManager.shared.nodes.contains(where: { $0.label.lowercased() == customLabel.lowercased() }) {
            KnowledgeGraphManager.shared.addNode(label: customLabel, type: .object)
        }
    }

    func forget(id: UUID) {
        if let obj = trainedObjects.first(where: { $0.id == id }) {
            // Also clean up from Knowledge Graph
            if let graphNode = KnowledgeGraphManager.shared.nodes.first(where: { $0.label.lowercased() == obj.customLabel.lowercased() }) {
                KnowledgeGraphManager.shared.deleteNode(id: graphNode.id)
            }
        }
        trainedObjects.removeAll { $0.id == id }
        save()
    }

    /// Matches against trained objects. Prefers the visual feature print (true
    /// instance recognition); falls back to the classification histogram for
    /// objects trained before the upgrade.
    func findMatch(for classifications: [String: Double], featurePrint: [Float]? = nil) -> String? {
        var bestPrintMatch: TrainedObject? = nil
        var bestPrintScore: Float = 0.0
        var bestHistMatch: TrainedObject? = nil
        var bestHistScore: Double = 0.0

        for obj in trainedObjects {
            if let query = featurePrint, let stored = obj.featurePrint {
                let score = Self.cosine(query, stored)
                if score > bestPrintScore {
                    bestPrintScore = score
                    bestPrintMatch = obj
                }
            } else if !classifications.isEmpty {
                let score = cosineSimilarity(classifications, obj.featureVector)
                if score > bestHistScore {
                    bestHistScore = score
                    bestHistMatch = obj
                }
            }
        }

        #if DEBUG
        if bestPrintScore > 0 {
            print(String(format: "[TrainedObjects] best print score: %.3f (%@)",
                         bestPrintScore, bestPrintMatch?.customLabel ?? "-"))
        }
        #endif

        if bestPrintScore >= Self.featurePrintThreshold {
            return bestPrintMatch?.customLabel
        }
        if bestHistScore >= Self.histogramThreshold {
            return bestHistMatch?.customLabel
        }
        return nil
    }

    /// Plain cosine over float vectors (feature prints).
    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = sqrt(na) * sqrt(nb)
        return denom > 0 ? dot / denom : 0
    }
    
    private func cosineSimilarity(_ vecA: [String: Double], _ vecB: [String: Double]) -> Double {
        var dotProduct: Double = 0.0
        var magnitudeA: Double = 0.0
        var magnitudeB: Double = 0.0
        
        let keys = Set(vecA.keys).union(vecB.keys)
        
        for key in keys {
            let valA = vecA[key] ?? 0.0
            let valB = vecB[key] ?? 0.0
            
            dotProduct += valA * valB
            magnitudeA += valA * valA
            magnitudeB += valB * valB
        }
        
        guard magnitudeA > 0 && magnitudeB > 0 else { return 0.0 }
        return dotProduct / (sqrt(magnitudeA) * sqrt(magnitudeB))
    }
    
    func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            self.trainedObjects = try JSONDecoder().decode([TrainedObject].self, from: data)
        } catch {
            print("[TrainedObjectsManager] Failed to load: \(error.localizedDescription)")
            self.trainedObjects = []
        }
    }
    
    func save() {
        do {
            let data = try JSONEncoder().encode(trainedObjects)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("[TrainedObjectsManager] Failed to save: \(error.localizedDescription)")
        }
    }
}
