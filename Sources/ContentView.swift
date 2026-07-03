import SwiftUI
import PhotosUI
import Translation

struct ContentView: View {
    @State private var store = ChatStore()
    @State private var models = ModelManager()
    @ObservedObject private var trainedObjectsManager = TrainedObjectsManager.shared
    @State private var inputText = ""
    @State private var showingSettings = false
    @State private var showingModels = false
    @State private var systemPromptTemp = ""
    @State private var renameTemp = ""
    @State private var showingRenameAlert = false
    @State private var sessionToRename: UUID?
    @State private var selectedModelTemp = ""
    @State private var translationEnabledTemp = false
    @State private var userLanguageCodeTemp = "ru"
    
    // Multimedia states
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var attachedImage: UIImage? = nil
    @State private var showingCamera = false
    @State private var showingAttachDialog = false
    @State private var showingPhotoPicker = false
    @State private var showingTrainingCamera = false
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.russian.rawValue
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
                                        }, onSpeak: { text in
                                            store.speak(text)
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
                        
                        // Voice conversation status banner
                        if store.conversationMode {
                            ConversationBanner(
                                phase: store.conversationPhase,
                                transcript: store.liveTranscript
                            )
                            .padding(.horizontal)
                            .padding(.bottom, 6)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
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

                            // Image Upload Button
                            Button(action: { showingAttachDialog = true }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 28))
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
                        Button {
                            store.toggleConversationMode()
                        } label: {
                            Image(systemName: store.conversationMode ? "waveform.circle.fill" : "waveform.circle")
                                .foregroundStyle(store.conversationMode ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                        }
                        .accessibilityLabel(store.conversationMode ? "Stop voice conversation" : "Start voice conversation")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            store.speakResponses.toggle()
                            if !store.speakResponses { store.stopSpeaking() }
                        } label: {
                            Image(systemName: store.speakResponses ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        }
                        .accessibilityLabel(store.speakResponses ? "Turn off spoken replies" : "Turn on spoken replies")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingTrainingCamera = true
                        } label: {
                            Image(systemName: "camera.badge.ellipsis")
                        }
                        .accessibilityLabel("Режим обучения")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: {
                            systemPromptTemp = session.systemPrompt
                            selectedModelTemp = session.modelName
                            translationEnabledTemp = session.isTranslationEnabled
                            userLanguageCodeTemp = session.languageCode
                            showingSettings = true
                        }) {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                }
                .sheet(isPresented: $showingSettings) {
                    NavigationStack {
                        Form {
                            Section(header: Text(appLanguage == "ru" ? "Системные правила" : "System Rules"), footer: Text(appLanguage == "ru" ? "Пресеты задают системный промпт. \"QCA · Ocean\" заставляет модель рассуждать как агент Ocean — кратко и ища противоречия." : "Presets set the system prompt. \"QCA · Ocean\" makes the model reason like the Ocean agent — terse and contradiction-seeking.")) {
                                Picker(appLanguage == "ru" ? "Пресет" : "Preset", selection: presetSelection) {
                                    ForEach(PromptPresets.all) { preset in
                                        Text(preset.name).tag(preset.id)
                                    }
                                    if PromptPresets.matching(systemPromptTemp) == nil {
                                        Text(appLanguage == "ru" ? "Свой" : "Custom").tag("custom")
                                    }
                                }
                                TextField(appLanguage == "ru" ? "Роль: переводчик, программист и т.д." : "Act as a translator, coder, etc.", text: $systemPromptTemp, axis: .vertical)
                                    .lineLimit(4...10)
                            }
                            
                            Section(header: Text(appLanguage == "ru" ? "Модель" : "Model"), footer: Text(appLanguage == "ru" ? "Выберите любую загруженную модель. Модель скачивается автоматически при первой отправке сообщения." : "Pick any downloaded model. The model is downloaded automatically the first time you send a message.")) {
                                Picker(appLanguage == "ru" ? "Активная модель" : "Active Model", selection: $selectedModelTemp) {
                                    ForEach(ModelCatalog.all) { model in
                                        Text("\(model.displayName) · \(model.kind.displayName)")
                                            .tag(model.id)
                                    }
                                    if ModelCatalog.info(for: selectedModelTemp) == nil && !selectedModelTemp.isEmpty {
                                        Text(selectedModelTemp).tag(selectedModelTemp)
                                    }
                                }
                                .pickerStyle(.menu)

                                Text(modelDescription(for: selectedModelTemp))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Section(header: Text(appLanguage == "ru" ? "Озвучка" : "Speech"), footer: Text(appLanguage == "ru" ? "Ответы зачитываются вслух на устройстве. Выберите голос или предоставьте системе автоматически определять язык." : "Replies are read aloud on-device. Choose a voice or let it match the reply's language.")) {
                                Toggle(appLanguage == "ru" ? "Озвучивать ответы" : "Speak replies", isOn: $store.speakResponses)
                                NavigationLink {
                                    VoicePickerView(store: store)
                                } label: {
                                    HStack {
                                        Text(appLanguage == "ru" ? "Голос" : "Voice")
                                        Spacer()
                                        Text(selectedVoiceName)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                             Section(header: Text(appLanguage == "ru" ? "Перевод" : "Translation"), footer: Text(appLanguage == "ru" ? "Переводить ваш родной язык на английский для оптимальной работы локальных моделей. Ответы переводятся обратно на ваш язык." : "Translate your native language to English for optimal performance on local models. Translates replies back to your native language.")) {
                                Toggle(appLanguage == "ru" ? "Переводить на английский" : "Translate to English", isOn: $translationEnabledTemp)
                                if translationEnabledTemp {
                                    Picker(appLanguage == "ru" ? "Мой язык" : "My Language", selection: $userLanguageCodeTemp) {
                                        Text("Russian").tag("ru-RU")
                                        Text("Spanish").tag("es-ES")
                                        Text("French").tag("fr-FR")
                                        Text("German").tag("de-DE")
                                        Text("Italian").tag("it-IT")
                                        Text("Chinese").tag("zh-CN")
                                        Text("Japanese").tag("ja-JP")
                                        Text("Korean").tag("ko-KR")
                                    }
                                }
                            }

                            Section(header: Text(appLanguage == "ru" ? "Язык приложения" : "App Language")) {
                                Picker("App Language", selection: $appLanguage) {
                                    Text("Русский").tag("ru")
                                    Text("English").tag("en")
                                }
                                .pickerStyle(.segmented)
                            }

                            Section(header: Text(appLanguage == "ru" ? "Внешний вид" : "Appearance")) {
                                Picker(appLanguage == "ru" ? "Тема" : "Theme", selection: $appThemeRaw) {
                                    ForEach(AppTheme.allCases) { theme in
                                        Label(theme.label, systemImage: theme.iconName)
                                            .tag(theme.rawValue)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                            
                            Section(header: Text(appLanguage == "ru" ? "Память объектов" : "Object Memory"), footer: Text(appLanguage == "ru" ? "Список предметов, которым вы научили агента. Проведите пальцем влево для удаления." : "List of items you taught the agent. Swipe left to delete.")) {
                                if trainedObjectsManager.trainedObjects.isEmpty {
                                    Text(appLanguage == "ru" ? "Нет выученных объектов" : "No trained objects")
                                        .foregroundColor(.secondary)
                                } else {
                                    ForEach(trainedObjectsManager.trainedObjects) { obj in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(obj.customLabel)
                                                .font(.body)
                                                .fontWeight(.medium)
                                            Text(obj.timestamp, style: .date)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .onDelete { indexSet in
                                        for index in indexSet {
                                            let obj = trainedObjectsManager.trainedObjects[index]
                                            trainedObjectsManager.forget(id: obj.id)
                                        }
                                    }
                                }
                            }
                        }
                        .navigationTitle(appLanguage == "ru" ? "Настройки чата" : "Chat Settings")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(appLanguage == "ru" ? "Отмена" : "Cancel") {
                                    showingSettings = false
                                }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button(appLanguage == "ru" ? "Сохранить" : "Save") {
                                    store.updateSystemPrompt(id: session.id, systemPrompt: systemPromptTemp)
                                    store.updateModel(id: session.id, modelName: selectedModelTemp)
                                    store.updateTranslationEnabled(id: session.id, enabled: translationEnabledTemp)
                                    store.updateUserLanguageCode(id: session.id, code: userLanguageCodeTemp)
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
                .fullScreenCover(isPresented: $showingTrainingCamera) {
                    TrainingCameraView()
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
        
        .translationTask(store.toEnglishConfig) { session in
            store.toEnglishSession = session
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            store.toEnglishSession = nil
        }
        .translationTask(store.toNativeConfig) { session in
            store.toNativeSession = session
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            store.toNativeSession = nil
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
    
    /// Two-way binding between the preset Picker and the system-prompt text:
    /// selecting a preset fills the text; editing the text shows "Custom".
    private var presetSelection: Binding<String> {
        Binding(
            get: { PromptPresets.matching(systemPromptTemp)?.id ?? "custom" },
            set: { id in
                if let preset = PromptPresets.preset(withID: id) {
                    systemPromptTemp = preset.prompt
                }
            }
        )
    }

    private func modelDescription(for model: String) -> String {
        ModelCatalog.info(for: model)?.summary ?? ""
    }

    /// Display name for the currently selected TTS voice (or "Automatic").
    private var selectedVoiceName: String {
        let id = store.selectedVoiceID
        if id.isEmpty { return "Automatic" }
        if let voice = store.availableVoices().first(where: { $0.identifier == id }) {
            return voice.name
        }
        return "Automatic"
    }
}

// MARK: - MessageBubbleView (restored and optimized to prevent compiler bottlenecks)
struct MessageBubbleView: View {
    let message: ChatMessageData
    let onPlayAudio: (Data) -> Void
    var onSpeak: ((String) -> Void)? = nil

    /// Speaker button shows on assistant text replies (not the user's own
    /// messages, and not replies that already carry their own audio).
    private var canSpeak: Bool {
        onSpeak != nil && !message.isUser && message.audioData == nil
            && !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Render assistant replies as Markdown (bold, lists, code spans, links);
    /// keep user text verbatim.
    private var formattedContent: AttributedString {
        let textToShow = message.displayContent ?? message.content
        if message.isUser {
            return AttributedString(textToShow)
        }
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let parsed = try? AttributedString(markdown: textToShow, options: options) {
            return parsed
        }
        return AttributedString(textToShow)
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
                    if canSpeak {
                        Button {
                            onSpeak?(message.content)
                        } label: {
                            Label("Speak", systemImage: "speaker.wave.2")
                        }
                    }
                }
                
                if let thinkingLog = message.thinkingLog, !thinkingLog.isEmpty {
                    ThinkingLogView(log: thinkingLog)
                        .padding(.top, 2)
                        .padding(.bottom, 2)
                }

                // Footnote: speaker button + speed
                if canSpeak || message.speed != nil {
                    HStack(spacing: 10) {
                        if canSpeak {
                            Button {
                                onSpeak?(message.content)
                            } label: {
                                Image(systemName: "speaker.wave.2.fill")
                            }
                            .buttonStyle(.borderless)
                        }
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

struct ThinkingLogView: View {
    let log: String
    @State private var isExpanded = false
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.russian.rawValue
    
    private var formattedLog: AttributedString {
        var translatedLog = log
        if appLanguage == AppLanguage.russian.rawValue {
            translatedLog = translatedLog
                .replacingOccurrences(of: "👁️ **Apple Vision Perceptions:**", with: "👁️ **Восприятие Apple Vision:**")
                .replacingOccurrences(of: "- Classifications:", with: "- Классификации:")
                .replacingOccurrences(of: "- Text:", with: "- Считанный текст:")
                .replacingOccurrences(of: "- 🌟 Trained Object:", with: "- 🌟 Выученный объект:")
                .replacingOccurrences(of: "🧠 **Cognitive Hypothesis:**", with: "🧠 **Когнитивная гипотеза:**")
                .replacingOccurrences(of: "🎭 **Adapted Persona:**", with: "🎭 **Адаптированная роль:**")
        }
        
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let parsed = try? AttributedString(markdown: translatedLog, options: options) {
            return parsed
        }
        return AttributedString(translatedLog)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.footnote)
                    Text(AppText.get(.thinkingLogTitle, lang: appLanguage))
                        .font(.footnote)
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(uiColor: .systemGroupedBackground))
                .cornerRadius(8)
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text(formattedLog)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .lineSpacing(4)
                }
                .padding(12)
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(8)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .frame(maxWidth: 300)
    }
}
