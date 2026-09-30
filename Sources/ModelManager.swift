import SwiftUI
import LeapModelDownloader

/// Ollama-style local model library: download to disk, query status, delete.
///
/// Models are addressed by their bundle manifest (`ModelInfo.manifestURL`), the
/// same URL `ChatStore` loads from, so both always agree on what is on disk.
@Observable
@MainActor
final class ModelManager {
    private(set) var statuses: [String: ModelDiskStatus] = [:]

    private let downloader = ModelDownloader(sessionConfiguration: .default)
    /// Root directory where the SDK keeps downloaded bundles.
    private let modelsRoot: URL

    /// Total physical RAM of the device.
    let deviceRAM: Int64 = Int64(ProcessInfo.processInfo.physicalMemory)

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.modelsRoot = docs.appendingPathComponent("leap_models")

        for model in ModelCatalog.all {
            statuses[model.id] = .notDownloaded
        }
        excludeModelsFromBackup()
    }

    /// Free space available on the device for app data.
    var freeDiskBytes: Int64 {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    /// Whether a model can run/download on this device, given RAM and free space.
    func fit(for model: ModelInfo) -> ModelFit {
        // Already downloaded → only RAM matters for running it.
        var onDisk = false
        if case .downloaded = status(for: model.id) { onDisk = true }
        if !onDisk && model.approxBytes > freeDiskBytes {
            return .noSpace
        }
        // iOS lets a single app use roughly half of physical RAM before jetsam.
        let usableRAM = Int64(Double(deviceRAM) * 0.55)
        if model.minRAMBytes > deviceRAM {
            return .wontFit
        }
        if model.minRAMBytes > usableRAM {
            return .heavy
        }
        return .fits
    }

    /// Bytes the model's files take on disk, or nil when they can't be located.
    /// The SDK stores a bundle in `<flattened manifest URL>/<quantization>/`.
    private func diskSize(of model: ModelInfo) -> Int64? {
        let fm = FileManager.default
        let bundles = (try? fm.contentsOfDirectory(at: modelsRoot, includingPropertiesForKeys: nil)) ?? []
        guard let bundle = bundles.first(where: { $0.lastPathComponent.hasSuffix("_\(model.id)-GGUF") }),
              let en = fm.enumerator(
                at: bundle.appendingPathComponent(model.quantization),
                includingPropertiesForKeys: [.fileSizeKey])
        else { return nil }
        var total: Int64 = 0
        for case let url as URL in en {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total > 0 ? total : nil
    }

    /// Model weights can be downloaded again, so keep them out of device backups.
    private func excludeModelsFromBackup() {
        var root = modelsRoot
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
    }

    // MARK: - Status

    func refreshAll() {
        for model in ModelCatalog.all {
            refresh(model)
        }
    }

    /// Reads the status from disk, without touching the network. A download in
    /// flight is left untouched.
    func refresh(_ model: ModelInfo) {
        if case .downloading = statuses[model.id] { return }
        if downloader.queryStatus(model.manifestURL) == .downloaded {
            statuses[model.id] = .downloaded(sizeBytes: diskSize(of: model))
        } else {
            statuses[model.id] = .notDownloaded
        }
    }

    // MARK: - Download

    /// Downloads the model's files to disk without loading it into memory.
    /// Never throws.
    func download(_ model: ModelInfo) async {
        statuses[model.id] = .downloading(downloadedBytes: 0, totalBytes: model.approxBytes)

        do {
            _ = try await downloader.downloadModelFromManifest(model.manifestURL) { [weak self] progress, _ in
                _Concurrency.Task { @MainActor in
                    guard let self, case .downloading = self.statuses[model.id] else { return }
                    self.statuses[model.id] = .downloading(
                        downloadedBytes: Int64(progress * Double(model.approxBytes)),
                        totalBytes: model.approxBytes)
                }
            }
        } catch {
            print("[ModelManager] download failed for \(model.id): \(error.localizedDescription)")
        }

        statuses[model.id] = .notDownloaded
        refresh(model)
        excludeModelsFromBackup()
    }

    // MARK: - Delete

    func delete(_ model: ModelInfo) async {
        do {
            try downloader.removeModel(fromManifestURL: model.manifestURL)
        } catch {
            print("[ModelManager] delete failed for \(model.id): \(error.localizedDescription)")
        }
        refresh(model)
    }

    // MARK: - Helpers

    func status(for modelName: String) -> ModelDiskStatus {
        statuses[modelName] ?? .notDownloaded
    }

    static func formatBytes(_ bytes: Int64?) -> String? {
        guard let bytes, bytes > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
