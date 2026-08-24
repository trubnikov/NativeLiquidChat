import SwiftUI
import AVFoundation
import ARKit
import SceneKit
import RoomPlan

/// 3D surface scan (LiDAR), two modes:
/// - **Wave** — a live grid of dots lies on real-world surfaces; nearer
///   geometry glows mint and lifts, and a scanning wave ripples across the
///   relief, its phase driven by depth, so it visibly bends around objects.
/// - **Mesh** — ARKit scene reconstruction: a real triangle mesh anchored in
///   world space grows over every surface and *stays put* as you move.
struct DepthScanView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner = DepthScanViewModel()
    @State private var mode: ScanMode = .wave

    enum ScanMode: String, CaseIterable, Identifiable {
        case wave, mesh, room
        var id: String { rawValue }
        var label: String {
            switch self {
            case .wave: return "Wave"
            case .mesh: return "Mesh"
            case .room: return "Room"
            }
        }
    }

    /// Live structure counts reported by RoomPlan while scanning.
    @State private var roomStats = RoomScanStats()

    var body: some View {
        ZStack {
            if mode == .room {
                if RoomCaptureSession.isSupported {
                    RoomScanView(stats: $roomStats)
                        .ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                    Text("Room scanning is not supported on this device")
                        .foregroundStyle(.white)
                }
            } else if mode == .mesh {
                MeshScanView()
                    .ignoresSafeArea()
            } else if scanner.isAvailable {
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
                    // Live room-structure counts (room mode)
                    if mode == .room, RoomCaptureSession.isSupported {
                        HStack(spacing: 10) {
                            Label("\(roomStats.walls)", systemImage: "square.split.bottomrightquarter")
                            Label("\(roomStats.doors + roomStats.windows)", systemImage: "door.left.hand.open")
                            Label("\(roomStats.objects)", systemImage: "chair.lounge")
                        }
                        .font(.caption.weight(.semibold))
                        .contentTransition(.numericText())
                        .animation(.snappy, value: roomStats)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .dsGlass(in: Capsule())
                    }

                    // Depth legend (wave mode only)
                    if mode == .wave {
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
                        .dsGlass(in: Capsule())
                    }

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

                // Mode switch: dot wave vs. anchored reconstruction mesh.
                Picker("Mode", selection: $mode) {
                    ForEach(ScanMode.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                .padding(.bottom, 24)
            }
        }
        .onAppear { if mode == .wave { scanner.start() } }
        .onDisappear { scanner.stop() }
        .onChange(of: mode) { _, newMode in
            // The AVCapture session, the ARKit session and RoomPlan can't
            // share the camera — run exactly one at a time.
            if newMode == .wave { scanner.start() } else { scanner.stop() }
        }
    }
}

// MARK: - RoomPlan (room mode)

/// Live counts of what RoomPlan has recognized so far.
struct RoomScanStats: Equatable {
    var walls = 0
    var doors = 0
    var windows = 0
    var objects = 0
}

/// Apple RoomPlan capture: walks the room and builds a parametric model
/// (walls, doors, windows, furniture) fully on-device. RoomCaptureView draws
/// the live camera feed, the growing model and coaching hints itself.
private struct RoomScanView: UIViewRepresentable {
    @Binding var stats: RoomScanStats

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.captureSession.delegate = context.coordinator
        var config = RoomCaptureSession.Configuration()
        config.isCoachingEnabled = true
        view.captureSession.run(configuration: config)
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}

    static func dismantleUIView(_ uiView: RoomCaptureView, coordinator: Coordinator) {
        uiView.captureSession.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator(stats: $stats) }

    final class Coordinator: NSObject, RoomCaptureSessionDelegate {
        private let stats: Binding<RoomScanStats>
        init(stats: Binding<RoomScanStats>) { self.stats = stats }

        func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
            let next = RoomScanStats(walls: room.walls.count,
                                     doors: room.doors.count,
                                     windows: room.windows.count,
                                     objects: room.objects.count)
            DispatchQueue.main.async { [stats] in
                if stats.wrappedValue != next { stats.wrappedValue = next }
            }
        }
    }
}

// MARK: - ARKit scene reconstruction (mesh mode)

