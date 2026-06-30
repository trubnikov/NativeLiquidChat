# NativeLiquidChat — Technical Report

> A detailed, self-contained description of the application: what it does, how it
> is built, every feature, and the architecture. Written so that another AI (or
> engineer) can fully understand the project without reading the source.

---

## 1. One-paragraph summary

**NativeLiquidChat** is a native iOS (SwiftUI) chat application that runs Liquid
AI's **LFM2 / LFM2.5** language, vision, and audio models **entirely on-device**
via the **LEAP SDK** (`Liquid4All/leap-sdk`). There are no network calls for
inference: the user downloads models to the phone, loads them into memory, and
chats with them offline. The app supports text chat, image understanding
(vision models), audio in/out (audio model), on-device text-to-speech of
replies, and a fully offline **hands-free voice conversation mode**
(speech-to-text → LLM → text-to-speech loop). Models are managed in an LM
Studio–style library with per-device fit checks.

---

## 2. Platform, toolchain & constraints

| Item | Value |
|---|---|
| UI framework | SwiftUI (`@Observable` state, iOS 17 SDK features) |
| Language | Swift 5.9 |
| Deployment target | iOS 17.0 |
| Project generation | **XcodeGen** (`project.yml` → `.xcodeproj`; the `.xcodeproj` is generated, not hand-edited) |
| Inference SDK | LEAP SDK `Liquid4All/leap-sdk` ≥ 0.10.0 (products: `LeapSDK`, `LeapModelDownloader`) |
| Dev machine | **Intel Mac**, **Xcode 16.4** (iOS 18.5 SDK), macOS 15.7 |
| Test device | iPhone 14 Pro Max, **iOS 27** (6 GB RAM) |

**Hard constraints discovered during development (important for any future work):**

1. **arm64-only SDK.** The LEAP `xcframework` ships **only `arm64`** slices
   (`ios-arm64`, `ios-arm64-simulator`, `macos-arm64`) — **no `x86_64`**. The dev
   Mac is Intel, whose iOS Simulator is `x86_64`. Therefore the app **cannot be
   built or run in the Simulator on this machine**; it must be built for a
   **physical device**. A Simulator build fails with a flood of misleading
   "no member / cannot find symbol" errors whose real cause is the missing
   architecture.
2. **No Liquid Glass from code on this toolchain.** The iOS 26 `.glassEffect(...)`
   API lives in the iOS 26 SDK (Xcode 26). Xcode 16's SDK (18.5) does not contain
   it, so calling it does not compile. The app instead relies on **system
   controls and materials** (`.bar`, `.regularMaterial`, native toolbars,
   menus) — iOS 26/27 renders *those* in Liquid Glass automatically. Custom
   views cannot be glass-styled until Xcode 26 is installed.

**Signing:** automatic, `DEVELOPMENT_TEAM = Q4MWQ3X44V`.

**Build/run helper:** `run.sh` (regenerate → build → install → launch on device;
`./run.sh test` runs the unit tests on device).

---

## 3. Source map (what each file does)

All under `Sources/` unless noted. ~2,800 lines total.

### App shell & state
- **`NativeLiquidChatApp.swift`** — `@main` entry. Applies the chosen color
  scheme (`AppTheme`) via `.preferredColorScheme`.
- **`ContentView.swift`** (~547 lines) — the entire UI: `NavigationSplitView`
  (sidebar = chat history; detail = active chat), native bottom input bar via
  `.safeAreaInset(edge:.bottom)`, message list, toolbar (voice-conversation
  toggle, speak toggle, settings), settings sheet (system prompt, model picker,
  Speech section, Appearance/theme), and `MessageBubbleView`.
- **`ChatStore.swift`** (~572 lines) — `@Observable` central state and
  orchestration: sessions CRUD, model loading, message send/stream,
  audio recording prompt, **TTS**, and **hands-free conversation mode** state
  machine. Single source of truth, driven on the main thread.

