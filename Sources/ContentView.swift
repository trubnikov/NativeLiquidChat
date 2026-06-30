import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var store = ChatStore()
    @State private var models = ModelManager()
    @State private var inputText = ""
    @State private var showingSettings = false
    @State private var showingModels = false
    @State private var systemPromptTemp = ""
    @State private var renameTemp = ""
    @State private var showingRenameAlert = false
    @State private var sessionToRename: UUID?
    @State private var selectedModelTemp = ""
    
    // Multimedia states
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var attachedImage: UIImage? = nil
    @State private var showingCamera = false
    @State private var showingAttachDialog = false
    @State private var showingPhotoPicker = false
    
    @AppStorage("appTheme") private var appThemeRaw = AppTheme.system.rawValue

    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        NavigationSplitView {
            // SIDEBAR: Chat History List
            List(selection: $store.currentSessionId) {
                Section(header: Text("History")) {
                    ForEach(store.sessions) { session in
                        NavigationLink(value: session.id) {
                            HStack {
                                Image(systemName: session.iconName) // Optimization: use iconName property to avoid nested ternary compiler slow down
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.title)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    Text(session.modelName)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .contextMenu {
                            Button(action: {
                                sessionToRename = session.id
                                renameTemp = session.title
                                showingRenameAlert = true
                            }) {
                                Label("Rename", systemImage: "pencil")
                            }
                            
                            Button(role: .destructive, action: {
                                withAnimation {
                                    store.deleteSession(id: session.id)
                                }
                            }) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            store.deleteSession(id: store.sessions[index].id)
                        }
                    }
                }
            }
            .navigationTitle("Liquid Chat")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        withAnimation {
                            store.createSession()
                        }
                    }) {
                        Image(systemName: "square.and.pencil")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showingModels = true }) {
                        Image(systemName: "cube.box")
                    }
                }
            }
            .sheet(isPresented: $showingModels) {
                ModelsView(store: store, models: models)
            }
        } detail: {
            // DETAIL VIEW: Active Chat Screen
            if let session = store.currentSession {
                ZStack {
                    // Background
                    Color(uiColor: .systemGroupedBackground)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        // Messages ScrollView
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(spacing: 16) {
                                    if session.messages.isEmpty {
                                        EmptyChatView(
                                            modelName: session.modelName,
                                            systemPrompt: session.systemPrompt
                                        ) { prompt in
                                            inputText = prompt
                                            isInputFocused = true
                                        }
                                        .padding(.top, 40)
                                    }
                                    
                                    ForEach(session.messages) { msg in
                                        MessageBubbleView(message: msg, onPlayAudio: { data in
                                            store.playAudio(data)
                                        })
                                        .transition(.move(edge: msg.isUser ? .trailing : .leading).combined(with: .opacity))
                                    }
                                    // Streaming message
                                    if store.isLoadingResponse && !store.currentAssistantMessage.isEmpty {
                                        MessageBubbleView(message: ChatMessageData(content: store.currentAssistantMessage, isUser: false), onPlayAudio: { _ in })
                                            .id("current")
                                    } else if store.isLoadingResponse {
                                        HStack {
                                            TypingIndicator()
                                            Spacer()
                                        }
                                        .id("loading")
                                        .transition(.opacity)
                                    }

                                    Color.clear.frame(height: 8).id("bottom")
                                }
                                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: session.messages.count)
                                .animation(.easeInOut(duration: 0.2), value: store.isLoadingResponse)
                                .padding()
                            }
                            .scrollDismissesKeyboard(.interactively)
                            .onChange(of: session.messages.count) {
                                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
                            }
                            .onChange(of: store.currentAssistantMessage) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                            .onChange(of: store.isLoadingResponse) {
                                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
                            }
                        }
                        
                        // Selected Image Preview (if present)
                        if let image = attachedImage {
                            HStack {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .cornerRadius(8)
                                    .clipped()
                                
                                Text("Image attached")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Button(action: {
                                    attachedImage = nil
                                    selectedItem = nil
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding()
                            .background(.regularMaterial)
                        }
                        
                    }
                    // Input bar lives in a bottom safe-area inset: a system
                    // "floating" layer the OS renders itself (Liquid Glass on iOS 26+).
                    // We only describe the contents and sizes — never the look.
                    .safeAreaInset(edge: .bottom) {
                        HStack(alignment: .bottom, spacing: 12) {

                            // Image Upload Button (Vision model only)
                            if session.modelName.contains("VL") {
                                Button(action: { showingAttachDialog = true }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 28))
                                }
                            }

                            // Audio Recording Button (Audio model only)
                            if session.modelName.contains("Audio") {
                                Button(action: {
                                    store.toggleRecording()
                                }) {
                                    Image(systemName: store.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                        .font(.system(size: 28))
                                        .foregroundStyle(store.isRecording ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
                                }
                                .contextMenu {
                                    if store.isRecording {
                                        Button(role: .destructive, action: { store.cancelRecording() }) {
                                            Label("Cancel Recording", systemImage: "trash")
                                        }
                                    }
                                }
                            }

                            TextField("Message LFM...", text: $inputText, axis: .vertical)
                                .focused($isInputFocused)
                                .lineLimit(1...6)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                                .background(Color(uiColor: .secondarySystemBackground),
                                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .strokeBorder(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5)
                                )

                            if store.isLoadingResponse {
                                // STOP BUTTON to cancel response generation
                                Button(action: {
                                    store.stopGeneration()
                                }) {
                                    Image(systemName: "stop.circle.fill")
                                        .font(.system(size: 32))
                                        .foregroundStyle(.red)
                                }
                            } else {
                                // SEND BUTTON
                                Button(action: {
                                    let text = inputText
                                    let img = attachedImage
                                    inputText = ""
                                    attachedImage = nil
                                    selectedItem = nil
                                    isInputFocused = false
                                    Task {
                                        await store.sendMessage(text, attachedImage: img)
                                    }
                                }) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 32))
                                        .symbolEffect(.bounce, value: inputText.isEmpty)
                                }
                                .disabled(inputText.isEmpty && attachedImage == nil)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.bar)
                    }
                }
                .navigationTitle(session.modelName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        if store.isModelLoading {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                if store.downloadProgress > 0 && store.downloadProgress < 1.0 {
                                    Text("\(Int(store.downloadProgress * 100))%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: {
                            systemPromptTemp = session.systemPrompt
                            selectedModelTemp = session.modelName
                            showingSettings = true
                        }) {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                }
                .sheet(isPresented: $showingSettings) {
                    NavigationStack {
                        Form {
                            Section(header: Text("System Rules")) {
                                TextField("Act as a translator, coder, etc.", text: $systemPromptTemp, axis: .vertical)
                                    .lineLimit(4...10)
                            }
                            
                            Section(header: Text("Model"), footer: Text("The model is downloaded automatically the first time you send a message.")) {
                                Picker("Active Model", selection: $selectedModelTemp) {
                                    Text("LFM-Instruct (Text)").tag("LFM2.5-1.2B-Instruct")
                                    Text("LFM-VL (Vision)").tag("LFM2.5-VL-1.6B")
                                    Text("LFM-Audio (Voice)").tag("LFM2.5-Audio-1.5B")
                                }
                                .pickerStyle(.menu)

                                Text(modelDescription(for: selectedModelTemp))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Section(header: Text("Appearance")) {
                                Picker("Theme", selection: $appThemeRaw) {
                                    ForEach(AppTheme.allCases) { theme in
                                        Label(theme.label, systemImage: theme.iconName)
                                            .tag(theme.rawValue)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                        .navigationTitle("Chat Settings")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") {
                                    showingSettings = false
                                }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Save") {
                                    store.updateSystemPrompt(id: session.id, systemPrompt: systemPromptTemp)
                                    store.updateModel(id: session.id, modelName: selectedModelTemp)
                                    showingSettings = false
                                }
                            }
                        }
                    }
                    .presentationDetents([.medium, .large])
                }
                .confirmationDialog("Attach Image", isPresented: $showingAttachDialog, titleVisibility: .visible) {
                    Button("Photo Library") { showingPhotoPicker = true }
                    Button("Camera") { showingCamera = true }
                    Button("Cancel", role: .cancel) { }
                }
                .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedItem, matching: .images)
                .sheet(isPresented: $showingCamera) {
                    CameraPicker(isPresented: $showingCamera, selectedImage: $attachedImage)
                }
                .onChange(of: selectedItem) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            attachedImage = image
                        }
                    }
                }
            } else {
                Text("Select a chat session or create a new one.")
                    .foregroundColor(.secondary)
            }
        }
        // Rename Alert
        .alert("Rename Chat", isPresented: $showingRenameAlert) {
            TextField("New Title", text: $renameTemp)
            Button("Cancel", role: .cancel) { sessionToRename = nil }
            Button("Save") {
                if let id = sessionToRename {
                    store.renameSession(id: id, newTitle: renameTemp)
                }
                sessionToRename = nil
            }
        }
    }
    
    private func modelDescription(for model: String) -> String {
        switch model {
        case "LFM2.5-1.2B-Instruct": return "Text generation, fast local inference"
        case "LFM2.5-VL-1.6B": return "Vision, supports image analysis"
        case "LFM2.5-Audio-1.5B": return "Audio, supports voice input/output"
        default: return ""
        }
    }
}

