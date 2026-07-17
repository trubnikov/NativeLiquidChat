import SwiftUI
import AVFoundation
import Vision

struct TrainingCameraView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var model = CameraViewModel()
    @State private var showingCustomNameInput = false
    @State private var customNameText = ""
    @State private var focusScreenPoint: CGPoint? = nil
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.russian.rawValue

    var body: some View {
        GeometryReader { geo in
        ZStack {
            // Live camera view layer
            if model.isCameraAuthorized {
                CameraPreviewView(session: model.captureSession) { device, view in
                    model.focusDevicePoint = device
                    focusScreenPoint = view
                    model.matchedLabel = nil
                    model.dominantLabel = nil
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                .ignoresSafeArea()

                FocusOverlay(
                    center: focusScreenPoint ?? CGPoint(x: geo.size.width / 2,
                                                        y: geo.size.height / 2 - 40)
                )
                .ignoresSafeArea()
            } else {
                Color.black
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill")
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
                            Text(AppText.get(.cameraScanning, lang: appLanguage))
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    } else if let matchedLabel = model.matchedLabel {
                        // Trained matched object
                        VStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.amber)
                                Text(AppText.get(.cameraTrainedHeader, lang: appLanguage))
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.amber)
                            }
                            
                            Text(matchedLabel)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            
                            Text(AppText.get(.cameraTrainedSubtitle, lang: appLanguage))
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    } else if let dominantLabel = model.dominantLabel {
                        // New standard object detected
                        VStack(spacing: 12) {
                            Text(AppText.get(.cameraDominantPrompt, lang: appLanguage))
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            
                            Text(dominantLabel.replacingOccurrences(of: "_", with: " "))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            
                            Text(AppText.get(.cameraRightPrompt, lang: appLanguage))
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
                                        Text(AppText.get(.buttonYes, lang: appLanguage))
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
                                        Text(AppText.get(.buttonNo, lang: appLanguage))
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
                        Text(AppText.get(.cameraPlaceholder, lang: appLanguage))
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    if model.analysisTimeMs > 0 {
                        Divider()
                            .background(Color.white.opacity(0.15))
                        Text(AppText.get(.cameraSpeedFormat(model.analysisTimeMs), lang: appLanguage))
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
                    Text(AppText.get(.dialogTitle, lang: appLanguage))
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(AppText.get(.dialogSubtitle, lang: appLanguage))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField(AppText.get(.dialogPlaceholder, lang: appLanguage), text: $customNameText)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .padding(.horizontal)
                    
                    HStack(spacing: 12) {
                        Button(AppText.get(.buttonCancel, lang: appLanguage)) {
                            showingCustomNameInput = false
                        }
                        .foregroundColor(.secondary)
                        
                        Button(AppText.get(.buttonRemember, lang: appLanguage)) {
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
}

class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }

    /// Called with (devicePoint 0…1, viewPoint in this view's coords) on tap.
    var onTap: ((CGPoint, CGPoint) -> Void)?

    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        backgroundColor = .black
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        let viewPoint = g.location(in: self)
        // Correct mapping through aspect-fill + rotation into sensor coords.
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: viewPoint)
        onTap?(devicePoint, viewPoint)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// SwiftUI camera preview wrapper
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var onTap: ((CGPoint, CGPoint) -> Void)? = nil

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let v = CameraPreviewUIView(session: session)
        v.onTap = onTap
        return v
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.onTap = onTap
    }
}

// Color asset helper
extension Color {
    static let amber = Color(red: 1.0, green: 0.75, blue: 0.0)
}

// ViewModel to encapsulate camera capturing and analysis
class CameraViewModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate,
                       AVCaptureDepthDataOutputDelegate {
    @Published var isCameraAuthorized = false
    @Published var isAnalyzing = false
    @Published var dominantLabel: String? = nil
    @Published var matchedLabel: String? = nil
    @Published var analysisTimeMs: Double = 0.0
    /// LiDAR distance to the focus point, meters (nil when depth unavailable).
    @Published var focusDepthMeters: Float? = nil

    let captureSession = AVCaptureSession()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let depthDataOutput = AVCaptureDepthDataOutput()
    private let cameraQueue = DispatchQueue(label: "camera.frame.processing")

    /// Latest LiDAR depth map (DepthFloat32), written by the depth delegate.
    private var latestDepthMap: CVPixelBuffer?
    private let depthLock = NSLock()
    /// Depth gate: pixels farther than this from the focus-point depth are
    /// treated as background and masked out before recognition.
    private let depthToleranceMeters: Float = 0.15
    
    /// Agent coordinator flips this off while the LFM is thinking/speaking so
    /// CLIP/Vision don't fight the LLM for the ANE/GPU (froze the preview).
    var analysisEnabled = true

    /// Where recognition looks, in capture-device coordinates (0…1, top-left
    /// origin). Tap-to-focus moves this; recognition uses ONLY this zone, so a
    /// cluttered scene no longer confuses the matchers.
    @Published var focusDevicePoint = CGPoint(x: 0.5, y: 0.5)
    /// Side of the square focus zone as a fraction of the frame.
    let focusZoneSide: CGFloat = 0.42

    /// Vision-style normalized ROI (bottom-left origin) around the focus point.
    var visionROI: CGRect {
        let s = focusZoneSide
        var x = focusDevicePoint.x - s/2
        var y = (1 - focusDevicePoint.y) - s/2   // flip to bottom-left origin
        x = min(max(x, 0), 1 - s)
        y = min(max(y, 0), 1 - s)
        return CGRect(x: x, y: y, width: s, height: s)
    }
    private var isProcessingFrame = false
    private var lastAnalysisTime: Date = .distantPast
    private(set) var currentClassifications: [String: Double] = [:]
    /// Ring buffer of the last few visual feature prints; averaged on train so a
    /// single noisy frame doesn't define the object.
    private var recentPrints: [[Float]] = []
    private let maxRecentPrints = 3
    
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
        
        // Prefer the LiDAR camera: same video feed, plus a synchronized depth
        // stream used to cut the background away from recognition.
        let lidar = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back)
        guard let camera = lidar
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            print("Failed to access camera device.")
            captureSession.commitConfiguration()
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        // BGRA so the depth mask can paint background pixels directly.
        videoDataOutput.videoSettings =
            [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: cameraQueue)

        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        }

        if lidar != nil {
            depthDataOutput.isFilteringEnabled = true   // smooth LiDAR holes
            depthDataOutput.alwaysDiscardsLateDepthData = true
            depthDataOutput.setDelegate(self, callbackQueue: cameraQueue)
            if captureSession.canAddOutput(depthDataOutput) {
                captureSession.addOutput(depthDataOutput)
            }
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
        TrainedObjectsManager.shared.train(customLabel: name,
                                           classifications: currentClassifications,
                                           featurePrint: averagedPrint())
        // Refresh local matching state
        matchedLabel = name
    }

    /// Element-wise mean of the buffered prints — steadier than any single frame.
    func averagedPrint() -> [Float]? {
        guard let first = recentPrints.first else { return nil }
        let usable = recentPrints.filter { $0.count == first.count }
        guard !usable.isEmpty else { return nil }
        var sum = [Float](repeating: 0, count: first.count)
        for print in usable {
            for i in 0..<sum.count { sum[i] += print[i] }
        }
        let n = Float(usable.count)
        return sum.map { $0 / n }
    }
    
    // MARK: - Depth-gated recognition (LiDAR background removal)

    func depthDataOutput(_ output: AVCaptureDepthDataOutput,
                         didOutput depthData: AVDepthData,
                         timestamp: CMTime,
                         connection: AVCaptureConnection) {
        let converted = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        depthLock.lock()
        latestDepthMap = converted.depthDataMap
        depthLock.unlock()
    }

    /// Returns a copy of the frame where, inside the focus zone, every pixel
    /// whose LiDAR depth differs from the focus-point depth by more than the
    /// gate tolerance is painted neutral gray. CLIP and feature prints then
    /// see the *object*, not the background it happens to sit on.
    /// Also returns the focus-point distance in meters.
    private func depthGatedBuffer(from pixelBuffer: CVPixelBuffer,
                                  roi: CGRect) -> (buffer: CVPixelBuffer, distance: Float)? {
        depthLock.lock()
        let depthOpt = latestDepthMap
        depthLock.unlock()
        guard let depth = depthOpt,
              CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA
        else { return nil }

        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        guard let dBase = CVPixelBufferGetBaseAddress(depth) else { return nil }
        let dw = CVPixelBufferGetWidth(depth)
        let dh = CVPixelBufferGetHeight(depth)
        let dRow = CVPixelBufferGetBytesPerRow(depth) / MemoryLayout<Float32>.size
        let dData = dBase.assumingMemoryBound(to: Float32.self)

        // Reference distance: median of a 3×3 patch at the focus point.
        let fx = Int(focusDevicePoint.x * CGFloat(dw - 1))
        let fy = Int(focusDevicePoint.y * CGFloat(dh - 1))
        var samples: [Float] = []
        for oy in -1...1 {
            for ox in -1...1 {
                let x = min(max(fx + ox, 0), dw - 1)
                let y = min(max(fy + oy, 0), dh - 1)
                let v = dData[y * dRow + x]
                if v.isFinite && v > 0.05 { samples.append(v) }
            }
        }
        guard !samples.isEmpty else { return nil }
        let d0 = samples.sorted()[samples.count / 2]

        // Copy the frame; the mask is painted into the copy.
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        var copyOut: CVPixelBuffer?
        let attrs = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary
        CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, attrs, &copyOut)
        guard let copy = copyOut else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(copy, [])
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(copy, [])
        }
        guard let srcBase = CVPixelBufferGetBaseAddress(pixelBuffer),
              let dstBase = CVPixelBufferGetBaseAddress(copy) else { return nil }
        let srcRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let dstRow = CVPixelBufferGetBytesPerRow(copy)
        for y in 0..<h {
            memcpy(dstBase + y * dstRow, srcBase + y * srcRow, min(srcRow, dstRow))
        }

        // Focus zone in top-left pixel coordinates (roi is bottom-left based).
        let x0 = Int(roi.minX * CGFloat(w))
        let x1 = Int(roi.maxX * CGFloat(w))
        let yTop = Int((1 - roi.maxY) * CGFloat(h))
        let yBot = Int((1 - roi.minY) * CGFloat(h))

        let dst = dstBase.assumingMemoryBound(to: UInt8.self)
        let tol = depthToleranceMeters
        var masked = 0, total = 0
        for y in max(0, yTop)..<min(h, yBot) {
            let dy = min(dh - 1, (y * dh) / h)
            for x in max(0, x0)..<min(w, x1) {
                total += 1
                let dx = min(dw - 1, (x * dw) / w)
                let d = dData[dy * dRow + dx]
                if !(d.isFinite && abs(d - d0) <= tol) {
                    let p = y * dstRow + x * 4
                    dst[p] = 128; dst[p + 1] = 128; dst[p + 2] = 128; dst[p + 3] = 255
                    masked += 1
                }
            }
        }
        #if DEBUG
        if total > 0 {
            print(String(format: "[DepthGate] d0=%.2fm masked=%d%%", d0, masked * 100 / total))
        }
        #endif
        return (copy, d0)
    }

    // SampleBuffer Delegate to analyze frames at 1Hz throttle rate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard analysisEnabled, !isProcessingFrame,
              now.timeIntervalSince(lastAnalysisTime) >= 1.0 else { return }
        lastAnalysisTime = now
        isProcessingFrame = true
        defer { isProcessingFrame = false }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let roi = visionROI

        // Depth gate: cut the background out of the focus zone so every
        // matcher below sees the object itself, not the scene behind it.
        var analysisBuffer = pixelBuffer
        var focusDistance: Float? = nil
        if let gated = depthGatedBuffer(from: pixelBuffer, roi: roi) {
            analysisBuffer = gated.buffer
            focusDistance = gated.distance
        }
        DispatchQueue.main.async { self.focusDepthMeters = focusDistance }

        // Build image request handler on the (masked) pixel buffer
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: analysisBuffer, orientation: .up, options: [:])

        // Visual feature print of the focus zone — true instance recognition.
        let printRequest = VNGenerateImageFeaturePrintRequest()
        printRequest.regionOfInterest = roi

        let classificationRequest = VNClassifyImageRequest { request, error in
            guard error == nil,
                  let _ = request.results as? [VNClassificationObservation] else {
                return
            }
        }
        // Classification looks only inside the focus zone.
        classificationRequest.regionOfInterest = roi

        DispatchQueue.main.async {
            self.isAnalyzing = true
        }

        let startTime = Date()
        do {
            try requestHandler.perform([classificationRequest, printRequest])
            let duration = Date().timeIntervalSince(startTime) * 1000.0

            // Extract results synchronously after perform.
            let results = (classificationRequest.results as? [VNClassificationObservation]) ?? []
            let mappedVec = results
                .filter { $0.confidence > 0.01 }
                .prefix(10)
                .reduce(into: [String: Double]()) { dict, item in
                    dict[item.identifier] = Double(item.confidence)
                }

            var framePrint: [Float]? = nil
            if let obs = printRequest.results?.first as? VNFeaturePrintObservation {
                framePrint = VisionProcessor.floats(from: obs)
            }

            // Zero-shot open-vocabulary label via MobileCLIP — concrete nouns
            // ("mug") instead of Apple's abstract taxonomy ("structure").
            let clipMatch = CLIPEngine.shared.bestLabel(pixelBuffer: analysisBuffer, roi: roi)

            DispatchQueue.main.async {
                self.analysisTimeMs = duration
                self.currentClassifications = mappedVec
                if let p = framePrint {
                    self.recentPrints.append(p)
                    if self.recentPrints.count > self.maxRecentPrints {
                        self.recentPrints.removeFirst()
                    }
                }

                // 1. Instance match on the visual print (falls back to histogram
                //    for objects trained before the upgrade).
                if let match = TrainedObjectsManager.shared.findMatch(for: mappedVec, featurePrint: framePrint) {
                    self.matchedLabel = match
                    self.dominantLabel = nil
                } else {
                    self.matchedLabel = nil
                    // 2. Zero-shot CLIP label (concrete, open-vocabulary) …
                    if let clip = clipMatch {
                        self.dominantLabel = clip.label.capitalized
                    // 3. … falling back to Apple's classifier taxonomy.
                    } else if let firstResult = results.first(where: { $0.confidence > 0.02 }) {
                        let name = firstResult.identifier.components(separatedBy: ",").first ?? firstResult.identifier
                        self.dominantLabel = name.capitalized
                    } else {
                        self.dominantLabel = nil
                    }
                }
                self.isAnalyzing = false
            }
        } catch {
            print("Failed to run real-time camera classification: \(error)")
            DispatchQueue.main.async {
                self.isAnalyzing = false
            }
        }
    }
}
