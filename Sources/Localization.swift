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
            }
        }
    }
}
