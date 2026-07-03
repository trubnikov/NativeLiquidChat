import Foundation

struct TrainedObject: Codable, Identifiable {
    let id: UUID
    let customLabel: String
    let featureVector: [String: Double] // e.g. ["chair": 0.85, "desk": 0.12]
    let timestamp: Date
    
    init(id: UUID = UUID(), customLabel: String, featureVector: [String: Double], timestamp: Date = Date()) {
        self.id = id
        self.customLabel = customLabel
        self.featureVector = featureVector
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
    
    func train(customLabel: String, classifications: [String: Double]) {
        // Remove prior items with exactly the same custom label to avoid duplication
        trainedObjects.removeAll { $0.customLabel.lowercased() == customLabel.lowercased() }
        
        let newObj = TrainedObject(customLabel: customLabel, featureVector: classifications)
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
    
    func findMatch(for classifications: [String: Double]) -> String? {
        guard !classifications.isEmpty else { return nil }
        
        var bestMatch: TrainedObject? = nil
        var bestScore: Double = 0.0
        
        for obj in trainedObjects {
            let score = cosineSimilarity(classifications, obj.featureVector)
            if score > bestScore {
                bestScore = score
                bestMatch = obj
            }
        }
        
        // Threshold: 65% similarity
        if bestScore >= 0.65 {
            return bestMatch?.customLabel
        }
        return nil
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
