import SwiftUI

/// LM-Studio-style model library: browse models grouped by type, see size and
/// whether each fits this device, then download / activate / delete.
struct ModelsView: View {
    @Bindable var store: ChatStore
    @Bindable var models: ModelManager
    @Environment(\.dismiss) private var dismiss

    private var grouped: [(ModelInfo.Kind, [ModelInfo])] {
        let kinds: [ModelInfo.Kind] = [.text, .vision, .audio]
        return kinds.compactMap { kind in
            let items = ModelCatalog.all.filter { $0.kind == kind }
            return items.isEmpty ? nil : (kind, items)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // Device capacity summary
                Section {
                    LabeledContent("Device memory",
                                   value: ModelManager.formatBytes(models.deviceRAM) ?? "—")
                    LabeledContent("Free storage",
                                   value: ModelManager.formatBytes(models.freeDiskBytes) ?? "—")
                } header: {
                    Text("This device")
                } footer: {
                    Text("Models run entirely on-device. A model needs enough free storage to download and enough memory to run.")
                }

                ForEach(grouped, id: \.0) { kind, items in
                    Section(kind.displayName) {
                        ForEach(items) { model in
                            ModelRow(
                                model: model,
                                status: models.status(for: model.id),
                                fit: models.fit(for: model),
                                isActive: store.loadedModelName == model.id,
                                isLoadingActive: store.isModelLoading && store.loadedModelName == nil,
                                onDownload: { Task { await models.download(model) } },
                                onDelete: { Task { await models.delete(model) } },
                                onActivate: { Task { _ = await store.ensureModelLoaded(for: model.id) } }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { models.refreshAll() }
            .refreshable { models.refreshAll() }
        }
    }
}

private struct ModelRow: View {
    let model: ModelInfo
    let status: ModelDiskStatus
    let fit: ModelFit
    let isActive: Bool
    let isLoadingActive: Bool
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onActivate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Image(systemName: model.kind.iconName).font(.system(size: 20))
                    .foregroundStyle(isActive ? AnyShapeStyle(DS.onAccent) : AnyShapeStyle(.secondary))
                    .frame(width: 40, height: 40)
                    .background(isActive ? AnyShapeStyle(DS.accentGradient) : AnyShapeStyle(DS.surfaceElevated),
                                in: RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.body.weight(.semibold))
                        if isActive {
                            Text("ACTIVE")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.tint, in: Capsule())
                        }
                    }
                    Text(model.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                trailing
            }

            // Size + compatibility line
            HStack(spacing: 10) {
                Label(sizeText, systemImage: "internaldrive")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                fitBadge
            }
            .padding(.leading, 44)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            if case .downloaded = status {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var sizeText: String {
        if case .downloaded(let size) = status, let s = ModelManager.formatBytes(size) {
            return s
        }
        return ModelManager.formatBytes(model.approxBytes) ?? "—"
    }

    @ViewBuilder
    private var fitBadge: some View {
        let color: Color = {
            switch fit {
            case .fits: return .green
            case .heavy: return .orange
            case .wontFit, .noSpace: return .red
            }
        }()
        Label(fit.label, systemImage: fit.systemImage)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
    }

    @ViewBuilder
    private var trailing: some View {
        switch status {
        case .notDownloaded:
            if fit == .wontFit || fit == .noSpace {
                Image(systemName: fit.systemImage)
                    .foregroundStyle(.red)
            } else {
                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle").font(.system(size: 18))
                        .foregroundStyle(.tint)
                        .frame(width: 36, height: 36)
                        .background(DS.surfaceElevated, in: Circle())
                }
                .buttonStyle(.borderless)
            }

        case .downloading(let done, _):
            VStack(alignment: .trailing, spacing: 4) {
                if done > 0 {
                    ProgressView(value: status.progress)
                        .progressViewStyle(.linear)
                        .frame(width: 90)
                    Text("\(Int(status.progress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: status.progress)
                } else {
                    ProgressView()
                    Text("Preparing…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

        case .downloaded:
            if isActive {
                Image(systemName: "checkmark").font(.system(size: 18))
                    .foregroundStyle(.tint)
            } else if isLoadingActive {
                ProgressView()
            } else {
                Button("Activate", action: onActivate)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}
