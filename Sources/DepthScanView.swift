import SwiftUI
import AVFoundation

/// 3D surface scan (LiDAR): a live grid of dots lies on real-world surfaces —
/// nearer geometry glows mint and lifts, farther geometry sinks and dims — and
/// a scanning wave ripples across the relief in real time. The wave's phase is
/// driven by *depth*, so it visibly bends around objects: you SEE what is
/// higher and what is lower.
struct DepthScanView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner = DepthScanViewModel()

    var body: some View {
        ZStack {
            if scanner.isAvailable {
                CameraPreviewView(session: scanner.session)
                    .ignoresSafeArea()

                // Depth dot field + scanning wave.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    Canvas { ctx, size in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        scanner.draw(in: &ctx, size: size, time: t)
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            } else {
                Color.black.ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "camera.metering.unknown")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("LiDAR is not available on this device")
                        .foregroundStyle(.white)
                }
            }

            // Top bar
            VStack {
                HStack {
                    // Depth legend
                    HStack(spacing: 6) {
                        Circle().fill(DS.accent).frame(width: 8, height: 8)
                        Text("near").font(.caption2)
                        Circle().fill(Color(red: 0.15, green: 0.3, blue: 0.45))
                            .frame(width: 8, height: 8)
                        Text("far").font(.caption2)
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.55)))

                    Spacer()

                    Button {
                        scanner.stop()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.85))
                            .shadow(radius: 4)
                    }
                }
                .padding()
                Spacer()
            }
        }
        .onAppear { scanner.start() }
        .onDisappear { scanner.stop() }
    }
}

/// Captures LiDAR depth and renders the dot field.
final class DepthScanViewModel: NSObject, ObservableObject, AVCaptureDepthDataOutputDelegate {
    @Published var isAvailable = true

    let session = AVCaptureSession()
    private let depthOutput = AVCaptureDepthDataOutput()
    private let queue = DispatchQueue(label: "depth.scan.queue")

    // Dot grid resolution (portrait: rows down the screen).
    private let cols = 30
    private let rows = 42

    /// Normalized depth per cell (0 = near, 1 = far), row-major. Written on the
    /// capture queue, read on the render thread — guarded by a lock.
    private var grid: [Float]
    private let gridLock = NSLock()

    /// Depth range mapped to the visual scale (meters).
    private let nearM: Float = 0.25
    private let farM: Float = 2.5

    override init() {
        grid = Array(repeating: 1, count: cols * rows)
        super.init()
    }

    // MARK: - Capture

    func start() {
        guard let device = AVCaptureDevice.default(.builtInLiDARDepthCamera,
                                                   for: .video, position: .back) else {
            DispatchQueue.main.async { self.isAvailable = false }
            return
        }
        guard !session.isRunning else { return }

        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        if let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }

        depthOutput.isFilteringEnabled = true   // smooth LiDAR holes
        depthOutput.setDelegate(self, callbackQueue: queue)
        if session.canAddOutput(depthOutput) {
            session.addOutput(depthOutput)
        }
        // Portrait orientation for the depth stream when supported.
        if let conn = depthOutput.connection(with: .depthData) {
            if conn.isVideoRotationAngleSupported(90) {
                conn.videoRotationAngle = 90
            }
        }
        session.commitConfiguration()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stop() {
        if session.isRunning { session.stopRunning() }
    }

    func depthDataOutput(_ output: AVCaptureDepthDataOutput,
                         didOutput depthData: AVDepthData,
                         timestamp: CMTime,
                         connection: AVCaptureConnection) {
        let converted = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let map = converted.depthDataMap
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(map) else { return }
        let w = CVPixelBufferGetWidth(map)
        let h = CVPixelBufferGetHeight(map)
        let rowFloats = CVPixelBufferGetBytesPerRow(map) / MemoryLayout<Float32>.size
        let data = base.assumingMemoryBound(to: Float32.self)

        var next = [Float](repeating: 1, count: cols * rows)
        for r in 0..<rows {
            let sy = min(h - 1, (r * h) / rows)
            for c in 0..<cols {
                let sx = min(w - 1, (c * w) / cols)
                let d = data[sy * rowFloats + sx]
                if d.isFinite && d > 0.05 {
                    let n = (d - nearM) / (farM - nearM)
                    next[r * cols + c] = min(max(n, 0), 1)
                } else {
                    next[r * cols + c] = 1
                }
            }
        }
        gridLock.lock()
        grid = next
        gridLock.unlock()
    }

    // MARK: - Rendering

    /// Draws the dot field: depth → color/size/lift, plus a scanning wave whose
    /// phase includes depth so it ripples over the 3D relief.
    func draw(in ctx: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        gridLock.lock()
        let g = grid
        gridLock.unlock()

        let cellW = size.width / CGFloat(cols)
        let cellH = size.height / CGFloat(rows)
        let cx = CGFloat(cols) / 2
        let cy = CGFloat(rows) / 2

        // Expanding wave: radius grows and loops every few seconds.
        let period = 3.2
        let maxR = Double(hypot(cx, cy)) + 8
        let waveR = (time.truncatingRemainder(dividingBy: period)) / period * maxR

        for r in 0..<rows {
            for c in 0..<cols {
                let depth = Double(g[r * cols + c])   // 0 near … 1 far

                // Wave phase bends with depth: the ripple visibly climbs
                // near (raised) geometry earlier and reaches far later.
                let dist = Double(hypot(CGFloat(c) - cx, CGFloat(r) - cy)) + depth * 10
                let wave = max(0, 1 - abs(dist - waveR) / 2.6)   // 0…1 pulse

                let near = 1 - depth                              // 0 far … 1 near
                let baseAlpha = 0.10 + near * 0.55 + wave * 0.45
                let radius = 1.2 + near * 2.4 + wave * 2.2
                // Near dots lift up slightly — a parallax hint of relief.
                let lift = CGFloat(near) * -5.0

                let x = (CGFloat(c) + 0.5) * cellW
                let y = (CGFloat(r) + 0.5) * cellH + lift

                // Mint (near) → deep blue (far); the wave flashes white-mint.
                let color = Color(
                    red: 0.24 * near + 0.10 * (1 - near) + wave * 0.5,
                    green: 0.95 * near + 0.28 * (1 - near) + wave * 0.05,
                    blue: 0.77 * near + 0.42 * (1 - near) + wave * 0.2
                ).opacity(min(baseAlpha, 1))

                let rect = CGRect(x: x - radius, y: y - radius,
                                  width: radius * 2, height: radius * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
    }
}
