# Heed — End-to-End Architecture

> A visual walkthrough of how Heed records, transcribes, and turns meetings into actionable tasks.

---

## 1. The Two Assembly Lines

Heed has two distinct pipelines that run one after the other. The first is fully local. The second is opt-in and network-dependent.

```
┌─────────────────────────────────────────────────────────────────┐
│  PIPELINE 1 — Local Capture & Transcription                     │
│                                                                 │
│  Microphone ──┐                                                 │
│               ├──► PCM Files ──► Whisper (on-device) ──► JSON  │
│  System Audio─┘                                                 │
│                                                                 │
│  Nothing leaves the device in this stage.                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ user clicks AI action
┌─────────────────────────────────────────────────────────────────┐
│  PIPELINE 2 — AI Analysis & Prep (opt-in, network)              │
│                                                                 │
│  Transcript text ──► OpenAI ──► Tasks ──► Prep Chat / Brief     │
│                                                                 │
│  Raw audio never touches the network.                           │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. App Boot Path

```
heedApp.swift
    │
    ├── Creates: RecordingController
    │               TaskAnalysisController
    │               TaskPrepController
    │               APIKeySettingsViewModel
    │
    └── Opens: one NSWindow (hidden title bar)
                    │
                    └── ContentView.swift
                            │
                            ├── UI-test mode? ──YES──► inject fixture services
                            │                          (no real network calls)
                            │
                            └── WorkspaceShell.swift  ◄── main UI container
```

---

## 3. Recording State Machine

`RecordingController` is the control tower. Every recording action flows through these states:

```
                    ┌─────────────────────┐
                    │        idle         │
                    └──────────┬──────────┘
                               │ user presses Record
                               ▼
                    ┌─────────────────────┐
                    │ requestingPermissions│
                    └──────────┬──────────┘
                               │ mic + screen granted
                               ▼
                    ┌─────────────────────┐
                    │        ready        │  ◄── demo mode starts here
                    └──────────┬──────────┘
                               │ permissions confirmed
                               ▼
          ┌──── watchdog ────► recording ◄──── audio frames arriving
          │                    │
          │                    │ user presses Stop
          │                    ▼
          │           ┌────────────────┐
          │           │    stopping    │  (flush writers, close files)
          │           └───────┬────────┘
          │                   │
          │                   ▼
          │           ┌────────────────┐
          │           │   processing   │  (Whisper transcribes PCM → JSON)
          │           └───────┬────────┘
          │                   │ complete
          │                   ▼
          │           ┌────────────────┐
          └──fail────►│    error(msg)  │
                      └────────────────┘
```

> **Watchdog:** if no audio frames arrive within the startup window, the controller moves to `error` before wasting the session.

---

## 4. Audio Capture Detail

Two sources are captured in parallel. Each writes to its own raw PCM file.

```
┌──────────────────────────────────────────────────────────┐
│                   RecordingController                     │
│                                                          │
│  ┌─────────────────────┐   ┌────────────────────────┐   │
│  │   MicCaptureManager  │   │ SystemAudioCaptureManager│  │
│  │  (AVAudioEngine)     │   │  (ScreenCaptureKit)    │   │
│  └────────┬────────────┘   └────────────┬───────────┘   │
│           │ 16 kHz mono float            │ 16 kHz mono   │
│           ▼                              ▼               │
│  ┌──────────────────┐        ┌──────────────────┐        │
│  │  mic.pcm  (file) │        │ system.pcm (file)│        │
│  └──────────────────┘        └──────────────────┘        │
│                                                          │
│  AudioEnergyGate monitors both streams for speech-like   │
│  signal — if one stream dies, recording continues on     │
│  the other. If both die, the session is closed.          │
└──────────────────────────────────────────────────────────┘

  Session folder on disk:
  ~/Library/Application Support/Heed/Sessions/<uuid>/
      ├── session.json
      ├── mic.pcm
      └── system.pcm
