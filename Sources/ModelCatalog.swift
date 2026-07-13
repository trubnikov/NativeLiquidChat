import Foundation

/// One entry in the local model library.
struct ModelInfo: Identifiable, Hashable, Codable {
    enum Kind: String, Codable {
        case text
        case vision
        case audio

        var iconName: String {
            switch self {
            case .text: return "bubble.left.and.bubble.right"
            case .vision: return "eye"
            case .audio: return "waveform"
            }
        }

        var displayName: String {
            switch self {
            case .text: return "Text"
            case .vision: return "Vision"
            case .audio: return "Audio"
            }
        }

    }

    let id: String          // the modelName passed to the SDK
    let displayName: String
    let kind: Kind
    let quantization: String
    let summary: String
    /// Approximate download size on disk (for the progress bar and "size" label).
    let approxBytes: Int64
    /// Rough peak RAM the model needs to run, used for the "fits on this device"
    /// check. Weights + KV cache + runtime overhead.
    let minRAMBytes: Int64

    var iconName: String { kind.iconName }
}

/// On-disk state of a model.
enum ModelDiskStatus: Equatable {
    case notDownloaded
    /// `downloadedBytes` grows as the file lands on disk; `totalBytes` is the
    /// catalog estimate. `progress` is derived for the bar.
    case downloading(downloadedBytes: Int64, totalBytes: Int64)
    case downloaded(sizeBytes: Int64?)

    var progress: Double {
        if case let .downloading(done, total) = self, total > 0 {
            return min(Double(done) / Double(total), 0.99)
        }
        return 0
    }
}

/// How well a model fits the current device, given its RAM and free disk space.
enum ModelFit {
    case fits            // comfortably runs
    case heavy           // runs but uses a lot of memory
    case wontFit         // not enough RAM
    case noSpace         // not enough free disk to download

    var label: String {
        switch self {
        case .fits: return "Fits well"
        case .heavy: return "Heavy"
        case .wontFit: return "Too large"
        case .noSpace: return "No space"
        }
    }

    var systemImage: String {
        switch self {
        case .fits: return "checkmark.seal.fill"
        case .heavy: return "exclamationmark.triangle.fill"
        case .wontFit: return "xmark.octagon.fill"
        case .noSpace: return "externaldrive.badge.xmark"
        }
    }
}

private let GB: Int64 = 1_000_000_000

enum ModelCatalog {
    /// Cached list of all models loaded dynamically.
    static var all: [ModelInfo] = loadCatalog()

    /// Default hardcoded models used as a fallback and seed configuration.
    private static let defaultModels: [ModelInfo] = [
        ModelInfo(
            id: "LFM2-350M",
            displayName: "LFM 350M",
            kind: .text,
            quantization: "Q4_0",
            summary: "Tiniest text model · ultra-fast, low memory",
            approxBytes: 230_000_000,
            minRAMBytes: 1 * GB
        ),
        ModelInfo(
            id: "LFM2-700M",
            displayName: "LFM 700M",
            kind: .text,
            quantization: "Q4_0",
            summary: "Small text model · fast, lightweight",
            approxBytes: 450_000_000,
            minRAMBytes: 2 * GB
        ),
        ModelInfo(
            id: "LFM2.5-1.2B-Instruct",
            displayName: "LFM Instruct 1.2B",
            kind: .text,
            quantization: "Q4_0",
            summary: "Balanced text model · best general chat",
            approxBytes: 730_000_000,
            minRAMBytes: 3 * GB
        ),
        ModelInfo(
            id: "LFM2-2.6B",
            displayName: "LFM 2.6B",
            kind: .text,
            quantization: "Q4_0",
            summary: "Larger text model · higher quality, heavier",
            approxBytes: 1_600_000_000,
            minRAMBytes: 5 * GB
        ),
        ModelInfo(
            id: "LFM2.5-VL-450M",
            displayName: "LFM Vision 450M",
            kind: .vision,
            quantization: "Q4_0",
            summary: "Compact vision model · image + text",
            approxBytes: 380_000_000,
            minRAMBytes: 2 * GB
        ),
        ModelInfo(
            id: "LFM2.5-VL-1.6B",
            displayName: "LFM Vision 1.6B",
            kind: .vision,
            quantization: "Q4_0",
            summary: "Capable vision model · image understanding",
            approxBytes: 1_100_000_000,
            minRAMBytes: 4 * GB
        )
    ]

    /// Loads the model catalog from `Documents/model_catalog.json`.
    /// Fallback to the default hardcoded list if file is missing or corrupt.
    static func loadCatalog() -> [ModelInfo] {
        let fileManager = FileManager.default
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        guard let docsDir = paths.first else { return defaultModels }
        let fileURL = docsDir.appendingPathComponent("model_catalog.json")

        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                let decoded = try JSONDecoder().decode([ModelInfo].self, from: data)
                return decoded
            } catch {
                print("[ModelCatalog] Failed to decode model catalog from Documents: \(error.localizedDescription)")
            }
        }

        // If file doesn't exist or decoding failed, seed/save default catalog
        saveCatalog(defaultModels)
        return defaultModels
    }

    /// Saves the model catalog to `Documents/model_catalog.json`.
    static func saveCatalog(_ models: [ModelInfo]) {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        guard let docsDir = paths.first else { return }
        let fileURL = docsDir.appendingPathComponent("model_catalog.json")
        do {
            let data = try JSONEncoder().encode(models)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("[ModelCatalog] Failed to save model catalog: \(error.localizedDescription)")
        }
    }

    /// Reloads the model catalog from disk.
    static func reload() {
        all = loadCatalog()
    }

    static func info(for modelName: String) -> ModelInfo? {
        all.first { $0.id == modelName }
    }
}
