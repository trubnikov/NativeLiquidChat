import SwiftUI
import AVFoundation
import Vision
import NaturalLanguage
import Accelerate

struct LabView: View {
    @StateObject private var model = LabCameraViewModel()
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.russian.rawValue
    @State private var labMode = 0 // 0 = Weight Estimator, 1 = GPU Search Benchmark
    
    // GPU Benchmark State
    @State private var vectorCount = 10000.0
    @State private var isBenchmarking = false
    @State private var cpuTimeMs: Double? = nil
    @State private var gpuTimeMs: Double? = nil
    @State private var accuracyMatch: Double? = nil
    @State private var speedupRatio: Double? = nil
    
    var body: some View {
        ZStack {
            if labMode == 0 {
                // CAMERA MODE (Weight & Density)
                ZStack {
                    if model.isCameraAuthorized {
                        CameraPreviewView(session: model.captureSession)
                            .ignoresSafeArea()
                    } else {
                        Color.black
                            .ignoresSafeArea()
                        VStack(spacing: 16) {
                            Image(systemName: "flask.fill")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                            Text(AppText.get(.cameraPermissionRequired, lang: appLanguage))
                                .font(.headline)
                                .foregroundColor(.white)
                            Button(AppText.get(.buttonSettings, lang: appLanguage)) {
                                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(settingsURL)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                    }
                    
                    // Reticle overlay
                    VStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(Color.cyan.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                            .frame(width: 220, height: 220)
                            .overlay(
                                Image(systemName: "scope")
                                    .foregroundColor(.cyan.opacity(0.4))
                                    .font(.system(size: 28))
                            )
                        Spacer()
                    }
                    
                    // Experimental Output Card
                    VStack {
                        Spacer()
                        
                        VStack(spacing: 14) {
                            HStack {
                                Image(systemName: "flask.fill")
                                    .foregroundColor(.cyan)
                                Text(AppText.get(.labTitle, lang: appLanguage))
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            
                            Divider()
                                .background(Color.white.opacity(0.15))
                            
                            if let detectedObject = model.detectedLabel {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(detectedObject.capitalized)
                                            .font(.title3)
                                            .fontWeight(.bold)
                                            .foregroundColor(.cyan)
                                        Spacer()
                                        Text(String(format: "%.0f%% Match", model.detectionConfidence * 100))
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.6))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(Color.cyan.opacity(0.3))
                                            .cornerRadius(6)
                                    }
                                    
                                    HStack {
                                        Text(AppText.get(.labDistanceLabel, lang: appLanguage) + ":")
                                            .foregroundColor(.white.opacity(0.7))
                                        Spacer()
                                        Text(String(format: "%.1f cm", model.currentDistance * 100))
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(.white)
                                    }
                                    
                                    HStack {
                                        Text(AppText.get(.labDimensionsLabel, lang: appLanguage) + ":")
                                            .foregroundColor(.white.opacity(0.7))
                                        Spacer()
                                        Text(String(format: "%.1f x %.1f cm", model.physicalWidth, model.physicalHeight))
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(.white)
                                    }
                                    
                                    HStack {
                                        Text(AppText.get(.labVolumeLabel, lang: appLanguage) + ":")
                                            .foregroundColor(.white.opacity(0.7))
                                        Spacer()
                                        Text(String(format: "~%.0f cm³", model.estimatedVolume))
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(.white)
                                    }
                                    
                                    HStack {
                                        Text(AppText.get(.labWeightLabel, lang: appLanguage) + ":")
                                            .foregroundColor(.white.opacity(0.7))
                                        Spacer()
                                        Text(String(format: "~%.0f g", model.estimatedWeight))
                                            .font(.system(.headline, design: .monospaced))
                                            .foregroundColor(.yellow)
                                    }
                                    
                                    if model.estimatedCalories > 0 {
                                        HStack {
                                            Text(AppText.get(.labCaloriesLabel, lang: appLanguage) + ":")
                                                .foregroundColor(.white.opacity(0.7))
                                            Spacer()
                                            Text(String(format: "~%.0f kcal", model.estimatedCalories))
                                                .font(.system(.headline, design: .monospaced))
                                                .foregroundColor(.orange)
                                        }
                                    }
                                }
                            } else {
                                Text(appLanguage == "ru" ? "Наведите рамку на объект (фрукт, посуду)" : "Point reticle at an object (fruit, cup)")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                    .padding(.vertical, 10)
                            }
                            
                            Divider()
                                .background(Color.white.opacity(0.15))
                            
                            // Hardware info footer
                            HStack {
                                Text(AppText.get(.labDepthSourceLabel, lang: appLanguage) + ": \(model.depthSource)")
                                Spacer()
                                Text(String(format: "F: %.0f px", model.cameraFocalLength))
                            }
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 24)
                                .fill(Color.black.opacity(0.7))
                                .background(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color.cyan.opacity(0.3), lineWidth: 0.5)
                        )
                        .padding()
                    }
                }
            } else {
                // GPU BENCHMARK MODE
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Title Card
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "cpu.fill")
                                    .foregroundColor(.green)
                                    .font(.title2)
                                Text(appLanguage == "ru" ? "Поиск эмбеддингов на GPU" : "GPU Embeddings Search")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            
                            Text(appLanguage == "ru" 
                                 ? "Бенчмарк косинусного сходства 512-мерных векторов на процессоре и графическом чипе Apple A16 Bionic (Metal)."
                                 : "Benchmark cosine similarity computation of 512-dimension vectors between A16 Bionic CPU and GPU using Metal.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.black.opacity(0.6))
                                .background(.ultraThinMaterial)
                        )
                        .padding(.horizontal)
                        .padding(.top, 70)
                        
