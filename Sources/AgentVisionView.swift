import SwiftUI
import AVFoundation

/// Live "agent eyes" mode: the camera watches the world, the LFM narrates what
/// it sees out loud, and when a *stable unknown* object appears the agent asks
/// the user (by voice) what to call it, listens for the answer, and learns it —
/// feature print + knowledge-graph node. Fully on-device.
///
/// State machine: observing → thinking → speaking → observing
///                observing → asking → listening → speaking(confirm) → observing
@MainActor
final class AgentVisionCoordinator: ObservableObject {
    enum Phase: String {
        case observing, thinking, speaking, asking, listening
    }

    @Published var phase: Phase = .observing {
        didSet {
            // Pause camera analysis while the LFM thinks/speaks — GPU/ANE
            // contention between CLIP+Vision and LLM inference froze the feed.
            camera.analysisEnabled = (phase == .observing)
        }
    }
    @Published var currentSeen: String = ""
    @Published var lastComment: String = ""
    @Published var liveTranscript: String = ""

    let camera = CameraViewModel()
    private let speech = SpeechManager()
    // English-only mode: recognize spoken names with the English engine.
    private let recognizer = SpeechRecognizer(locale: Locale(identifier: "en-US"))
    private weak var store: ChatStore?

    // Scene stability: same label for N consecutive ticks (1 tick ≈ 1 s).
    private var stableLabel: String?
    private var stableCount = 0
    private let stabilityNeeded = 3

    // Throttles so the agent doesn't babble or nag.
    private var lastCommentedLabel: String?
    private var lastCommentTime = Date.distantPast
    private var recentlyAsked: [String: Date] = [:]

    // Captured at the moment we decide to ask, so the learned vector matches
    // what the user was actually shown.
    private var pendingClassifications: [String: Double] = [:]
    private var pendingPrint: [Float]?
    private var pendingAppleLabel = ""

    private var tick: Timer?

    // Agent mode is English-only: the small on-device LFM is much more reliable
    // in English, and mixed-language TTS/narration confused it in testing.

    func start(store: ChatStore) {
        self.store = store
        store.stopConversation()   // don't fight over the mic with hands-free chat
        store.stopSpeaking()

        speech.forceAutoVoice = true   // English narration → English voice, always
        speech.onFinishSpeaking = { [weak self] in
            Task { @MainActor in self?.didFinishSpeaking() }
        }

        camera.checkAuthorizationAndStart()
        phase = .observing

        tick?.invalidate()
        tick = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
    }

    func stop() {
        tick?.invalidate()
        tick = nil
        camera.stopSession()
        recognizer.stop()
        speech.stop()
        phase = .observing
    }

    // MARK: - Perception loop

    private func evaluate() {
        guard phase == .observing else { return }

        let matched = camera.matchedLabel
        let dominant = camera.dominantLabel
        let label = matched ?? dominant
        currentSeen = label ?? ""

        guard let label else {
            stableLabel = nil
            stableCount = 0
            return
        }

        if label == stableLabel {
            stableCount += 1
        } else {
            stableLabel = label
            stableCount = 1
        }
        guard stableCount >= stabilityNeeded else { return }

        if matched != nil {
            // A known (user-trained) object — narrate it, with graph facts.
            maybeComment(about: label, known: true)
        } else {
            // Unknown but stable — ask once, then leave it alone for a while.
            if let asked = recentlyAsked[label], Date().timeIntervalSince(asked) < 180 {
                maybeComment(about: label, known: false)
            } else {
                askAboutUnknown(label)
            }
        }
    }

    // MARK: - Narration (LFM speaks about the scene)

    private func maybeComment(about label: String, known: Bool) {
        let now = Date()
        guard label != lastCommentedLabel || now.timeIntervalSince(lastCommentTime) > 60 else { return }
        lastCommentedLabel = label
        lastCommentTime = now

        phase = .thinking
        Task { @MainActor in
            // Seeded world knowledge covers generic categories too, so pull
            // graph facts for both trained objects and Apple Vision labels.
            let facts = KnowledgeGraphManager.shared
                .traverseGraph(startingFrom: label).associatedFacts
            _ = known
            #if DEBUG
            print("[Agent] narrate label='\(label)' known=\(known) facts=\(facts.count)")
            #endif

            let system = "You are the voice of an assistant watching the world through a camera. Reply with EXACTLY ONE short sentence, max 15 words. No greetings. English only."
            var user = "Currently in view: \(label)."
            if let fact = facts.first {
                user += " A known fact: \(String(fact.prefix(160)))."
            }

            let reply = await store?.generateOneShot(system: system, user: user) ?? ""
            // Hard cap: never let the agent monologue — first sentence only.
            let firstSentence = reply
                .components(separatedBy: CharacterSet(charactersIn: ".!?"))
                .first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
            let text = firstSentence.isEmpty ? "I can see: \(label)." : firstSentence + "."

            lastComment = text
            phase = .speaking
            speech.speak(text)
        }
    }

    // MARK: - Ask-and-learn (unknown object)

    private func askAboutUnknown(_ appleLabel: String) {
        recentlyAsked[appleLabel] = Date()
        pendingAppleLabel = appleLabel
        pendingClassifications = camera.currentClassifications
        pendingPrint = camera.averagedPrint()

        // If the seeded knowledge base knows this category, weave a fact into
        // the question — the agent sounds informed even about unknown items.
        let fact = KnowledgeGraphManager.shared
            .traverseGraph(startingFrom: appleLabel).associatedFacts.first
        #if DEBUG
        print("[Agent] ask label='\(appleLabel)' fact=\(fact != nil)")
        #endif
        var question = "I see something like a \(appleLabel.replacingOccurrences(of: "_", with: " "))."
        if let fact {
            question += " \(String(fact.prefix(120)))"
        }
        question += " I don't know this one specifically — what should I call it? Say a name, or stay silent to skip."

        lastComment = question
        phase = .asking
        speech.speak(question)
        // didFinishSpeaking() flips us into .listening
    }

