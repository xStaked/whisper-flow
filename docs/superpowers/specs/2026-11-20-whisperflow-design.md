# WhisperFlow — design

Date: 2026-11-20
Status: implemented (v0.1.0)

## Problem

Wispr Flow is paid (~12 USD/month) and sends audio to the cloud. We want the same
thing — hold a key, speak, and have the text appear in the active app — but free,
offline and without an account.

## MVP scope

In:

- Global hotkey: hold `fn` to record, release to transcribe.
- 100% local transcription with `whisper.cpp`.
- Insert the text into the focused app.
- Floating panel with recent texts and a copy button, as a safety net.
- Menu bar icon with state (idle / recording / transcribing).

Out (on purpose):

- LLM rewriting, voice commands, configurable punctuation.
- Style correction, synonyms, per-app "flow".
- Auto-update, notarisation, App Store.
- Hotkey configurable from the UI (changed in code if it ever matters).

## Decisions

### 1. Native Swift app, not a script

macOS permissions (microphone, accessibility) are granted per bundle identity. A
Python script run from Terminal stays tied to Terminal and the global hotkey
becomes fragile. A real bundle gets clean TCC and can start by itself.

### 2. `whisper.cpp`, not Apple Speech

Clearly better quality, genuinely multilingual, and the model depends neither on
the network nor on Apple enabling on-device for your locale. Cost: a 547 MB model.

It is built from the vendored repo with a portable cmake inside the project,
because the environment allows neither writing outside the workspace nor
installing Homebrew.

### 3. `fn` as the key

`fn` alone produces no characters, which makes it the ideal push-to-talk key. The
event tap intercepts it at HID level and **swallows** the `flagsChanged` events so
macOS does not open the emoji picker. Any other key while `fn` is held cancels the
recording, so `fn`+arrows and `fn`+F3 keep working.

### 4. Two-layer insertion

1. Unicode events (`CGEventKeyboardSetUnicodeString`) in 20 UTF-16-unit chunks,
   without touching the clipboard.
2. Accessibility verification: the caret position is compared before and after. If
   it did not move, it retries with clipboard + ⌘V and restores the clipboard
   0.6 s later.

If neither layer can be verified, the panel opens: the text is never lost.

> **Superseded in v0.3.5:** synthetic unicode typing only ever delivered its first
> chunk on macOS 26, so the order was inverted. A single atomic ⌘V is now the
> primary path; see `TextInserter`.

### 5. Non-activating panel

`NSPanel` with `.nonactivatingPanel` + `becomesKeyOnlyIfNeeded`. When it appears
because insertion failed, focus stays in the app you were typing into; if the panel
activated the app, the text would go to the panel and the destination would be lost.

## Data flow

```
CGEventTap (flagsChanged, fn)
  └─ onPress   → AudioRecorder.start()  → AVAudioEngine tap → [Float] in memory
  └─ onRelease → AudioRecorder.stop()   → 16-bit mono WAV in temp
                    └─ Transcriber: ffmpeg -ar 16000 -ac 1 → whisper-cli → .txt
                         └─ clean() drops [BLANK_AUDIO], [MUSIC], etc.
                              └─ TranscriptStore.add()
                                   └─ TextInserter.insert() → success? → done
                                                            → failure  → panel.show()
  └─ onCancel  → AudioRecorder.cancel()
```

## Errors and states

| Situation | Behaviour |
|---|---|
| No microphone permission | Alert with a button to Settings. |
| No Accessibility | Alert + retry every 2 s until granted. |
| Empty audio / < 0.3 s | Does nothing, back to idle. |
| Whisper understands nothing | Discards the result (never inserts junk). |
| ffmpeg/whisper fail | The panel opens with the message in red. |
| Insertion not verifiable | The panel opens with the text to copy. |
| Recording > 120 s | Stops by itself and transcribes. |

## Structure

```
WhisperFlow/
├── Sources/            # Swift files, one responsibility each
├── Resources/Info.plist
├── build.sh            # compile + package + sign
├── download-model.sh
├── models/             # gitignored, 547 MB
└── vendor-whisper/     # gitignored, whisper.cpp checkout
```

## Verification done

- `say` → ffmpeg → `whisper-cli`: exact transcription in English and Spanish.
- Measured latency: 1.83 s (2.3 s audio) and 1.93 s (9 s audio) with a fixed
  language; 3.34 s / 3.43 s with `auto`.
- The app launches, resolves paths and writes `config.json` correctly.
- Manual testing pending: real `fn` hotkey, TCC permissions, insertion into
  third-party apps (needs human interaction).

---

# Appendix: AI text cleanup (v0.2.0)

## Goal

Wispr Flow does not only transcribe: it runs the text through an LLM that removes
fillers, fixes punctuation and splits sentences. We wanted the same, locally.

## Finding: Apple Intelligence is not available

`FoundationModels.framework` exists on macOS 26, but asking
`SystemLanguageModel.default.availability` returns `appleIntelligenceNotEnabled`:
the on-device model is off and not enabled in the user's region. The code is in
place and is used only if it ever becomes available; it is not the main path.

## Decision: llama.cpp with a GGUF model

- Official prebuilt binary (`llama-b12589-bin-macos-arm64`), which **does ship
  Metal** — unlike whisper.cpp, which had to be built without a GPU on this machine
  because the shader compiler was missing.
- `Qwen2.5-3B-Instruct-Q4_K_M` (~1.8 GB): good Spanish, follows instructions and
  preserves numbers and technical vocabulary.
- It calls `llama-completion` (not `llama-cli`) with a hand-built ChatML template,
  so stdout is only the answer — no banner, no interactive loop.
- `PostProcessor.sanitize` rejects output that differs too much from the original
  (less than half or more than double the words), comes back empty, or carries a
  preamble like "Here is the cleaned text:". In that case the raw text wins.

## Why two engines

Loading 1.8 GB costs **~4.5 s** per dictation (measured: 4.6 s GPU, 6.1 s CPU,
with only 0.3 s difference between loading and generating). That is too much for
normal use, so:

- **Rules** (`RulesCleaner`): deterministic regex, <10 ms, no models. Drops
  `eh/um/mmm`, fixes spacing, capitalisation and the final period. No rewriting.
- **Local AI**: the real cleanup, opt-in, for long dictations.

Keeping a resident `llama-server` was ruled out: it would give ~1 s per dictation
but hold ~2.5 GB of RAM at rest — the exact opposite of the design.

## Verification

- `llama-completion` with a ChatML template: removed "pues"/"o sea", added
  punctuation and split sentences without altering the numbers (29.5 / 13.5 /
  18.5 / 40 / 60).
- `RulesCleaner`: "eh hola  eh  como estas ,  quiero..." → "Hola como estas,
  quiero...".
- The app launched after rebuilding with **permissions intact**, thanks to signing
  with the Apple Development certificate instead of ad-hoc.
