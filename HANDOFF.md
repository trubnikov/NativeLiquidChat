# HANDOFF — session continuation notes

> For a new working session (any machine, any agent): read this first, then
> [README.md](README.md) for the product picture and [REPORT.md](REPORT.md)
> for deep architecture. This file tracks *in-flight* state that isn't obvious
> from the code.

_Last updated: 2026-08-24_

## Where things stand

- **Repo location:** `~/Work/ios-apps/native-liquid-chat` (moved 2026-08-18;
  the old `Dima Kernel/Website` path is gone).
- **`Real-world` = `main`** — stable line. Includes: Xcode 26 rebuild →
  system Liquid Glass + manual `.glassEffect()` adoption (DesignSystem
  tokens), live SF symbol effects, 3-mode 3D scanner (Wave dot-field with
  snow accumulation / ARKit reconstruction Mesh / RoomPlan Room),
  **depth-gated recognition** (LiDAR background masking before CLIP/feature
  prints, distance in the focus chip).
- **`fix/product-audit`** — product-readiness audit fixes (privacy manifest,
  versioning, first-run CTA, permission dead-ends, Reduce Motion, VoiceOver,
  audio-session release, stale-index streaming fix, repo hygiene).
- **Private lab:** experiments live in the second remote `lab`
  (https://github.com/trubnikov/NativeLiquidChat-lab, private). Branch
  `lab/object-capture` = Object Capture experiment (photorealistic USDZ of an
  object, AR Quick Look). Push experiments with `git push lab <branch>`;
  only merged, mature work goes to public `origin`.

## Product backlog

Prioritized RICE backlog with full specs lives in Notion:
**"NativeLiquidChat — Product Backlog: Unique Capability Chains"**
(P0 depth-gating — done; next: P1 size-aware recognition, P1 voice object
finder, P2 spatial narrator, P2 point-and-explain, P3 spatial memory palace).

## Known debt (from the 2026-08-24 audit, not yet fixed)

- Localization: AgentVision / DepthScan / ModelsView / VoicePicker /
  ObjectCapture screens are English-only; ContentView mixes inline ternaries
  with the `AppText` system. Full pass needed.
- Audio-session single owner: `setActive(false)` now happens in
  `stopConversation`, but SpeechManager/AudioRecorder/AudioPlayback still
  configure independently.
- `recordingStatus` / `executionStatus` are computed but not rendered.
- Tests cover only serialization/CRUD; cosine matching, graph traversal, and
  AppText parity are untested pure functions.
- App icon: single 1024 PNG, no dark/tinted variants; verify sRGB profile
  before archiving.

## Workflow quirks that cost time if forgotten

- **Device-only builds** (LEAP SDK is arm64-only; Intel Mac simulator is
  x86_64). Device: iPhone 14 Pro Max, iOS 27. Two id spaces, both valid:
  - `xcodebuild -destination 'platform=iOS,id=00008120-00046C2A348BC01E'` (UDID)
  - `devicectl` also accepts CoreDevice UUID `024A4A30-2146-5D7E-8C4B-7AA13A4C4CF0`
- Launching via `devicectl` fails when the phone is **locked** — ask the user
  to unlock, or have them tap the app icon.
- **Don't install the app while tests run** on the device — it replaces the
  test host and the run fails spuriously.
- Regenerate after touching `project.yml` or adding files: `xcodegen generate`.
  Helper: `./run.sh` (build+install+launch), `./run.sh test`.
- Xcode 26.3 on this Mac (Intel, Sequoia): App Store auto-installed the last
  compatible version. If a build errors "iOS X.Y is not installed", run
  `xcodebuild -downloadPlatform iOS`; Metal shaders need
  `xcodebuild -downloadComponent MetalToolchain` (one-time).
- Agent Vision debug: console prints `[CLIP] top: …`, `[DepthGate] d0=…`,
  `[Agent] …`, `[KnowledgeGraph] …` — capture via
  `xcrun devicectl device process launch --console`.
