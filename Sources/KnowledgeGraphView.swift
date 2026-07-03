import SwiftUI

struct KnowledgeGraphView: View {
    @ObservedObject var graphManager = KnowledgeGraphManager.shared
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.russian.rawValue
    
    // Add Document states
    @State private var showingAddDoc = false
    @State private var docTitle = ""
    @State private var docContent = ""
    
    // Add Relation states
    @State private var showingAddRelation = false
    @State private var sourceNodeId: UUID? = nil
    @State private var targetNodeId: UUID? = nil
    @State private var relationType = ""
    
    var body: some View {
        Form {
            // Action Buttons Section
            Section {
                Button(action: {
                    docTitle = ""
                    docContent = ""
                    showingAddDoc = true
                }) {
                    Label(AppText.get(.addDocumentButton, lang: appLanguage), systemImage: "doc.badge.plus")
                }
                
                Button(action: {
                    relationType = ""
                    sourceNodeId = graphManager.nodes.first?.id
                    targetNodeId = graphManager.nodes.dropFirst().first?.id ?? graphManager.nodes.first?.id
                    showingAddRelation = true
                }) {
                    Label(AppText.get(.addRelationButton, lang: appLanguage), systemImage: "arrow.triangle.merge")
                }
                .disabled(graphManager.nodes.count < 2)
            } header: {
                Text(AppText.get(.ragHeader, lang: appLanguage))
            } footer: {
                Text(AppText.get(.ragFooter, lang: appLanguage))
            }
            
            // Nodes Section
            Section(header: Text(AppText.get(.nodesSection, lang: appLanguage))) {
                if graphManager.nodes.isEmpty {
                    Text(AppText.get(.noData, lang: appLanguage))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(graphManager.nodes) { node in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(node.label)
                                    .fontWeight(.medium)
                                Text(nodeTypeLabel(node.type))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if let text = node.properties["text"] {
                                Text(text)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 150)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            let node = graphManager.nodes[idx]
                            graphManager.deleteNode(id: node.id)
                        }
                    }
                }
            }
            
            // Edges Section
            Section(header: Text(AppText.get(.edgesSection, lang: appLanguage))) {
                if graphManager.edges.isEmpty {
                    Text(AppText.get(.noData, lang: appLanguage))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(graphManager.edges) { edge in
                        let sourceName = graphManager.nodes.first(where: { $0.id == edge.sourceId })?.label ?? "Unknown"
                        let targetName = graphManager.nodes.first(where: { $0.id == edge.targetId })?.label ?? "Unknown"
                        
                        HStack {
                            Text(sourceName)
                                .fontWeight(.semibold)
                            Text("--(\(edge.relationType))-->")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(targetName)
                                .fontWeight(.semibold)
                        }
                        .font(.footnote)
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            let edge = graphManager.edges[idx]
                            graphManager.deleteEdge(id: edge.id)
                        }
                    }
                }
            }
        }
        .navigationTitle(AppText.get(.ragTitle, lang: appLanguage))
        .navigationBarTitleDisplayMode(.inline)
        // Add Document Sheet
        .sheet(isPresented: $showingAddDoc) {
            NavigationStack {
                Form {
                    Section {
                        TextField(AppText.get(.documentTitlePlaceholder, lang: appLanguage), text: $docTitle)
                        TextEditor(text: $docContent)
                            .frame(minHeight: 200)
                            .overlay(
                                Group {
                                    if docContent.isEmpty {
                                        Text(AppText.get(.documentContentPlaceholder, lang: appLanguage))
                                            .foregroundColor(.gray.opacity(0.5))
                                            .padding(.top, 8)
                                            .padding(.leading, 5)
                                    }
                                },
                                alignment: .topLeading
                            )
                    }
                }
                .navigationTitle(AppText.get(.addDocumentButton, lang: appLanguage))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(AppText.get(.buttonCancel, lang: appLanguage)) {
                            showingAddDoc = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(AppText.get(.buttonSave, lang: appLanguage)) {
                            let title = docTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                            let content = docContent.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !title.isEmpty && !content.isEmpty {
                                graphManager.importDocument(title: title, content: content)
                                showingAddDoc = false
                            }
                        }
                        .disabled(docTitle.isEmpty || docContent.isEmpty)
                    }
                }
            }
        }
        // Add Relation Sheet
        .sheet(isPresented: $showingAddRelation) {
            NavigationStack {
                Form {
                    Section(header: Text(AppText.get(.linkSubtitle, lang: appLanguage))) {
                        Picker(AppText.get(.sourceNodeLabel, lang: appLanguage), selection: $sourceNodeId) {
                            ForEach(graphManager.nodes) { node in
                                Text("\(node.label) (\(nodeTypeLabel(node.type)))")
                                    .tag(node.id as UUID?)
                            }
                        }
                        
                        Picker(AppText.get(.targetNodeLabel, lang: appLanguage), selection: $targetNodeId) {
                            ForEach(graphManager.nodes) { node in
                                Text("\(node.label) (\(nodeTypeLabel(node.type)))")
                                    .tag(node.id as UUID?)
                            }
                        }
                        
                        TextField(AppText.get(.relationTypePlaceholder, lang: appLanguage), text: $relationType)
                    }
                }
                .navigationTitle(AppText.get(.linkTitle, lang: appLanguage))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(AppText.get(.buttonCancel, lang: appLanguage)) {
                            showingAddRelation = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(AppText.get(.buttonSave, lang: appLanguage)) {
                            if let src = sourceNodeId, let tgt = targetNodeId, !relationType.isEmpty {
                                graphManager.addEdge(sourceId: src, targetId: tgt, relationType: relationType)
                                showingAddRelation = false
                            }
                        }
                        .disabled(sourceNodeId == nil || targetNodeId == nil || relationType.isEmpty)
                    }
                }
            }
        }
    }
    
    private func nodeTypeLabel(_ type: NodeType) -> String {
        switch type {
        case .object: return appLanguage == "ru" ? "Предмет" : "Object"
        case .concept: return appLanguage == "ru" ? "Понятие" : "Concept"
        case .document: return appLanguage == "ru" ? "Документ RAG" : "RAG Chunk"
        }
    }
}
