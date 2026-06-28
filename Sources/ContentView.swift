import SwiftUI

struct ContentView: View {
    @State private var store = ChatStore()
    @State private var inputText = ""
    @State private var showingSettings = false
    @State private var systemPromptTemp = ""
    @State private var renameTemp = ""
    @State private var showingRenameAlert = false
    @State private var sessionToRename: UUID?
    
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        NavigationSplitView {
            // SIDEBAR: Chat History List
            List(selection: $store.currentSessionId) {
                Section(header: Text("History")) {
                    ForEach(store.sessions) { session in
                        NavigationLink(value: session.id) {
                            HStack {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .foregroundColor(.blue)
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
            }
        } detail: {
            // DETAIL VIEW: Active Chat Screen
            if let session = store.currentSession {
                ZStack {
                    // Background
                    Color(uiColor: .systemGroupedBackground)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        // Custom Navigation Bar / Model Selector
                        HStack {
                            Spacer()
                            ModelSelectorView(
                                currentModel: session.modelName,
                                isModelLoading: store.isModelLoading,
                                downloadProgress: store.downloadProgress,
                                onSelect: { selectedModel in
                                    store.updateModel(id: session.id, modelName: selectedModel)
                                }
                            )
                            Spacer()
                            
                            Button(action: {
                                systemPromptTemp = session.systemPrompt
                                showingSettings = true
                            }) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.title3)
                                    .padding(8)
                                    .background(.regularMaterial)
                                    .clipShape(Circle())
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        
                        // Messages ScrollView
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(spacing: 16) {
                                    if session.messages.isEmpty {
                                        VStack(spacing: 16) {
                                            Image(systemName: "brain.head.profile")
                                                .font(.system(size: 64))
                                                .foregroundColor(.blue)
                                                .padding(.top, 60)
                                            
                                            Text("Start a conversation with Liquid LFM")
                                                .font(.headline)
                                                .foregroundColor(.secondary)
                                            
                                            if !session.systemPrompt.isEmpty {
                                                Text("System: \(session.systemPrompt)")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .italic()
                                                    .multilineTextAlignment(.center)
                                                    .padding(.horizontal)
                                            }
                                        }
                                    }
                                    
                                    ForEach(session.messages) { msg in
                                        MessageBubbleView(message: msg)
                                    }
                                    
                                    // Streaming message
                                    if store.isLoadingResponse && !store.currentAssistantMessage.isEmpty {
                                        MessageBubbleView(message: ChatMessageData(content: store.currentAssistantMessage, isUser: false))
                                            .id("current")
                                    } else if store.isLoadingResponse {
                                        HStack {
                                            ProgressView()
                                                .padding()
                                            Spacer()
                                        }
                                        .id("loading")
                                    }
                                    
                                    Color.clear.frame(height: 20).id("bottom")
                                }
                                .padding()
                            }
                            .onChange(of: session.messages.count) {
                                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                            }
                            .onChange(of: store.currentAssistantMessage) {
                                withAnimation { proxy.scrollTo("current", anchor: .bottom) }
                            }
                        }
                        
                        // Glassmorphism Input Bar
                        VStack(spacing: 0) {
                            Divider()
                            HStack(alignment: .bottom, spacing: 12) {
                                TextField("Message LFM...", text: $inputText, axis: .vertical)
                                    .focused($isInputFocused)
                                    .lineLimit(1...5)
                                    .padding(12)
                                    .background(.regularMaterial)
                                    .cornerRadius(20)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                    )
                                
                                Button(action: {
                                    let text = inputText
                                    inputText = ""
                                    Task {
                                        await store.sendMessage(text)
                                    }
                                }) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 36))
                                        .symbolEffect(.bounce, value: inputText.isEmpty)
                                        .foregroundColor(!inputText.isEmpty && !store.isLoadingResponse ? .blue : .secondary)
                                }
                                .disabled(inputText.isEmpty || store.isLoadingResponse)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                        }
                    }
                }
                .navigationTitle(session.title)
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showingSettings) {
                    NavigationStack {
                        Form {
                            Section(header: Text("System Rules")) {
                                TextField("Act as a translator, coder, etc.", text: $systemPromptTemp, axis: .vertical)
                                    .lineLimit(4...10)
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
                                    showingSettings = false
                                }
                            }
                        }
                    }
                    .presentationDetents([.medium])
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
}

struct MessageBubbleView: View {
    let message: ChatMessageData
    
    var body: some View {
        HStack {
            if message.isUser { Spacer() }
            
            Text(message.content)
                .font(.body)
                .foregroundColor(message.isUser ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    message.isUser
                    ? LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [Color(uiColor: .secondarySystemGroupedBackground), Color(uiColor: .tertiarySystemGroupedBackground)], startPoint: .top, endPoint: .bottom)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
                .contextMenu {
                    Button(action: {
                        UIPasteboard.general.string = message.content
                    }) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            
            if !message.isUser { Spacer() }
        }
    }
}
