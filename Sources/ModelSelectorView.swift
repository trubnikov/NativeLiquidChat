import SwiftUI

struct ModelSelectorView: View {
    let currentModel: String
    let isModelLoading: Bool
    let downloadProgress: Double
    let onSelect: (String) -> Void
    
    let availableModels = [
        ("LFM2.5-1.2B-Instruct", "Text generation, 46 t/s", "cpu"),
        ("LFM2.5-VL-1.6B", "Vision & Multimodal", "eye"),
        ("LFM2.5-Audio-1.5B", "Audio & Voice tasks", "waveform")
    ]
    
    var body: some View {
        Menu {
            ForEach(availableModels, id: \.0) { model in
                Button(action: {
                    onSelect(model.0)
                }) {
                    HStack {
                        Image(systemName: model.2)
                        VStack(alignment: .leading) {
                            Text(model.0)
                            Text(model.1)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if currentModel == model.0 {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .foregroundColor(isModelLoading ? .orange : .blue)
                
                Text(currentModel)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if isModelLoading {
                    if downloadProgress > 0 && downloadProgress < 1.0 {
                        Text("\(Int(downloadProgress * 100))%")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    } else {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                } else {
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .cornerRadius(16)
        }
    }
}
