import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case russian = "ru"
    case english = "en"
    
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .russian: return "Русский"
        case .english: return "English"
        }
    }
}

struct AppText {
    static func get(_ key: Key, lang: String) -> String {
        let isRu = (lang == AppLanguage.russian.rawValue)
        return isRu ? key.ru : key.en
    }
    
    enum Key {
        // Chat Settings
        case settingsTitle
        case systemRulesHeader
        case systemRulesFooter
        case modelHeader
        case modelFooter
        case speechHeader
        case speechToggle
        case speechVoice
        case translationHeader
        case translationToggle
        case translationLanguage
        case appearanceHeader
        case appearanceTheme
        case memoryHeader
        case memoryFooter
        case memoryEmpty
        case buttonSave
        case buttonCancel
        
        // Thinking Log
        case thinkingLogTitle
        case visionPerceptions
        case classificationsLabel
        case textLabel
        case trainedObjectLabel
        case hypothesisLabel
        case personaLabel
        
        // Camera View
        case cameraScanning
        case cameraTrainedHeader
        case cameraTrainedSubtitle
        case cameraDominantPrompt
        case cameraRightPrompt
        case buttonYes
        case buttonNo
        case cameraPlaceholder
        case cameraPermissionRequired
        case buttonSettings
        case cameraSpeedFormat(Double)
        
        // Dialog
        case dialogTitle
        case dialogSubtitle
        case dialogPlaceholder
        case buttonRemember
        
        // RAG / Knowledge Graph
        case ragTitle
        case ragHeader
        case ragFooter
        case addDocumentButton
        case documentTitlePlaceholder
        case documentContentPlaceholder
        case addRelationButton
        case relationTypePlaceholder
        case linkTitle
        case linkSubtitle
        case nodesSection
        case edgesSection
        case noData
        case sourceNodeLabel
        case targetNodeLabel
        case selectNode
        
        var ru: String {
            switch self {
            case .settingsTitle: return "Настройки чата"
            case .systemRulesHeader: return "Системные правила"
            case .systemRulesFooter: return "Пресеты задают системный промпт. \"QCA · Ocean\" заставляет модель рассуждать как агент Ocean — кратко и ища противоречия."
            case .modelHeader: return "Модель"
            case .modelFooter: return "Выберите любую загруженную модель. Модель скачивается автоматически при первой отправке сообщения."
            case .speechHeader: return "Озвучка"
            case .speechToggle: return "Озвучивать ответы"
            case .speechVoice: return "Голос"
            case .translationHeader: return "Перевод"
            case .translationToggle: return "Переводить на английский"
            case .translationLanguage: return "Мой язык"
            case .appearanceHeader: return "Внешний вид"
            case .appearanceTheme: return "Тема"
            case .memoryHeader: return "Память объектов"
            case .memoryFooter: return "Список предметов, которым вы научили агента. Проведите пальцем влево для удаления."
            case .memoryEmpty: return "Нет выученных объектов"
            case .buttonSave: return "Сохранить"
            case .buttonCancel: return "Отмена"
            case .thinkingLogTitle: return "Когнитивный лог размышления"
            case .visionPerceptions: return "👁️ **Восприятие Apple Vision:**"
            case .classificationsLabel: return "Классификации"
            case .textLabel: return "Текст"
            case .trainedObjectLabel: return "Выученный объект"
            case .hypothesisLabel: return "🧠 **Когнитивная гипотеза:**"
            case .personaLabel: return "🎭 **Адаптированная роль:**"
            case .cameraScanning: return "Сканирую объект..."
            case .cameraTrainedHeader: return "ВЫУЧЕННЫЙ ОБЪЕКТ"
            case .cameraTrainedSubtitle: return "Агент узнал этот объект по сигнатуре!"
            case .cameraDominantPrompt: return "Кажется, это:"
            case .cameraRightPrompt: return "Я прав?"
            case .buttonYes: return "Да, верно"
            case .buttonNo: return "Нет, другое"
            case .cameraPlaceholder: return "Наведите камеру на объект в рамке"
            case .cameraPermissionRequired: return "Камере требуется разрешение"
            case .buttonSettings: return "Разрешить доступ в Настройках"
            case let .cameraSpeedFormat(ms): return String(format: "Скорость: %.1f мс (Vision + Similarity)", ms)
            case .dialogTitle: return "Чему научить агента?"
            case .dialogSubtitle: return "Введите точное имя для этого объекта:"
            case .dialogPlaceholder: return "Например: Кресло Босса"
            case .buttonRemember: return "Запомнить"
            case .ragTitle: return "База знаний RAG"
            case .ragHeader: return "Управление графом знаний"
            case .ragFooter: return "Здесь вы можете загружать текстовые файлы/инструкции и связывать распознанные объекты с концептами."
            case .addDocumentButton: return "Добавить документ"
            case .documentTitlePlaceholder: return "Название документа"
            case .documentContentPlaceholder: return "Содержимое документа..."
            case .addRelationButton: return "Создать связь"
            case .relationTypePlaceholder: return "Тип связи (например: содержит)"
            case .linkTitle: return "Связать объекты графа"
            case .linkSubtitle: return "Выберите исходный и целевой узлы и укажите тип связи:"
            case .nodesSection: return "Узлы (Документы и Объекты)"
            case .edgesSection: return "Связи между понятиями"
            case .noData: return "Нет данных"
            case .sourceNodeLabel: return "Исходный узел"
            case .targetNodeLabel: return "Целевой узел"
            case .selectNode: return "Выбрать узел"
            }
        }
        