### Data & persistence
- **`Models.swift`** — `ChatMessageData` (id, content, isUser, timestamp,
  optional `imageData`/`audioData`, optional `speed` tokens/s), `ChatSession`
  (id, title, modelName, systemPrompt, messages, createdAt; computed
  `iconName`), and `ChatStorage` (load/save all sessions to
  `Documents/chat_sessions.json` via `Codable`, atomic + file protection).

### Model library
- **`ModelCatalog.swift`** — `ModelInfo` (id/displayName/kind/quantization/
  summary/`approxBytes`/`minRAMBytes`), `ModelInfo.Kind` (text/vision/audio with
  icons), `ModelDiskStatus` (notDownloaded / downloading(bytes) / downloaded),
  `ModelFit` (fits / heavy / wontFit / noSpace), and the hardcoded catalog of 7
  models.
- **`ModelManager.swift`** — `@Observable @MainActor`. Per-model on-disk status
  (reads the `leap_models/<id>-<quant>/` folder directly — robust, no URL
  resolution), download via `Leap.shared.load` with a byte-progress poller,
  delete (folder + SDK), and **device fit check** using `physicalMemory` and
  free disk capacity.
- **`ModelsView.swift`** — LM-Studio-style library screen: device capacity
  header, models grouped by type, size + colored fit badge per model,
  download/activate/delete, swipe-to-delete.

### Audio in/out (LEAP audio model path)
- **`AudioRecorder.swift`** — `AVAudioEngine` mic capture → `[Float]` samples
  (for the LFM Audio model).
- **`AudioPlaybackManager.swift`** — `AVAudioEngine` playback of model-generated
  audio (streamed PCM samples and WAV data).
- **`CameraPicker.swift`** — `UIImagePickerController` wrapper for camera capture.

### Speech features (Apple, on-device)
- **`SpeechManager.swift`** — **Text-to-Speech** via `AVSpeechSynthesizer`.
  Language detection (`NaturalLanguage`), voice selection (prefers
  enhanced/premium), `.playback/.spokenAudio/.defaultToSpeaker` session,
  persisted chosen voice, preview, `onFinishSpeaking` callback.
- **`SpeechRecognizer.swift`** — **Speech-to-Text** via `SFSpeechRecognizer`
  with `requiresOnDeviceRecognition = true` (strictly offline). Streams mic
  audio, reports partial transcripts, and detects end-of-utterance via a
  trailing-silence timer (~1.6 s).
- **`VoicePickerView.swift`** — settings screen to choose the TTS voice (grouped
  by language, Enhanced/Premium badges, tap-to-preview) or "Automatic".

### UI components
- **`TypingIndicator.swift`** — animated three-dot "assistant is typing" bubble.
- **`EmptyChatView.swift`** — model-aware empty state with tappable example
  prompts.
- **`ConversationBanner.swift`** — status strip for voice mode
  (Listening/Thinking/Speaking + live transcript).
- **`AppTheme.swift`** — System / Light / Dark enum, persisted via `@AppStorage`.

### Tests (`Tests/`, XCTest, run on device)
- **`ModelsTests.swift`**, **`ChatStorageTests.swift`**, **`ChatStoreTests.swift`**
  — 18 unit tests for model `Codable` round-trips, `iconName` logic, JSON
  storage round-trips, and session CRUD/selection logic. (These do not exercise
  the SDK; they must run on device because the test bundle links the app.)

---

## 4. Feature catalog (what the app can do)

### 4.1 Local model inference (core)
- Runs LFM2/LFM2.5 models **fully on-device, offline**, via
  `Leap.shared.load(model:quantization:options:progress:)`.
- Context size 2048; quantization `Q4_0`.
- **Streaming** token output with a live typing indicator and tokens/sec metric.
- **Stop** button cancels generation mid-stream.

### 4.2 Multimodal input/output
- **Text chat** (LFM Instruct).
- **Vision** (LFM VL): attach an image from **Photo Library** (`.photosPicker`)
  or **Camera**; the image is sent as `ChatMessageContent.fromUIImage` alongside
  text; the reply describes/answers about the image. (Markdown text reply with a
  fallback to streamed text if the completion carries no text part.)
- **Audio** (LFM Audio): record a voice prompt with the mic; the model returns
  audio that is played back; user/assistant audio messages have play buttons.