    private func startListening() {
        phase = .listening
        liveTranscript = ""

        recognizer.onPartial = { [weak self] text in
            Task { @MainActor in self?.liveTranscript = text }
        }
        recognizer.onFinished = { [weak self] text in
            Task { @MainActor in self?.handleName(text) }
        }
        do {
            try recognizer.start()
        } catch {
            print("[AgentVision] recognizer failed: \(error)")
            phase = .observing
        }
    }

    private func handleName(_ raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        liveTranscript = ""

        guard !name.isEmpty else {
            let skip = "Okay, I'll keep watching."
            lastComment = skip
            phase = .speaking
            speech.speak(skip)
            return
        }

        TrainedObjectsManager.shared.train(
            customLabel: name,
            classifications: pendingClassifications,
            featurePrint: pendingPrint
        )
        // Link the new instance to its category node ("my mug" → "mug") so the
        // 2-hop graph traversal reaches the category's seeded facts when
        // narrating about the trained object.
        let category = pendingAppleLabel.replacingOccurrences(of: "_", with: " ").lowercased()
        DispatchQueue.main.async {
            let kg = KnowledgeGraphManager.shared
            if let obj = kg.nodes.first(where: { $0.label.lowercased() == name.lowercased() }),
               let cat = kg.nodes.first(where: { $0.label.lowercased() == category }),
               obj.id != cat.id {
                kg.addEdge(sourceId: obj.id, targetId: cat.id, relationType: "instance_of")
            }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        let confirm = "Got it: \(name)."
        lastComment = confirm
        phase = .speaking
        speech.speak(confirm)
    }

    /// Focus zone moved — forget the old scene so recognition restarts cleanly.
    func focusChanged() {
        stableLabel = nil
        stableCount = 0
        currentSeen = ""
        camera.matchedLabel = nil
        camera.dominantLabel = nil
    }

    /// User-initiated interrupt: stop talking/listening and go back to watching.
    func skip() {
        speech.stop()
        recognizer.stop()
        liveTranscript = ""
        phase = .observing
    }

    private func didFinishSpeaking() {
        switch phase {
        case .asking:
            startListening()
        case .speaking:
            phase = .observing
        default:
            break
        }
    }
}

// MARK: - View

struct AgentVisionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var agent = AgentVisionCoordinator()
    let store: ChatStore
    /// Focus zone center in screen coords (nil = screen center).
    @State private var focusScreenPoint: CGPoint? = nil

    var body: some View {
        GeometryReader { geo in
        ZStack {
            if agent.camera.isCameraAuthorized {
                CameraPreviewView(session: agent.camera.captureSession) { device, view in
                    agent.camera.focusDevicePoint = device
                    focusScreenPoint = view
                    agent.focusChanged()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                .ignoresSafeArea()

                // Tap-to-focus zone: recognition happens ONLY inside the frame.
                FocusOverlay(
                    center: focusScreenPoint ?? CGPoint(x: geo.size.width / 2,
                                                        y: geo.size.height / 2 - 40),
                    label: agent.currentSeen,
                    isTrained: agent.camera.matchedLabel != nil,
                    distanceMeters: agent.camera.focusDepthMeters
                )
                .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                Text("Camera access required")
                    .foregroundColor(.white)
            }

            VStack {
                // Top bar: phase + close
                HStack {
                    phaseChip
                    Spacer()
                    Button {
                        agent.stop()
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

                // Bottom card: what the agent sees / says / hears
                VStack(alignment: .leading, spacing: 10) {
                    if !agent.currentSeen.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "eye").font(.system(size: 15))
                            Text(agent.currentSeen)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    }
                    if !agent.lastComment.isEmpty {
                        Text(agent.lastComment)
                            .font(.body)
                            .foregroundColor(.white.opacity(0.95))
                    }
                    if agent.phase == .listening {
                        HStack(spacing: 8) {
                            Image(systemName: "mic").font(.system(size: 15))
                                .foregroundColor(.red)
                            Text(agent.liveTranscript.isEmpty
                                 ? "Listening…"
                                 : agent.liveTranscript)
                                .font(.callout)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }

                    // Interrupt: stop talking/asking and go back to watching.
                    if agent.phase != .observing {
                        Button(action: { agent.skip() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "stop.circle.fill").font(.system(size: 15))
                                Text("Skip")
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
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
        }
        .onAppear { agent.start(store: store) }
        .onDisappear { agent.stop() }
        }
    }

    private var phaseChip: some View {
        let (icon, text): (String, String) = {
            switch agent.phase {
            case .observing: return ("eye", "Watching")
            case .thinking: return ("brain.head.profile", "Thinking…")
            case .speaking: return ("speaker.wave.2.fill", "Speaking")
            case .asking: return ("message", "Asking")
            case .listening: return ("mic", "Listening")
            }
        }()
        return HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 14))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.variableColor.iterative,
                              isActive: icon == "speaker.wave.2.fill" || icon == "mic")
                .symbolEffect(.pulse, isActive: icon == "brain.head.profile")
            Text(text).font(.footnote.weight(.semibold))
                .contentTransition(.numericText())
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .dsGlass(in: Capsule())
    }
}