```

---

## 5. Post-Stop Transcription Pipeline

After the user presses Stop, the recorded PCM files are transcribed locally using a bundled Whisper binary.

```
  mic.pcm ──────────────────────────────────────────────────┐
  system.pcm ───────────────────────────────────────────────┤
                                                            │
                    BatchSourceTranscriber                  │
                    ┌──────────────────────────────────┐   │
                    │  reads PCM → AudioChunker         │ ◄─┘
                    │  slices into fixed-size chunks    │
                    │  dispatches chunks to workers     │
                    └──────────────┬───────────────────┘
                                   │ one chunk at a time
                                   ▼
                    ┌──────────────────────────────────┐
                    │         WhisperWorker             │
                    │  wraps WhisperProcessClient       │
                    └──────────────┬───────────────────┘
                                   │ stdin/stdout pipe
                                   ▼
                    ┌──────────────────────────────────┐
                    │   WhisperChunkCLI (binary)        │
                    │   • loads ggml-base.en model      │
                    │   • runs whisper.cpp              │
                    │   • filters caption-like noise    │
                    │   • returns segments as JSON      │
                    └──────────────┬───────────────────┘
                                   │ JSON segments
                                   ▼
                    ┌──────────────────────────────────┐
                    │   TranscriptSession               │
                    │   micSegments  []                 │
                    │   systemSegments []               │
                    │   segments (computed merge) ──────┼──► export / UI
                    └──────────────────────────────────┘
```

> **Privacy note:** the Whisper model runs entirely on-device. Audio never leaves the machine during transcription.

---

## 6. UI Layer Map

```
WorkspaceShell.swift  (root container)
├── SessionSidebarView          — past session list (slide-in)
│
├── mainWorkspace  [switches based on taskPrepController.activeTaskID]
│   │
│   ├── IF no active task prep:
│   │   └── TranscriptCanvasView
│   │       ├── SourceTranscriptPanelsView   — MIC | SYSTEM columns
│   │       └── TaskAnalysisSectionView      — compiled tasks + "Show source"
│   │
│   └── IF task prep active:
│       └── TaskPrepWorkspaceView
│           ├── TaskPrepChatView             — left pane (streaming chat)
│           └── TaskPrepContextPanelView     — right pane (stable brief + spawn approval)
│
├── FloatingTransportView       — Record / Stop button
├── UtilityRailView             — status bar, copy text, sidebar toggle
└── APIKeySettingsView          — sheet (presented on demand)
```

---

## 7. Task Analysis Flow

```
User clicks "Compile tasks"
        │
        ▼
TaskAnalysisController
        │
        ├── checks: session non-empty? API key present?
        │
        └──► OpenAITaskCompilers
                │
                ├── formats transcript as numbered lines
                │
                └──► OpenAIResponsesClient  ──► OpenAI API
                            │                   (structured JSON schema)
                            │
                            ▼
                     [CompiledTask]
                     ┌────────────────────────┐
                     │ id, title, description │
                     │ sourceLineRefs []      │ ◄── "Show source" links back
                     └────────────────────────┘
                            │
                            ▼
                    TaskAnalysisSectionView
                    (inline cards in transcript)
```

---

## 8. Task Prep Workspace Flow

```
User clicks "Prepare context" on a task
        │
        ▼
TaskPrepController.start(task:in:)
        │
        ├── stores activeTask + activeSession
        │
        └──► TaskPrepConversationService.beginTurn(input:)
                │
                └──► OpenAIResponsesClient(model: "gpt-5.4")
                            │  streaming SSE
                            ▼
                    OpenAIResponsesStream
                    (event parser)
                            │
              ┌─────────────┼──────────────────────┐
              ▼             ▼                       ▼
        text delta   tool_call                 .completed
              │             │                       │
              ▼             ▼                       ▼
       chat bubble   ┌──────────────┐     pendingDraft ──► stableContextDraft
                     │ which tool?  │
                     └──────────────┘
                       │         │         │
                       ▼         ▼         ▼
            get_meeting_  update_context_  spawn_
            transcript    draft           agent
                │              │              │
                │              ▼              ▼
                │       pendingBrief     blocked until
                │       (right pane)    user clicks
                │                       "Approve spawn"
                ▼
        read current session
        transcript only
        (no cross-session access)