### 4.3 Model library (LM Studio–style) — `ModelsView`
- Catalog of **7 models** grouped Text / Vision / Audio:
  `LFM2-350M`, `LFM2-700M`, `LFM2.5-1.2B-Instruct`, `LFM2-2.6B` (text),
  `LFM2.5-VL-450M`, `LFM2.5-VL-1.6B` (vision), `LFM2.5-Audio-1.5B` (audio).
- Per model: **download size**, **on-disk status**, **download** (with live
  byte progress polled from disk), **activate** (load into memory), **delete**
  (swipe), and a **device-fit badge**:
  - 🟢 *Fits well* — runs comfortably,
  - 🟠 *Heavy* — runs but uses a lot of memory,
  - 🔴 *Too large* — exceeds device RAM (download blocked),
  - 🔴 *No space* — not enough free storage (download blocked).
- Fit is computed from **actual** `ProcessInfo.physicalMemory` and free disk
  (`volumeAvailableCapacityForImportantUsage`), with the rule "an app may use
  ~55% of RAM before jetsam".
- Header shows the device's memory and free storage.

### 4.4 Chat management
- Multiple chat **sessions** (sidebar list), each with its own model + system
  prompt + history. Create / rename / delete (context menu + swipe). Persisted
  to JSON; survives relaunch.
- Per-session **system prompt** and **model** selection in the settings sheet.

### 4.5 On-device Text-to-Speech
- After a **text** reply completes, it is **read aloud** (if enabled), using
  Apple `AVSpeechSynthesizer` — offline.
- **Auto voice selection** by the reply's detected language, preferring
  **enhanced/premium** voices when installed; or a **user-chosen voice**
  (`VoicePickerView`, with preview).
- Per-reply **speaker button**; global **speak toggle** in the toolbar and in
  Settings → Speech. New replies stop any in-progress speech. Replies that carry
  their own model audio are not double-spoken.

### 4.6 Hands-free voice conversation mode (offline)
- A continuous loop: **listen → recognize (on-device STT) → LFM answers →
  speak (TTS) → listen again**, with no button presses.
- **End-of-turn detection** by ~1.6 s of trailing silence.
- The mic is muted while the assistant speaks (prevents self-hearing); listening
  resumes automatically after the reply is spoken.
- A **status banner** shows *Listening… / Thinking… / Speaking…* plus the live
  transcript. Toggled by a waveform button in the toolbar.
- Strictly offline (`requiresOnDeviceRecognition = true`); requires an installed
  on-device recognition language (typically the system language + English).

### 4.7 UI/UX polish
- **Native-first styling**: system materials and native toolbars/menus so iOS
  renders Liquid Glass itself; system colors that respect Dark Mode.
- **Theme switcher**: System / Light / Dark (persisted).
- **Markdown rendering** + selectable text in assistant bubbles; Copy / Share /
  Speak context menu; width-limited bubbles.
- Smooth auto-scroll, spring message transitions, typing indicator, haptics on
  send/receive/record/copy, model-aware empty state with tappable prompts.

---

## 5. Key control flows

### 5.1 Sending a text message
`ContentView` send button → `ChatStore.sendMessage(text, attachedImage:)`
→ `ensureModelLoaded(modelName)` (loads via `Leap.shared.load`, downloading on
first use) → build `ChatMessage` (text and/or image content) → append user
message → `setupConversationIfNeeded` (builds history with system prompt) →
`streamResponse` consumes the SDK event stream.

### 5.2 Streaming events (`handleEvent`)
- `.chunk` → append token text to `currentAssistantMessage` (live UI).
- `.audioSample` → enqueue PCM to `AudioPlaybackManager` (audio model).
- `.complete` → assemble final text (falls back to streamed text if the
  completion has no text part), capture tokens/sec, append the assistant
  message, then: play model audio **or** speak text via TTS (if enabled) **or**,
  in conversation mode with nothing to speak, resume listening.

### 5.3 Conversation-mode state machine (`ChatStore`)
`idle → listening → thinking → speaking → listening …`
- `startConversation()` requests speech+mic permission, forces `speakResponses`
  on, calls `beginListening()`.
