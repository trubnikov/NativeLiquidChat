import SwiftUI
import AVFoundation
import Vision
import NaturalLanguage

struct LabView: View {
    @StateObject private var model = LabCameraViewModel()
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.russian.rawValue
    
    var body: some View {
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
                        Text(appLanguage == "ru" ? "Наведите рамку на фрукт (яблоко, банан, апельсин, лимон)" : "Point reticle at a fruit (apple, banana, orange, lemon)")
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
        .navigationTitle(AppText.get(.tabLab, lang: appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            model.startSession()
        }
        .onDisappear {
            model.stopSession()
        }
    }
}

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
    private var detectionRequest: VNCoreMLRequest?
    
    // Density & Calorie Constants
    private let densities: [String: (density: Double, caloriesPer100g: Double)] = [
        "apple": (0.85, 52.0),
        "banana": (0.95, 89.0),
        "orange": (0.90, 47.0),
        "lemon": (0.92, 29.0),
        "cup": (1.00, 65.0)
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
        captureSession.sessionPreset = .vga640x480 // VGA is highly efficient and standard for CV
        
        // Use back dual/triple/wide camera that supports depth if available
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
            
            // Video Output
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }
            
            // Try adding Depth Output
            if captureSession.canAddOutput(depthOutput) {
                captureSession.addOutput(depthOutput)
                depthOutput.setDelegate(self, callbackQueue: sessionQueue)
                depthOutput.isFilteringEnabled = true
                self.cameraFocalLength = 3000.0 // Default fallback wide lens focal length
            }
            
            // Enable auto-focus monitoring to calculate distance from lensPosition if LiDAR fails
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
        // Load on-device MobileNetV2 or similar classifier
        guard let modelURL = Bundle.main.url(forResource: "MobileNetV2", withExtension: "mlmodelc"),
              let coreMLModel = try? MLModel(contentsOf: modelURL),
              let visionModel = try? VNCoreMLModel(for: coreMLModel) else {
            print("Failed to load MobileNetV2 CoreML model.")
            return
        }
        
        let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
            guard let self = self,
                  let results = request.results as? [VNClassificationObservation],
                  let topResult = results.first(where: {
                      let label = $0.identifier.lowercased()
                      return label.contains("apple") || label.contains("banana") || label.contains("orange") || label.contains("lemon") || label.contains("cup")
                  }) else {
                DispatchQueue.main.async {
                    self?.detectedLabel = nil
                }
                return
            }
            
            // Map VN identifier to simplified keys
            let matchedLabel: String
            let id = topResult.identifier.lowercased()
            if id.contains("apple") { matchedLabel = "apple" }
            else if id.contains("banana") { matchedLabel = "banana" }
            else if id.contains("orange") { matchedLabel = "orange" }
            else if id.contains("lemon") { matchedLabel = "lemon" }
            else { matchedLabel = "cup" }
            
            DispatchQueue.main.async {
                self.detectedLabel = matchedLabel
                self.detectionConfidence = topResult.confidence
                self.calculatePhysicalMetrics()
            }
        }
        
        // Run classification strictly on the central focus region
        request.regionOfInterest = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        self.detectionRequest = request
    }
    
    // MARK: - AVCaptureVideoDataOutputDelegate
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Extract lens position to estimate distance if depth map is unavailable
        if depthSource == "Focus Lens",
           let device = (captureSession.inputs.first as? AVCaptureDeviceInput)?.device {
            let lensPosition = device.lensPosition
            // Map lensPosition (0.0 to 1.0) to distance in meters
            // Close focus (1.0) -> ~10cm. Far focus (0.0) -> ~2 meters.
            let estimatedMeters = 0.1 + (1.0 - Double(lensPosition)) * 1.5
            DispatchQueue.main.async {
                self.currentDistance = estimatedMeters
            }
        }
        
        if let request = detectionRequest {
            try? sequenceHandler.perform([request], on: pixelBuffer)
        }
    }
    
    // MARK: - AVCaptureDepthDataOutputDelegate
    
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
        
        // Get depth in center
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
    
    // MARK: - Physical Metric Calculations
    
    private func calculatePhysicalMetrics() {
        guard let label = detectedLabel else { return }
        
        // 1. Get width/height in pixels from framing box
        // For VGA (640x480) focus box is 220x220, let's assume average object diameter occupies 140 pixels
        let pixelWidth = 140.0
        let pixelHeight = 140.0
        
        // 2. Physical size calculation (in cm): Size = (PixelSize * Distance) / FocalLength
        let distanceCm = currentDistance * 100.0
        let widthCm = (pixelWidth * distanceCm) / cameraFocalLength
        let heightCm = (pixelHeight * distanceCm) / cameraFocalLength
        
        self.physicalWidth = widthCm
        self.physicalHeight = heightCm
        
        // 3. Volume approximation (in cm³)
        let volume: Double
        if label == "banana" {
            // Cylinder: V = pi * r^2 * h
            let radius = min(widthCm, heightCm) / 2
            let length = max(widthCm, heightCm)
            volume = Double.pi * pow(radius, 2) * length
        } else {
            // Sphere: V = 4/3 * pi * r^3
            let radius = (widthCm + heightCm) / 4
            volume = (4.0 / 3.0) * Double.pi * pow(radius, 3)
        }
        
        self.estimatedVolume = volume
        
        // 4. Weight estimation: Weight = Volume * Density
        if let constants = densities[label] {
            let weight = volume * constants.density
            self.estimatedWeight = weight
            
            // 5. Calories calculation
            self.estimatedCalories = (weight * constants.caloriesPer100g) / 100.0
        }
    }
}
