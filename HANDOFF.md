# HANDOFF — session continuation notes

> For a new working session (any machine, any agent): read this first, then
> [README.md](README.md) for the product picture and [REPORT.md](REPORT.md)
> for deep architecture. This file tracks *in-flight* state that isn't obvious
> from the code.

_Last updated: 2026-07-08_

## Where things stand

- **`Real-world` = `main`** — current stable line. Latest: dev-UI merge (SF
  Symbols, AnimatedMeshBackground as hero-moment, 44pt targets, glass cards,
  dock with voice+camera) + ADA interaction layer (scrollTransition,
  jump-to-latest pill, dock focus glow, numeric transitions, staggered empty
  state, breathing focus brackets) + tap-to-focus recognition zone.
- **`3d` branch** — experimental LiDAR surface scan (`DepthScanView`): dot
  field over real relief + depth-phased scanning wave. Works on device.
  Not merged; entry: camera menu → "3D Scan".
- Tags: `stable-agent-vision`, `working-v1`, `archive/*` — rollback points.

## In flight right now

**Xcode 26 installation.** Disk was cleaned (19 → 40 GB free) by deleting
recreatable dev caches (iOS DeviceSupport, DerivedData, simulators — first
device connect after this is slow while support files regenerate). User was
installing Xcode 26 from the Mac App Store (replaces Xcode 16.4; Intel Macs
are supported, macOS 14.5+ required, AI-assist features excluded on Intel).

**After Xcode 26 lands, the plan is:**
1. `sudo xcodebuild -license accept && xcodebuild -runFirstLaunch`
2. Rebuild the app → **system Liquid Glass activates automatically** on the
   iOS 27 device (nav bars, menus, sheets) just from building with the new SDK.
3. Manual glass adoption on custom surfaces (`.glassEffect()`,
   `GlassEffectContainer`): the floating input dock, dsCard surfaces,
   FocusOverlay chips. All styling flows through `Sources/DesignSystem.swift`
   tokens — adopt there, not per-screen.
4. Consider bumping deployment target (currently iOS 18.0).

## Agreed next steps (ranked, from the SOTA research)

1. **MobileCLIP2 swap** — drop-in accuracy upgrade for zero-shot recognition.
   Re-run the vocabulary precompute with v2 encoders (same CLIP BPE tokenizer).
   Pipeline reference: `Resources/clip_vocabulary.txt` →
   `clip_vocab_embeddings.bin` (+ labels json); the original precompute used a
   python3.9 venv + coremltools + `apple/coreml-mobileclip` text encoder on the
   Mac; only the *image* encoder ships in `MLModels/`.
2. **Foreground segmentation** (`VNGenerateForegroundInstanceMaskRequest`,
   iOS 17+) before feature prints — removes the background-in-the-print
   weakness of instance memory; enables a dim-background training effect.
3. **FastVLM-0.5B (Core ML, apple/fastvlm on HF)** — give the agent real
   scene understanding instead of label+facts narration. Biggest capability
   jump; mind RAM contention with the LFM (consider it the agent-mode brain).
4. **ARKit scene reconstruction** for the `3d` branch — real mesh instead of
   per-frame dot sampling.
5. **Object Capture** (RealityKit) — teaching an object also yields a USDZ
   model + multi-view prints.

## Pending user-facing items

- **LinkedIn post**: EN draft delivered (hook: "My iPhone just asked me — out
  loud — what to call an object…"; tags: #EdgeAI #OnDeviceAI #AIAgents
  #ProductDesign #BuildInPublic; @-mention Liquid AI in the stack line).
  Waiting on a 30–45 s demo video (tap-to-focus → agent asks → user names →
  re-recognition). The same video should become the README hero.
- README has no screenshots/GIF yet.

## Workflow quirks that cost time if forgotten

- **Device-only builds** (LEAP SDK is arm64-only; Intel Mac simulator is
  x86_64). Device: iPhone 14 Pro Max, id `00008120-00046C2A348BC01E`, iOS 27.
- Launching via `devicectl` fails when the phone is **locked** — ask the user
  to unlock, or have them tap the app icon.
- **Don't install the app while tests run** on the device — it replaces the
  test host and the run fails spuriously.
- Regenerate the project after touching `project.yml` or adding files:
  `xcodegen generate`. Helper: `./run.sh` (build+install+launch), `./run.sh test`.
- zsh word-splitting: `for i in $VAR` does NOT split — use explicit lists.
- Agent Vision debug: console prints `[CLIP] top: …`, `[Agent] narrate/ask…`,
  `[KnowledgeGraph] …`, `[TrainedObjects] best print score…` — capture via
  `xcrun devicectl device process launch --console`.
