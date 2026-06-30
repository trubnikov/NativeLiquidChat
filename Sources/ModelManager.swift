import SwiftUI
import LeapSDK
import LeapModelDownloader

/// Ollama-style local model library: download to disk, query status, delete,
/// and activate (load into memory).
///
/// Downloads go through the high-level `Leap.shared.load` API, which resolves
/// and fetches the model with *catchable* Swift errors. The low-level
/// `ModelDownloader` is used only for read/delete operations on already-known
/// models, each wrapped in `do/catch` so a backend failure degrades gracefully
/// instead of crashing the process.
@Observable
@MainActor
final class ModelManager {
    private(set) var statuses: [String: ModelDiskStatus] = [:]

    private let downloader: ModelDownloader
    /// Root directory where `Leap.shared.load` stores models — must match the
    /// SDK default (`<Documents>/leap_models`) so on-disk status reads find them.
    private let modelsRoot: URL

    /// Total physical RAM of the device.
    let deviceRAM: Int64 = Int64(ProcessInfo.processInfo.physicalMemory)

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.modelsRoot = docs.appendingPathComponent("leap_models")
        let config = LeapModelDownloader.LeapDownloaderConfig.with(saveDir: modelsRoot.path)
        self.downloader = ModelDownloader(config: config)

        for model in ModelCatalog.all {
            statuses[model.id] = .notDownloaded
        }
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
        let onDisk = isOnDisk(model)
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

    /// Sum of file sizes for a model's on-disk folder (e.g. `LFM2.5-VL-1.6B-Q4_0`).
    private func diskSize(of model: ModelInfo) -> Int64 {
        let folder = modelsRoot.appendingPathComponent("\(model.id)-\(model.quantization)")
        guard let en = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in en {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }

    /// True when the model's `.gguf` weights are present on disk.
    private func isOnDisk(_ model: ModelInfo) -> Bool {
        let folder = modelsRoot.appendingPathComponent("\(model.id)-\(model.quantization)")
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
        else { return false }
        return files.contains { $0.hasSuffix(".gguf") }
    }

    // MARK: - Status

    func refreshAll() {
        for model in ModelCatalog.all {
            refresh(model)
        }
    }

    /// Determines status straight from disk — robust and crash-free (no URL
    /// resolution). A download in flight is left untouched.
    func refresh(_ model: ModelInfo) {
        if case .downloading = statuses[model.id] { return }
        if isOnDisk(model) {
            statuses[model.id] = .downloaded(sizeBytes: diskSize(of: model))
        } else {
            statuses[model.id] = .notDownloaded
        }
    }

    // MARK: - Download

    /// Downloads the model to disk via the high-level Leap API. Because that API
    /// doesn't stream incremental progress, a poller watches the on-disk folder
    /// size and reports it against the catalog's estimate. Never throws.
    func download(_ model: ModelInfo) async {
        statuses[model.id] = .downloading(downloadedBytes: 0, totalBytes: model.approxBytes)

        // Poll the folder size on disk while the fetch runs.
        let poller = _Concurrency.Task { @MainActor [weak self] in
            while !_Concurrency.Task.isCancelled {
                guard let self else { return }
                if case .downloading = self.statuses[model.id] {
                    let done = self.diskSize(of: model)
                    self.statuses[model.id] = .downloading(
                        downloadedBytes: done, totalBytes: model.approxBytes)
                }
                try? await _Concurrency.Task.sleep(nanoseconds: 700_000_000)
            }
        }

        do {
            let options = LeapSDK.LiquidInferenceEngineManifestOptions()
            let runner = try await Leap.shared.load(
                model: model.id,
                quantization: model.quantization,
                options: options
            )
            _ = runner   // only wanted it on disk; release the in-memory runner
            poller.cancel()
            refresh(model)
        } catch {
            print("[ModelManager] download failed for \(model.id): \(error.localizedDescription)")
            poller.cancel()
            refresh(model)
        }
    }

    // MARK: - Delete

    func delete(_ model: ModelInfo) async {
        let folder = modelsRoot.appendingPathComponent("\(model.id)-\(model.quantization)")
        // Remove the on-disk folder directly; fall back to the SDK if needed.
        if FileManager.default.fileExists(atPath: folder.path) {
            do {
                try FileManager.default.removeItem(at: folder)
            } catch {
                print("[ModelManager] file delete failed for \(model.id): \(error.localizedDescription)")
            }
        }
        do {
            try await downloader.removeModel(
                modelName: model.id, quantizationType: model.quantization)
        } catch {
            // Folder may already be gone; that's fine.
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