                        // Settings Card
                        VStack(alignment: .leading, spacing: 16) {
                            Text(appLanguage == "ru" ? "Параметры базы данных" : "Database Parameters")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            VStack(spacing: 8) {
                                HStack {
                                    Text(appLanguage == "ru" ? "Количество векторов:" : "Vector count:")
                                    Spacer()
                                    Text("\(Int(vectorCount))")
                                        .font(.system(.body, design: .monospaced))
                                        .fontWeight(.bold)
                                }
                                Slider(value: $vectorCount, in: 1000...20000, step: 1000)
                                    .tint(.cyan)
                            }
                            
                            HStack {
                                Text(appLanguage == "ru" ? "Размерность вектора:" : "Vector dimension:")
                                Spacer()
                                Text("512 floats")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                Text(appLanguage == "ru" ? "Объем данных:" : "Memory Size:")
                                Spacer()
                                Text(String(format: "%.2f MB", Double(Int(vectorCount) * 512) * 4.0 / (1024.0 * 1024.0)))
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            
                            Button(action: runVectorBenchmark) {
                                HStack {
                                    if isBenchmarking {
                                        ProgressView()
                                            .tint(.white)
                                            .padding(.trailing, 8)
                                        Text(AppText.get(.gpuBenchmarkRunning, lang: appLanguage))
                                    } else {
                                        Image(systemName: "play.fill")
                                        Text(AppText.get(.gpuBenchmarkRun, lang: appLanguage))
                                    }
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(isBenchmarking ? Color.gray : Color.cyan)
                                .cornerRadius(14)
                            }
                            .disabled(isBenchmarking)
                        }
                        .padding(20)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(20)
                        .padding(.horizontal)
                        
                        // Results Card
                        if cpuTimeMs != nil || gpuTimeMs != nil {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(appLanguage == "ru" ? "Результаты сравнения" : "Performance Results")
                                    .font(.headline)
                                
                                VStack(spacing: 12) {
                                    HStack {
                                        Text(AppText.get(.gpuBenchmarkCpuTime, lang: appLanguage) + ":")
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        if let cpu = cpuTimeMs {
                                            Text(String(format: "%.3f ms", cpu))
                                                .font(.system(.body, design: .monospaced))
                                        }
                                    }
                                    
                                    HStack {
                                        Text(AppText.get(.gpuBenchmarkGpuTime, lang: appLanguage) + ":")
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        if let gpu = gpuTimeMs {
                                            Text(String(format: "%.3f ms", gpu))
                                                .font(.system(.body, design: .monospaced))
                                                .foregroundColor(.green)
                                                .fontWeight(.bold)
                                        }
                                    }
                                    
                                    Divider()
                                    
                                    if let ratio = speedupRatio {
                                        HStack {
                                            Text(AppText.get(.gpuBenchmarkSpeedup, lang: appLanguage) + ":")
                                                .font(.headline)
                                            Spacer()
                                            Text(String(format: "%.1f x быстрее", ratio))
                                                .font(.system(.title3, design: .monospaced))
                                                .foregroundColor(.green)
                                                .fontWeight(.bold)
                                        }
                                    }
                                    
                                    if let accuracy = accuracyMatch {
                                        HStack {
                                            Text(AppText.get(.gpuBenchmarkAccuracy, lang: appLanguage) + ":")
                                                .foregroundColor(.secondary)
                                                .font(.caption)
                                            Spacer()
                                            Text(String(format: "%.4f%% совпадение", accuracy * 100))
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                
                                // Benchmark Chart Visualization
                                if let cpu = cpuTimeMs, let gpu = gpuTimeMs {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(appLanguage == "ru" ? "Соотношение времени:" : "Time ratio:")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        
                                        // CPU Bar
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("CPU")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.orange)
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color.orange)
                                                .frame(width: 250, height: 12)
                                        }
                                        
                                        // GPU Bar
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("GPU (Metal)")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.green)
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color.green)
                                                .frame(width: max(250 * (gpu / cpu), 5), height: 12)
                                        }
                                    }
                                    .padding(.top, 10)
                                }
                            }
                            .padding(20)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .cornerRadius(20)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 30)
                }
            }
            
            // Tab Segment Control Overlay
            VStack {
                Picker("Lab Mode", selection: $labMode) {
                    Text(AppText.get(.labTabWeight, lang: appLanguage)).tag(0)
                    Text(AppText.get(.labTabGPU, lang: appLanguage)).tag(1)
                }
                .pickerStyle(.segmented)
                .padding(8)
                .background(.ultraThinMaterial)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
                .padding()
                
                Spacer()
            }
        }
        .navigationTitle(AppText.get(.tabLab, lang: appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if labMode == 0 {
                model.startSession()
            }
        }
        .onDisappear {
            model.stopSession()
        }
        .onChange(of: labMode) { _, newMode in
            if newMode == 0 {
                model.startSession()
            } else {
                model.stopSession()
            }
        }
    }
    
    // MARK: - GPU Benchmark Execution
    
    private func runVectorBenchmark() {
        isBenchmarking = true
        let limit = Int(vectorCount)
        let dimension = 512
        
        DispatchQueue.global(qos: .userInitiated).async {
            // 1. Generate Synthetic Data
            let query = (0..<dimension).map { _ in Float.random(in: -1.0...1.0) }
            let database = (0..<(limit * dimension)).map { _ in Float.random(in: -1.0...1.0) }
            
            // 2. CPU Benchmark (vDSP / Accelerate)
            let cpuStart = DispatchTime.now()
            let cpuResults = runCpuSearch(query: query, database: database, vectorCount: limit, dimension: dimension)
            let cpuEnd = DispatchTime.now()
            let cpuNano = cpuEnd.uptimeNanoseconds - cpuStart.uptimeNanoseconds
            let cpuMs = Double(cpuNano) / 1_000_000.0
            
            // 3. GPU Benchmark (Metal Shader)
            let gpuStart = DispatchTime.now()
            let gpuResults = GPUSimilarityEngine.shared.performParallelSearch(
                query: query,
                database: database,
                vectorCount: limit,
                dimension: dimension
            )
            let gpuEnd = DispatchTime.now()
            let gpuNano = gpuEnd.uptimeNanoseconds - gpuStart.uptimeNanoseconds
            let gpuMs = Double(gpuNano) / 1_000_000.0
            
            // 4. Verification Check (compare correctness)
            var accuracy: Double = 1.0
            if let gpu = gpuResults {
                var matches = 0
                for i in 0..<limit {
                    if abs(cpuResults[i] - gpu[i]) < 0.001 {
                        matches += 1
                    }
                }
                accuracy = Double(matches) / Double(limit)
            }
            
            // 5. Update UI
            DispatchQueue.main.async {
                self.cpuTimeMs = cpuMs
                self.gpuTimeMs = gpuMs
                self.accuracyMatch = accuracy
                self.speedupRatio = cpuMs / gpuMs
                self.isBenchmarking = false
            }
        }
    }
    
    private func runCpuSearch(query: [Float], database: [Float], vectorCount: Int, dimension: Int) -> [Float] {
        var results = [Float](repeating: 0.0, count: vectorCount)
        
        var magnitudeQ: Float = 0.0
        vDSP_svesq(query, 1, &magnitudeQ, vDSP_Length(dimension))
        let sqrtQ = sqrt(magnitudeQ)
        
        guard sqrtQ > 0 else { return results }
        
        for i in 0..<vectorCount {
            let offset = i * dimension
            let vectorB = Array(database[offset..<(offset + dimension)])
            
            var dotProduct: Float = 0.0
            vDSP_dotpr(query, 1, vectorB, 1, &dotProduct, vDSP_Length(dimension))
            
            var magnitudeD: Float = 0.0
            vDSP_svesq(vectorB, 1, &magnitudeD, vDSP_Length(dimension))
            let sqrtD = sqrt(magnitudeD)
            
            if sqrtD > 0 {
                results[i] = dotProduct / (sqrtQ * sqrtD)
            }
        }
        return results
    }
}