/// Live ARKit mesh: LiDAR scene reconstruction rendered as a mint wireframe
/// anchored to the world — walk around and the mesh stays on the surfaces.
private struct MeshScanView: UIViewRepresentable {
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.delegate = context.coordinator
        view.automaticallyUpdatesLighting = true

        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        config.environmentTexturing = .none
        view.session.run(config)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, ARSCNViewDelegate {
        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            guard let mesh = anchor as? ARMeshAnchor else { return nil }
            let node = SCNNode(geometry: Self.wireframe(from: mesh.geometry))
            return node
        }

        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let mesh = anchor as? ARMeshAnchor else { return }
            node.geometry = Self.wireframe(from: mesh.geometry)
        }

        private static func wireframe(from mesh: ARMeshGeometry) -> SCNGeometry {
            let vertices = SCNGeometrySource(
                buffer: mesh.vertices.buffer,
                vertexFormat: mesh.vertices.format,
                semantic: .vertex,
                vertexCount: mesh.vertices.count,
                dataOffset: mesh.vertices.offset,
                dataStride: mesh.vertices.stride)
            let faceData = Data(
                bytes: mesh.faces.buffer.contents(),
                count: mesh.faces.buffer.length)
            let element = SCNGeometryElement(
                data: faceData,
                primitiveType: .triangles,
                primitiveCount: mesh.faces.count,
                bytesPerIndex: mesh.faces.bytesPerIndex)
            let geometry = SCNGeometry(sources: [vertices], elements: [element])
            let material = SCNMaterial()
            material.fillMode = .lines
            material.diffuse.contents = UIColor(red: 0.24, green: 0.95, blue: 0.77, alpha: 0.8)
            material.isDoubleSided = true
            geometry.materials = [material]
            return geometry
        }
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
    /// Session inputs/outputs are attached once and reused across mode switches.
    private var isConfigured = false

    /// Accumulated "snow": each wave pass deposits brightness on the cells it
    /// crosses, so the relief builds up scan after scan instead of flashing.
    private var reveal: [Float]
    /// Depth at which each cell was revealed — if the geometry under a cell
    /// changes (camera or object moved), its snow melts and re-accumulates.
    private var revealDepth: [Float]

    override init() {
        grid = Array(repeating: 1, count: cols * rows)
        reveal = Array(repeating: 0, count: cols * rows)
        revealDepth = Array(repeating: 1, count: cols * rows)
        super.init()
    }

    // MARK: - Capture

    func start() {
        // Fresh snow on every scan session.
        reveal = Array(repeating: 0, count: cols * rows)
        guard let device = AVCaptureDevice.default(.builtInLiDARDepthCamera,
                                                   for: .video, position: .back) else {
            DispatchQueue.main.async { self.isAvailable = false }
            return
        }
        guard !session.isRunning else { return }

        // Configure exactly once: re-entering Wave mode after Mesh/Room must
        // not re-add inputs/outputs (AVFoundation would silently corrupt the
        // session — black preview, frozen dots).
        if !isConfigured {
            isConfigured = true
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
        }

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
                let i = r * cols + c
                let depth = Double(g[i])              // 0 near … 1 far

                // Wave phase bends with depth: the ripple visibly climbs
                // near (raised) geometry earlier and reaches far later.
                let dist = Double(hypot(CGFloat(c) - cx, CGFloat(r) - cy)) + depth * 10
                let wave = max(0, 1 - abs(dist - waveR) / 2.6)   // 0…1 pulse

                // Snow accumulation: the passing wave deposits brightness that
                // STAYS after it moves on; each pass adds another layer.
                if wave > 0.15 {
                    reveal[i] = min(1, reveal[i] + Float(wave) * 0.28)
                    revealDepth[i] = Float(depth)
                } else if abs(Float(depth) - revealDepth[i]) > 0.06 {
                    // Geometry under the cell changed — melt and rebuild.
                    reveal[i] *= 0.80
                    revealDepth[i] = Float(depth)
                }
                let rev = Double(reveal[i])

                let near = 1 - depth                              // 0 far … 1 near
                // Before any wave: a faint hint field. Revealed cells stay lit.
                let baseAlpha = 0.05 + near * 0.10 + rev * (0.25 + near * 0.45) + wave * 0.45
                let radius = 1.0 + near * 0.9 + rev * (0.6 + near * 1.9) + wave * 2.2
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
