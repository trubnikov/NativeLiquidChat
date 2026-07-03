import SwiftUI
import AVFoundation
import Vision

struct TrainingCameraView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var model = CameraViewModel()
    @State private var showingCustomNameInput = false
    @State private var customNameText = ""
    
    var body: some View {
        ZStack {
            // Live camera view layer
            if model.isCameraAuthorized {
                CameraPreviewView(session: model.captureSession)
                    .ignoresSafeArea()
            } else {
                Color.black
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    Text("Камере требуется разрешение")
                        .font(.headline)
                        .foregroundColor(.white)
                    Button("Разрешить доступ в Настройках") {
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsURL)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            
            // Focus overlay (Reticle in center)
            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [10, 10]))
                    .frame(width: 200, height: 200)
                    .overlay(
                        Image(systemName: "plus")
                            .foregroundColor(.white.opacity(0.4))
                            .font(.title)
                    )
                Spacer()
            }
            
            // Top Controls (Dismiss)
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        model.stopSession()
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.8))
                            .shadow(radius: 4)
                    }
                    .padding()
                }
                Spacer()
            }
            
            // Bottom Glassmorphic card
            VStack {
                Spacer()
                
                VStack(spacing: 16) {
                    if model.isAnalyzing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text("Сканирую объект...")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    } else if let matchedLabel = model.matchedLabel {
                        // Trained matched object
                        VStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.amber)
                                Text("ВЫУЧЕННЫЙ ОБЪЕКТ")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.amber)
                            }
                            
                            Text(matchedLabel)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            
                            Text("Агент узнал этот объект по сигнатуре!")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    } else if let dominantLabel = model.dominantLabel {
                        // New standard object detected
                        VStack(spacing: 12) {
                            Text("Кажется, это:")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            
                            Text(dominantLabel.replacingOccurrences(of: "_", with: " "))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            
                            Text("Я прав?")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.8))
                            
                            HStack(spacing: 20) {
                                // YES button
                                Button(action: {
                                    model.trainCurrentObject(as: dominantLabel)
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                        Text("Да, верно")
                                    }
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.green.opacity(0.8))
                                    .cornerRadius(12)
                                }
                                
                                // NO button (custom training)
                                Button(action: {
                                    customNameText = ""
                                    showingCustomNameInput = true
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "xmark.circle.fill")
                                        Text("Нет, другое")
                                    }
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.red.opacity(0.8))
                                    .cornerRadius(12)
                                }
                            }
                        }
                    } else {
                        Text("Наведите камеру на объект в рамке")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    if model.analysisTimeMs > 0 {
                        Divider()
                            .background(Color.white.opacity(0.15))
                        Text(String(format: "Скорость: %.1f мс (Vision + Similarity)", model.analysisTimeMs))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.black.opacity(0.6))
                        .background(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
                .padding()
            }
            
            // Custom Name Input Modal Dialog
            if showingCustomNameInput {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showingCustomNameInput = false
                    }
                
                VStack(spacing: 16) {
                    Text("Чему научить агента?")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Введите точное имя для этого объекта:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("Например: Кресло Босса", text: $customNameText)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .padding(.horizontal)
                    
                    HStack(spacing: 12) {
                        Button("Отмена") {
                            showingCustomNameInput = false
                        }
                        .foregroundColor(.secondary)
                        
                        Button("Запомнить") {
                            let name = customNameText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !name.isEmpty {
                                model.trainCurrentObject(as: name)
                                showingCustomNameInput = false
                                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(customNameText.isEmpty)
                    }
                }
                .padding()
                .background(Color(uiColor: .systemBackground))
                .cornerRadius(20)
                .shadow(radius: 8)
                .frame(maxWidth: 320)
            }
        }
        .onAppear {
            model.checkAuthorizationAndStart()
        }
        .onDisappear {
            model.stopSession()
        }
    }
}

class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var previewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
    
    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        backgroundColor = .black
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// SwiftUI camera preview wrapper
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> CameraPreviewUIView {
        return CameraPreviewUIView(session: session)
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
    }
}

// Color asset helper
extension Color {
    static let amber = Color(red: 1.0, green: 0.75, blue: 0.0)
}

// ViewModel to encapsulate camera capturing and analysis
class CameraViewModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var isCameraAuthorized = false
    @Published var isAnalyzing = false
    @Published var dominantLabel: String? = nil
    @Published var matchedLabel: String? = nil
    @Published var analysisTimeMs: Double = 0.0
    
    let captureSession = AVCaptureSession()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let cameraQueue = DispatchQueue(label: "camera.frame.processing")
    
    private var lastAnalysisTime: Date = .distantPast
    private var currentClassifications: [String: Double] = [:]
    
    func checkAuthorizationAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.isCameraAuthorized = true
            setupAndStartSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.isCameraAuthorized = granted
                    if granted {
                        self.setupAndStartSession()
                    }
                }
            }
        default:
            self.isCameraAuthorized = false
        }
    }
    
    private func setupAndStartSession() {
        guard !captureSession.isRunning else { return }
        
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .hd1280x720
        
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            print("Failed to access camera device.")
            captureSession.commitConfiguration()
            return
        }
        
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }
        
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: cameraQueue)
        
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        }
        
        captureSession.commitConfiguration()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }
    
    func stopSession() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }
    
    func trainCurrentObject(as name: String) {
        guard !currentClassifications.isEmpty else { return }
        TrainedObjectsManager.shared.train(customLabel: name, classifications: currentClassifications)
        // Refresh local matching state
        matchedLabel = name
    }
    
    // SampleBuffer Delegate to analyze frames at 1Hz throttle rate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastAnalysisTime) >= 1.0 else { return }
        lastAnalysisTime = now
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Build image request handler on pixel buffer
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        let classificationRequest = VNClassifyImageRequest { [weak self] request, error in
            guard let self = self else { return }
            guard error == nil,
                  let results = request.results as? [VNClassificationObservation] else {
                return
            }
            
            // Map top 10 categories with confidence > 1%
            let mappedVec = results
                .filter { $0.confidence > 0.01 }
                .prefix(10)
                .reduce(into: [String: Double]()) { dict, item in
                    dict[item.identifier] = Double(item.confidence)
                }
            
            DispatchQueue.main.async {
                self.currentClassifications = mappedVec
                
                // 1. Run local similarity vector matching against trained objects
                if let match = TrainedObjectsManager.shared.findMatch(for: mappedVec) {
                    self.matchedLabel = match
                    self.dominantLabel = nil
                } else {
                    // 2. Fall back to dominant Apple Vision prediction
                    self.matchedLabel = nil
                    if let firstResult = results.first(where: { $0.confidence > 0.02 }) {
                        // Extract first segment of comma-separated VN identifier
                        let name = firstResult.identifier.components(separatedBy: ",").first ?? firstResult.identifier
                        self.dominantLabel = name.capitalized
                    } else {
                        self.dominantLabel = nil
                    }
                }
                self.isAnalyzing = false
            }
        }
        
        // Focus the classification on the central rect to align with the reticle
        classificationRequest.regionOfInterest = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        
        DispatchQueue.main.async {
            self.isAnalyzing = true
        }
        
        let startTime = Date()
        do {
            try requestHandler.perform([classificationRequest])
            let duration = Date().timeIntervalSince(startTime) * 1000.0
            DispatchQueue.main.async {
                self.analysisTimeMs = duration
            }
        } catch {
            print("Failed to run real-time camera classification: \(error)")
            DispatchQueue.main.async {
                self.isAnalyzing = false
            }
        }
    }
}