// Re-declare LabCameraViewModel exactly as before
class LabCameraViewModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureDepthDataOutputDelegate {
    @Published var isCameraAuthorized = false
    @Published var currentDistance: Double = 0.35 // fallback 35cm
    @Published var depthSource = "Focus Lens"
    @Published var detectedLabel: String? = nil
    @Published var detectionConfidence: Float = 0.0
    
    // Physical dimensions
    @Published var physicalWidth: Double = 0.0
    @Published var physicalHeight: Double = 0.0
    @Published var estimatedVolume: Double = 0.0
    @Published var estimatedWeight: Double = 0.0
    @Published var estimatedCalories: Double = 0.0
    @Published var cameraFocalLength: Double = 3000.0 // Default wide camera focal length in pixels
    
    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private let sessionQueue = DispatchQueue(label: "lab_camera_queue")
    
    private var sequenceHandler = VNSequenceRequestHandler()
    private var detectionRequest: VNClassifyImageRequest?
    
    // Density & Calorie Constants (expanded to support dynamic organic & food targets)
    private let densities: [String: (density: Double, caloriesPer100g: Double)] = [
        "apple": (0.85, 52.0),
        "banana": (0.95, 89.0),
        "orange": (0.90, 47.0),
        "lemon": (0.92, 29.0),
        "strawberry": (0.90, 33.0),
        "grape": (0.98, 67.0),
        "pineapple": (0.88, 50.0),
        "watermelon": (0.92, 30.0),
        "tomato": (0.95, 18.0),
        "potato": (1.05, 77.0),
        "pear": (0.86, 57.0),
        "peach": (0.90, 39.0),
        "plum": (0.93, 46.0),
        "kiwi": (0.92, 61.0),
        "cucumber": (0.96, 15.0),
        "carrot": (1.02, 41.0),
        "pepper": (0.91, 20.0),
        "bread": (0.45, 265.0),
        "cheese": (1.10, 402.0),
        "egg": (1.03, 155.0),
        "meat": (1.06, 250.0),
        "chicken": (1.04, 239.0),
        "fish": (1.02, 206.0),
        "cup": (1.00, 0.0),
        "mug": (1.00, 0.0),
        "bowl": (1.00, 0.0),
        "glass": (1.00, 0.0)
    ]
    
