import Foundation
import AVFoundation

class SystemTools {
    
    static let systemPromptExtension = """

You are an advanced iOS Voice Assistant. You run locally on the user's iPhone and can control hardware and read system info.

You have access to the following tools:
1. `getCurrentTime()`: Returns the current date and time.
2. `toggleFlashlight(enabled: Bool)`: Turns the physical camera flashlight on (`true`) or off (`false`).

To call a tool, you MUST write the exact format:
[TOOL_CALL: name(param=value)]

Examples:
- To turn on the flashlight: [TOOL_CALL: toggleFlashlight(enabled=true)]
- To check time: [TOOL_CALL: getCurrentTime()]

Do not output anything else in the same message when calling a tool. After you call it, you will receive the result in the next turn and can explain it to the user.
"""

    @MainActor
    static func executeTool(callString: String) -> String {
        let trimmed = callString.trimmingCharacters(in: .whitespacesAndNewlines)
        print("Executing tool call: \(trimmed)")
        
        if trimmed.contains("getCurrentTime") {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .medium
            return "Current time is \(formatter.string(from: Date()))"
        }
        
        if trimmed.contains("toggleFlashlight") {
            let enabled = trimmed.contains("enabled=true") || trimmed.contains("enabled:true")
            return toggleFlashlight(enabled: enabled)
        }
        
        return "Unknown tool call format."
    }
    
    private static func toggleFlashlight(enabled: Bool) -> String {
        guard let device = AVCaptureDevice.default(for: .video) else {
            return "Flashlight is not available on this device."
        }
        
        guard device.hasTorch else {
            return "Flashlight torch is not supported on this device."
        }
        
        do {
            try device.lockForConfiguration()
            if enabled {
                try device.setTorchModeOn(level: 1.0)
                device.unlockForConfiguration()
                return "Flashlight turned ON."
            } else {
                device.torchMode = .off
                device.unlockForConfiguration()
                return "Flashlight turned OFF."
            }
        } catch {
            return "Failed to toggle flashlight: \(error.localizedDescription)"
        }
    }
}