        var en: String {
            switch self {
            case .settingsTitle: return "Chat Settings"
            case .systemRulesHeader: return "System Rules"
            case .systemRulesFooter: return "Presets set the system prompt. \"QCA · Ocean\" makes the model reason like the Ocean agent — terse and contradiction-seeking."
            case .modelHeader: return "Model"
            case .modelFooter: return "Pick any downloaded model. The model is downloaded automatically the first time you send a message."
            case .speechHeader: return "Speech"
            case .speechToggle: return "Speak replies"
            case .speechVoice: return "Voice"
            case .translationHeader: return "Translation"
            case .translationToggle: return "Translate to English"
            case .translationLanguage: return "My Language"
            case .appearanceHeader: return "Appearance"
            case .appearanceTheme: return "Theme"
            case .memoryHeader: return "Object Memory"
            case .memoryFooter: return "List of items you taught the agent. Swipe left to delete."
            case .memoryEmpty: return "No trained objects"
            case .buttonSave: return "Save"
            case .buttonCancel: return "Cancel"
            case .thinkingLogTitle: return "Cognitive Thinking Log"
            case .visionPerceptions: return "👁️ **Apple Vision Perceptions:**"
            case .classificationsLabel: return "Classifications"
            case .textLabel: return "Text"
            case .trainedObjectLabel: return "Trained Object"
            case .hypothesisLabel: return "🧠 **Cognitive Hypothesis:**"
            case .personaLabel: return "🎭 **Adapted Persona:**"
            case .cameraScanning: return "Scanning object..."
            case .cameraTrainedHeader: return "TRAINED OBJECT"
            case .cameraTrainedSubtitle: return "Agent recognized this object by signature!"
            case .cameraDominantPrompt: return "It seems to be:"
            case .cameraRightPrompt: return "Am I right?"
            case .buttonYes: return "Yes, correct"
            case .buttonNo: return "No, other"
            case .cameraPlaceholder: return "Point the camera at an object in the frame"
            case .cameraPermissionRequired: return "Camera permission required"
            case .buttonSettings: return "Allow access in Settings"
            case let .cameraSpeedFormat(ms): return String(format: "Speed: %.1f ms (Vision + Similarity)", ms)
            case .dialogTitle: return "What to teach the agent?"
            case .dialogSubtitle: return "Enter the exact name for this object:"
            case .dialogPlaceholder: return "Example: Boss Chair"
            case .buttonRemember: return "Remember"
            case .ragTitle: return "RAG Knowledge Base"
            case .ragHeader: return "Knowledge Graph Management"
            case .ragFooter: return "Here you can load text documents/manuals and connect recognized objects to concepts."
            case .addDocumentButton: return "Add Document"
            case .documentTitlePlaceholder: return "Document Title"
            case .documentContentPlaceholder: return "Document content..."
            case .addRelationButton: return "Create Relation"
            case .relationTypePlaceholder: return "Relation type (e.g. contains)"
            case .linkTitle: return "Connect Graph Nodes"
            case .linkSubtitle: return "Select source and target nodes and set the relation type:"
            case .nodesSection: return "Nodes (Documents & Objects)"
            case .edgesSection: return "Semantic Relations"
            case .noData: return "No data"
            case .sourceNodeLabel: return "Source Node"
            case .targetNodeLabel: return "Target Node"
            case .selectNode: return "Select node"
            }
        }
    }
}