// MARK: - MessageBubbleView (restored and optimized to prevent compiler bottlenecks)
struct MessageBubbleView: View {
    let message: ChatMessageData
    let onPlayAudio: (Data) -> Void

    /// Render assistant replies as Markdown (bold, lists, code spans, links);
    /// keep user text verbatim.
    private var formattedContent: AttributedString {
        if message.isUser {
            return AttributedString(message.content)
        }
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let parsed = try? AttributedString(markdown: message.content, options: options) {
            return parsed
        }
        return AttributedString(message.content)
    }

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 40) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                // Image display if attached
                if let imgData = message.imageData, let uiImage = UIImage(data: imgData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 240, maxHeight: 240)
                        .cornerRadius(12)
                        .padding(.bottom, 4)
                }
                
                HStack(spacing: 8) {
                    // Audio Playback button if audio is attached
                    if let audData = message.audioData {
                        Button(action: {
                            onPlayAudio(audData)
                        }) {
                            Image(systemName: "play.circle.fill")
                                .font(.title2)
                                .foregroundStyle(message.isUser ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                        }
                    }

                    Text(formattedContent)
                        .font(.body)
                        .foregroundStyle(message.isUser ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background {
                    if message.isUser {
                        Color.accentColor
                    } else {
                        Color(uiColor: .secondarySystemGroupedBackground)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = message.content
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    ShareLink(item: message.content) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }

                // Speed + time footnote
                if message.speed != nil || !message.isUser {
                    HStack(spacing: 6) {
                        if let speedVal = message.speed {
                            Text(String(format: "%.1f tok/s", speedVal))
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                }
            }
            
            if !message.isUser { Spacer(minLength: 40) }
        }
    }
}