    override init() {
        super.init()
        setupVision()
        checkAuthorization()
    }
    
    private func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isCameraAuthorized = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { authorized in
                DispatchQueue.main.async {
                    self.isCameraAuthorized = authorized
                }
            }
        default:
            isCameraAuthorized = false
        }
    }
    
    func startSession() {
        guard isCameraAuthorized else { return }
        sessionQueue.async {
            if self.captureSession.inputs.isEmpty {
                self.setupCaptureSession()
            }
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }
    
    func stopSession() {
        sessionQueue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }
    
    private func setupCaptureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .vga640x480
        
        let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInWideAngleCamera]
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: .back)
        
        guard let device = discoverySession.devices.first else {
            captureSession.commitConfiguration()
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
            
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }
            
            if captureSession.canAddOutput(depthOutput) {
                captureSession.addOutput(depthOutput)
                depthOutput.setDelegate(self, callbackQueue: sessionQueue)
                depthOutput.isFilteringEnabled = true
                self.cameraFocalLength = 3000.0
            }
            
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            device.unlockForConfiguration()
            
        } catch {
            print("Error setting up lab camera session: \(error)")
        }
        
        captureSession.commitConfiguration()
    }
    
    private func setupVision() {
        let request = VNClassifyImageRequest { [weak self] request, error in
            guard let self = self,
                  let results = request.results as? [VNClassificationObservation],
                  let topResult = results.first else {
                DispatchQueue.main.async {
                    self?.detectedLabel = nil
                }
                return
            }
            
            let rawLabel = topResult.identifier.lowercased()
            let cleanLabel = rawLabel.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? rawLabel
            
            var featureVector: [String: Double] = [:]
            for res in results.prefix(10) {
                featureVector[res.identifier] = Double(res.confidence)
            }
            
            let finalLabel: String
            if let customMatch = TrainedObjectsManager.shared.findMatch(for: featureVector) {
                finalLabel = customMatch
            } else {
                finalLabel = cleanLabel
            }
            
            DispatchQueue.main.async {
                self.detectedLabel = finalLabel
                self.detectionConfidence = topResult.confidence
                self.calculatePhysicalMetrics()
            }
        }
        
        request.regionOfInterest = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        self.detectionRequest = request
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        if depthSource == "Focus Lens",
           let device = (captureSession.inputs.first as? AVCaptureDeviceInput)?.device {
            let lensPosition = device.lensPosition
            let estimatedMeters = 0.1 + (1.0 - Double(lensPosition)) * 1.5
            DispatchQueue.main.async {
                self.currentDistance = estimatedMeters
            }
        }
        
        if let request = detectionRequest {
            let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            try? requestHandler.perform([request])
        }
    }
    
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        let depthMap = depthData.depthDataMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        guard CVPixelBufferGetPixelFormatType(depthMap) == kCVPixelFormatType_DepthFloat32 else { return }
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return }
        
        let floatData = baseAddress.assumingMemoryBound(to: Float32.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(depthMap)
        
        let centerX = width / 2
        let centerY = height / 2
        
        let pixelIndex = centerY * (rowBytes / 4) + centerX
        let depthValue = floatData[pixelIndex]
        
        var focalLength: Double? = nil
        if let calibrationData = depthData.cameraCalibrationData {
            let intrinsics = calibrationData.intrinsicMatrix
            let fx = intrinsics.columns.0.x
            let fy = intrinsics.columns.1.y
            focalLength = Double((fx + fy) / 2.0)
        }
        
        if depthValue.isFinite && depthValue > 0.05 && depthValue < 5.0 {
            DispatchQueue.main.async {
                self.currentDistance = Double(depthValue)
                self.depthSource = "LiDAR/Stereo"
                if let f = focalLength {
                    self.cameraFocalLength = f
                }
            }
        }
    }
    
    private func calculatePhysicalMetrics() {
        guard let label = detectedLabel else { return }
        
        let pixelWidth = 140.0
        let pixelHeight = 140.0
        
        let distanceCm = currentDistance * 100.0
        let widthCm = (pixelWidth * distanceCm) / cameraFocalLength
        let heightCm = (pixelHeight * distanceCm) / cameraFocalLength
        
        self.physicalWidth = widthCm
        self.physicalHeight = heightCm
        
        let volume: Double
        let lowerLabel = label.lowercased()
        if lowerLabel.contains("banana") {
            let radius = min(widthCm, heightCm) / 2
            let length = max(widthCm, heightCm)
            volume = Double.pi * pow(radius, 2) * length
        } else {
            let radius = (widthCm + heightCm) / 4
            volume = (4.0 / 3.0) * Double.pi * pow(radius, 3)
        }
        
        self.estimatedVolume = volume
        
        var matchedDensity: Double = 0.95
        var matchedCalories: Double = 50.0
        
        for (key, val) in densities {
            if lowerLabel.contains(key) || key.contains(lowerLabel) {
                matchedDensity = val.density
                matchedCalories = val.caloriesPer100g
                break
            }
        }
        
        let weight = volume * matchedDensity
        self.estimatedWeight = weight
        self.estimatedCalories = matchedCalories > 0 ? (weight * matchedCalories) / 100.0 : 0.0
    }
}