- `beginListening()` wires `SpeechRecognizer` callbacks; on `onFinished`
  (silence) with non-empty text → phase `thinking` → `sendMessage`.
- `.complete` with a spoken reply → phase `speaking`; TTS `onFinishSpeaking`
  → `conversationDidFinishSpeaking()` → `beginListening()` again.
- `stopConversation()` tears everything down.

### 5.4 Model download & status (`ModelManager`)
- `download(model)` sets `.downloading`, starts a poller that reads the model
  folder size every 0.7 s (because `Leap.shared.load` doesn't stream byte
  progress), awaits the load, releases the in-memory runner (keeping weights on
  disk), then refreshes status.
- `refresh(model)` checks the on-disk folder for a `.gguf` file → downloaded +
  size, else not-downloaded. Crash-free (no manifest/URL resolution).
- `delete(model)` removes the folder directly, then calls the SDK remove.

---

## 6. Important engineering decisions & fixes

- **Crash fix — model load.** An earlier version used the low-level
  `ModelDownloader` with `baseUrl: nil`, which built an invalid URL and threw
  from a **Kotlin coroutine** inside the SDK; the error escaped Swift `try/catch`
  and aborted the process (SIGABRT). Replaced with the high-level
  `Leap.shared.load`, which resolves/downloads and throws **catchable** Swift
  errors. (The low-level downloader is now used only for safe read/delete ops,
  each wrapped in `do/catch`.)
- **Model storage path.** `Leap.shared.load` stores weights under
  **`Documents/leap_models`**. The status reader must use the same path (an
  earlier mismatch with `applicationSupport` made downloaded models read as
  "not downloaded").
- **PhotosPicker fix.** `PhotosPicker` nested inside a `Menu` would not present;
  replaced with `.photosPicker` modifier driven by a `confirmationDialog`.
- **Vision empty reply.** Some VL completions carry no text part; the code falls
  back to the streamed chunk text so the reply isn't shown as empty.
- **Actor isolation.** Speech callbacks bridge non-isolated AVFoundation
  delegates back to `@MainActor` via `Task { @MainActor in … }`.

---

## 7. Permissions (Info.plist usage strings)
- `NSCameraUsageDescription` — capture images for the vision model.
- `NSMicrophoneUsageDescription` — capture audio prompts / voice input.
- `NSSpeechRecognitionUsageDescription` — on-device speech-to-text for
  hands-free conversation.
- `NSPhotoLibraryUsageDescription` — pick images for the vision model.

---

## 8. Privacy posture
- **All inference is on-device.** No model or chat data leaves the phone for the
  LLM/VLM/audio path.
- **TTS** is Apple on-device synthesis.
- **STT** is forced on-device (`requiresOnDeviceRecognition = true`); no audio is
  sent to Apple's servers (at the cost of language coverage).
- Chats and attached media persist locally in `Documents/chat_sessions.json`.

---

## 9. Repository state
- **Branch `feature/multimodal-support`** — main working line: crash fix, model
  manager, native UI polish, tests (commit `521ae4c`).
- **Branch `feature/speech-tts`** (current) — adds on-device TTS + voice
  selection (commit `57d337e`); the **hands-free conversation mode** changes are
  staged on top (not yet committed at time of writing).
- Remote: `github.com/trubnikov/NativeLiquidChat`.

---

## 10. Known limitations / future work
- No Liquid Glass on custom views until **Xcode 26** is installed (toolchain
  limitation, not a code issue).
- On-device STT language coverage depends on what the device has installed;
  no in-app language picker for recognition yet.
- Model catalog sizes/RAM are **estimates** hardcoded in `ModelCatalog`
  (the SDK doesn't expose size before download); actual size is shown after
  download.
- No "barge-in" (interrupting the spoken reply by talking over it).
- Conversation history rebuilt for the SDK uses text only; image/audio
  attachments are not replayed into a re-initialized conversation context.
- Tests cover storage/session logic only; inference, audio, STT/TTS are
  verified manually on device.