```

> **Draft promotion safety:** the controller writes `pendingContextDraft` during streaming and only promotes it to `stableContextDraft` on `.completed`. This prevents half-finished streamed output from appearing as final in the UI.

---

## 9. Storage Layout

```
~/Library/Application Support/Heed/
└── Sessions/
    └── <session-uuid>/
        ├── session.json        ← TranscriptSession (all metadata + segments)
        ├── mic.pcm             ← raw 16 kHz mono float32
        └── system.pcm          ← raw 16 kHz mono float32

  session.json shape:
  {
    "id": "...",
    "startDate": "...",
    "state": "completed" | "recording" | "recovered",
    "micSegments":    [{ "start", "end", "text", "source": "mic" }, ...],
    "systemSegments": [{ "start", "end", "text", "source": "system" }, ...]
  }

  Crash recovery: on next launch, SessionStore rewrites any session
  still marked "recording" → "recovered".
```

---

## 10. Secrets and API Key Path

```
User types OpenAI key
        │
        ▼
APIKeySettingsViewModel
        │
        └──► KeychainAPIKeyStore ──► macOS Keychain
                                         │
                                         ▼
                            retrieved per-request by:
                            • OpenAIResponsesClient (task compile)
                            • OpenAIResponsesClient (task prep)
```

No API key is ever written to disk in plaintext.

---

## 11. Trust Boundary Map

```
┌───────────────────────────────────────────────────────┐
│                  ON-DEVICE ONLY                       │
│                                                       │
│  Audio capture → PCM files → Whisper CLI → segments  │
│  Session JSON storage                                 │
│  Keychain (API key)                                   │
│                                                       │
└───────────────────────┬───────────────────────────────┘
                        │ explicit user action required
                        ▼
┌───────────────────────────────────────────────────────┐
│                NETWORK (OpenAI)                       │
│                                                       │
│  Transcript text (not audio) → task compile           │
│  Transcript text (not audio) → prep chat              │
│                                                       │
│  Raw audio: NEVER sent over the network               │
└───────────────────────────────────────────────────────┘
```

---

## 12. Test Coverage Map

```
RecordingControllerBatchModeTests   — post-stop batch transcription logic
BatchSourceTranscriberTests         — chunking + worker dispatch
SessionStoreMigrationTests          — legacy format migration + crash recovery
heedTests                           — audio chunking, storage, exports
OpenAITaskCompilersTests            — prompt format + JSON schema parsing
OpenAIResponsesStreamTests          — SSE event parsing
TaskPrepControllerTests             — prep state machine + spawn gate
heedUITests                         — full end-to-end UI flow in demo/fixture mode
```

---

## 13. Component Dependency Graph

```
         heedApp
            │
            ▼
       ContentView
       ┌────┼──────────────┐
       │    │              │
       ▼    ▼              ▼
  Recording Task         TaskPrep
  Controller Analysis    Controller
       │    Controller        │
       │         │            │
       │         ▼            ▼
       │   OpenAITask   TaskPrepConversation
       │   Compilers       Service
       │         │            │
       │         └─────┬──────┘
       │               ▼
       │      OpenAIResponsesClient
       │               │
       │               ▼
       │           OpenAI API
       │
       ├── PermissionsManager
       ├── MicCaptureManager
       ├── SystemAudioCaptureManager
       ├── SourceRecordingFileWriter  ──► mic.pcm / system.pcm
       ├── BatchSourceTranscriber
       │       └── WhisperWorker
       │               └── WhisperProcessClient ──► WhisperChunkCLI (binary)
       └── SessionStore  ──► session.json
```

---

## 14. Key Design Decisions at a Glance

| Decision | Why it matters |
|---|---|
| Local-first audio capture | Raw audio never leaves the device |
| Split MIC / SYSTEM streams | Preserves provenance; enables per-source fault tolerance |
| Whisper runs in a subprocess | Isolates model crash risk from the main app process |
| Draft → stable promotion | Prevents half-streamed AI output from showing as final |
| Prep data is RAM-only | Simplifies storage and reduces privacy surface |
| Spawn approval gate | Human stays in the loop before any agent handoff |
| Keychain for API key | No plaintext secrets on disk |
