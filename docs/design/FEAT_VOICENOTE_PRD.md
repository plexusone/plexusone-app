# Feature: Voice Note Input

## Overview

**Feature Name:** Voice Note Input
**Status:** Draft
**Last Updated:** 2026-03-20
**Related Projects:**
- [PlexusOne Nexus](https://github.com/plexusone/nexus) - macOS terminal multiplexer for AI agents
- [OmniVoice](https://github.com/plexusone/omnivoice) - Go voice pipeline framework (reference)

## Problem Statement

When working with multiple AI CLI agents, typing complex prompts can be slow and disruptive. Users want to:

1. Quickly dictate prompts using voice instead of typing
2. Send voice notes to agents like they do in WhatsApp/ChatGPT
3. Keep hands free while thinking through problems

## Goals

1. **Quick voice input**: Click mic, speak, release, text appears
2. **Seamless integration**: Voice note sends text directly to active pane
3. **Low friction**: No complex setup or API keys required (for MVP)
4. **Accuracy option**: Support for cloud STT (Whisper) for better accuracy

## User Experience

### Flow 1: Push-to-Talk (Primary)

```
1. User clicks and holds mic button (or presses hotkey)
2. Recording indicator appears (pulsing red dot)
3. User speaks their prompt
4. User releases button
5. Audio is transcribed
6. Text appears in terminal input (or sent directly)
```

### Flow 2: Toggle Recording

```
1. User clicks mic button once
2. Recording starts (visual indicator)
3. User speaks
4. User clicks mic button again (or presses Enter)
5. Recording stops, transcription happens
6. Text is sent to active pane
```

### Visual Design

**Mic Button in Pane Header:**
```
┌──────────────────────────────────────────────────────────────┐
│ [▼ coder-1 🟢]                              [🎤]  #1   [×]  │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  Terminal content...                                         │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**During Recording:**
```
┌──────────────────────────────────────────────────────────────┐
│ [▼ coder-1 🟢]                        [🔴 Recording...]  #1  │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  🎤 Recording... (3.2s)  [Cancel]                      │ │
│  │  ████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  (waveform) │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**During Transcription:**
```
┌──────────────────────────────────────────────────────────────┐
│ [▼ coder-1 🟢]                        [⏳ Transcribing...]   │
├──────────────────────────────────────────────────────────────┤
```

## Architecture

### Option A: Apple Speech Framework (MVP)

Uses macOS built-in speech recognition. No API keys required.

```
┌─────────────────────────────────────────────────────────────────┐
│                         Nexus App                               │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ VoiceNoteManager                                         │   │
│  │ - AVAudioEngine (recording)                              │   │
│  │ - SFSpeechRecognizer (transcription)                     │   │
│  │ - Handles permissions                                     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│                    Transcribed Text                             │
│                              │                                  │
│                              ▼                                  │
│                    Send to Terminal Pane                        │
└─────────────────────────────────────────────────────────────────┘
```

**Pros:**
- No API keys needed
- Works offline
- Low latency (real-time transcription)
- Built into macOS

**Cons:**
- Less accurate than Whisper
- Limited language support
- Requires user permission

### Option B: OpenAI Whisper API

Records audio, sends to Whisper API for transcription.

```
┌─────────────────────────────────────────────────────────────────┐
│                         Nexus App                               │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ VoiceNoteManager                                         │   │
│  │ - AVAudioEngine (recording)                              │   │
│  │ - Save to temp .wav file                                 │   │
│  │ - Upload to OpenAI Whisper API                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼ HTTPS                            │
│                    api.openai.com/v1/audio/transcriptions       │
│                              │                                  │
│                              ▼                                  │
│                    Transcribed Text                             │
└─────────────────────────────────────────────────────────────────┘
```

**Pros:**
- Best-in-class accuracy
- Supports many languages
- Handles accents well

**Cons:**
- Requires API key
- Requires network
- Has latency (upload + process)
- Costs money

### Option C: Embed OmniVoice Binary

Bundle the omnivoice Go binary inside the Nexus app bundle and call it as a subprocess.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Nexus.app Bundle                             │
│  Contents/                                                      │
│  ├── MacOS/                                                     │
│  │   ├── Nexus                    (main app)                   │
│  │   └── omnivoice                (embedded binary)            │
│  └── Resources/                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         Nexus App                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ VoiceNoteManager (Swift)                                 │   │
│  │ - Records audio to temp .wav file                        │   │
│  │ - Calls: omnivoice transcribe --provider deepgram        │   │
│  │ - Parses JSON output                                     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼ subprocess                       │
│                    omnivoice (Go binary)                        │
│                              │                                  │
│                              ▼ API call                         │
│            Deepgram / OpenAI Whisper / ElevenLabs              │
└─────────────────────────────────────────────────────────────────┘
```

**Pros:**
- Reuses existing omnivoice code
- Access to all omnivoice providers (Deepgram, Whisper, ElevenLabs)
- Single codebase for voice functionality
- Can update providers without changing Swift code

**Cons:**
- Larger app bundle (~10-15MB for Go binary)
- Subprocess overhead
- Cross-compile needed (arm64 + x86_64)

**Build Integration:**
```bash
# Build omnivoice for macOS (universal binary)
cd ~/go/src/github.com/plexusone/omnivoice
GOOS=darwin GOARCH=arm64 go build -o omnivoice-arm64 ./cmd/omnivoice
GOOS=darwin GOARCH=amd64 go build -o omnivoice-amd64 ./cmd/omnivoice
lipo -create -output omnivoice omnivoice-arm64 omnivoice-amd64

# Copy to Nexus bundle
cp omnivoice Nexus.app/Contents/MacOS/
```

**Swift Integration:**
```swift
class OmniVoiceTranscriber {
    func transcribe(audioFile: URL, provider: String = "deepgram") async throws -> String {
        let binaryPath = Bundle.main.path(forResource: "omnivoice", ofType: nil, inDirectory: "MacOS")!

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["transcribe", "--provider", provider, "--format", "json", audioFile.path]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let result = try JSONDecoder().decode(TranscriptionResult.self, from: data)
        return result.text
    }
}
```

### Option D: Add Apple Speech to OmniVoice

Extend omnivoice with an Apple Speech provider, then embed the binary.

**New Provider in OmniVoice (Go + cgo):**
```go
// providers/apple/stt.go
// Uses cgo to call Apple Speech Framework

/*
#cgo CFLAGS: -x objective-c
#cgo LDFLAGS: -framework Speech -framework Foundation
#import <Speech/Speech.h>
*/
import "C"

type AppleSTTProvider struct{}

func (p *AppleSTTProvider) TranscribeFile(ctx context.Context, path string, config stt.TranscriptionConfig) (*stt.TranscriptionResult, error) {
    // Call SFSpeechRecognizer via cgo
}
```

**Pros:**
- Unified provider interface in omnivoice
- Apple Speech works offline
- Can fallback: Apple → Whisper → Deepgram
- Single transcription API for all platforms

**Cons:**
- Requires cgo (complicates cross-compilation)
- macOS-only provider
- More complex build process

### Recommended: Hybrid Approach

**Phase 1 (MVP):** Native Swift with Apple Speech Framework
- Fastest to implement
- No external dependencies
- Works offline

**Phase 2:** Embed OmniVoice binary
- Add as optional "enhanced" transcription
- Use for Whisper/Deepgram when user configures API keys
- Fallback to Apple Speech if binary fails

**Phase 3:** Add Apple Speech to OmniVoice
- Unify the codebase
- Single provider registry for all STT options

```swift
enum TranscriptionProvider {
    case apple      // Default, no setup, native Swift
    case omnivoice(provider: String)  // Embedded binary with provider selection
}
```

## Implementation

### VoiceNoteManager (Swift)

```swift
import AVFoundation
import Speech

@Observable
class VoiceNoteManager: NSObject {
    enum State {
        case idle
        case recording(duration: TimeInterval)
        case transcribing
        case error(String)
    }

    private(set) var state: State = .idle
    private(set) var transcribedText: String = ""

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    var onTranscriptionComplete: ((String) -> Void)?

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        let micStatus = await AVAudioApplication.requestRecordPermission()

        return speechStatus && micStatus
    }

    // MARK: - Recording

    func startRecording() throws {
        guard state == .idle else { return }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        audioEngine = AVAudioEngine()
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let audioEngine = audioEngine,
              let recognitionRequest = recognitionRequest,
              let speechRecognizer = speechRecognizer else {
            throw VoiceNoteError.setupFailed
        }

        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            if let result = result {
                self?.transcribedText = result.bestTranscription.formattedString
            }

            if error != nil || result?.isFinal == true {
                self?.finishRecording()
            }
        }

        state = .recording(duration: 0)
        startDurationTimer()
    }

    func stopRecording() {
        guard case .recording = state else { return }

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        state = .transcribing

        // Wait for final result, then call completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            self.state = .idle
            self.onTranscriptionComplete?(self.transcribedText)
            self.transcribedText = ""
        }
    }

    func cancelRecording() {
        recognitionTask?.cancel()
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        state = .idle
        transcribedText = ""
    }

    private func finishRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest = nil
        recognitionTask = nil
    }

    private func startDurationTimer() {
        // Update duration every 0.1s while recording
    }
}

enum VoiceNoteError: Error {
    case permissionDenied
    case setupFailed
    case recordingFailed
    case transcriptionFailed
}
```

### VoiceNoteButton (SwiftUI)

```swift
struct VoiceNoteButton: View {
    @State private var voiceManager = VoiceNoteManager()
    @State private var isPressed = false
    let onTranscription: (String) -> Void

    var body: some View {
        Button(action: {}) {
            ZStack {
                Circle()
                    .fill(fillColor)
                    .frame(width: 28, height: 28)

                Image(systemName: iconName)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        startRecording()
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    stopRecording()
                }
        )
        .help("Hold to record voice note")
        .onAppear {
            voiceManager.onTranscriptionComplete = onTranscription
        }
    }

    private var fillColor: Color {
        switch voiceManager.state {
        case .idle: return .secondary
        case .recording: return .red
        case .transcribing: return .orange
        case .error: return .red
        }
    }

    private var iconName: String {
        switch voiceManager.state {
        case .idle: return "mic"
        case .recording: return "mic.fill"
        case .transcribing: return "ellipsis"
        case .error: return "exclamationmark.triangle"
        }
    }

    private func startRecording() {
        Task {
            let hasPermission = await voiceManager.requestPermissions()
            if hasPermission {
                try? voiceManager.startRecording()
            }
        }
    }

    private func stopRecording() {
        voiceManager.stopRecording()
    }
}
```

### Integration with PaneHeaderView

```swift
struct PaneHeaderView: View {
    // ... existing properties ...

    var body: some View {
        HStack(spacing: 4) {
            // Session dropdown
            // ...

            Spacer()

            // Voice note button
            VoiceNoteButton { transcribedText in
                sendToTerminal(transcribedText)
            }

            // Pane number
            // ...
        }
    }

    private func sendToTerminal(_ text: String) {
        // Send transcribed text to the terminal pane
        // Either paste into input or send directly via tmux send-keys
    }
}
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘⇧V | Toggle voice recording for active pane |
| Esc | Cancel current recording |

## Settings

```swift
struct VoiceSettings: Codable {
    var provider: TranscriptionProvider = .apple
    var language: String = "en-US"
    var autoSend: Bool = true  // Send immediately after transcription
    var showPreview: Bool = false  // Show text before sending

    // Whisper-specific
    var whisperAPIKey: String?
    var whisperModel: String = "whisper-1"
}
```

**Settings UI:**

```
┌─────────────────────────────────────────────────────────┐
│ Voice Input                                             │
├─────────────────────────────────────────────────────────┤
│ Provider:     [Apple Speech ▼]                          │
│               ○ Apple Speech (built-in, offline)        │
│               ○ OpenAI Whisper (more accurate)          │
│                                                         │
│ Language:     [English (US) ▼]                          │
│                                                         │
│ □ Auto-send after transcription                         │
│ □ Show preview before sending                           │
│                                                         │
│ ─── Whisper Settings ───                                │
│ API Key:      [••••••••••••••••]  [Test]               │
│ Model:        [whisper-1 ▼]                             │
└─────────────────────────────────────────────────────────┘
```

## Privacy & Permissions

### Required Permissions

1. **Microphone Access** - For recording audio
2. **Speech Recognition** - For Apple Speech Framework

### Permission Request Flow

```
First voice note attempt:
1. Check permissions
2. If not granted, show explanation dialog
3. Request permission via system dialog
4. If denied, show settings link
```

### Privacy Considerations

- **Apple Speech**: Audio processed on-device or Apple servers (based on settings)
- **Whisper**: Audio sent to OpenAI servers
- **No storage**: Audio deleted after transcription (unless user enables saving)

## Implementation Phases

### Phase 1: Apple Speech MVP

- [ ] VoiceNoteManager with AVAudioEngine + SFSpeechRecognizer
- [ ] VoiceNoteButton (push-to-talk)
- [ ] Integration in PaneHeaderView
- [ ] Basic error handling
- [ ] Permission request flow

### Phase 2: Polish

- [ ] Recording duration indicator
- [ ] Audio waveform visualization
- [ ] Keyboard shortcut (⌘⇧V)
- [ ] Settings UI for language selection
- [ ] Cancel gesture (drag away)

### Phase 3: Whisper Integration

- [ ] WhisperTranscriber service
- [ ] Audio file encoding (WAV/MP3)
- [ ] API key management in Settings
- [ ] Provider selection in Settings
- [ ] Fallback from Whisper to Apple if offline

### Phase 4: Advanced

- [ ] Streaming transcription preview
- [ ] Custom vocabulary/keywords
- [ ] Multi-language auto-detect
- [ ] Voice commands ("send", "cancel", "clear")

## Testing

### Manual Testing

1. Grant microphone and speech permissions
2. Click and hold mic button
3. Speak a test phrase
4. Release button
5. Verify text appears in terminal

### Edge Cases

- No microphone available
- Permission denied
- Network error (Whisper)
- Very long recording (>60s)
- Background noise
- Multiple languages in one recording

## Open Questions

1. **Auto-send vs preview**: Should transcribed text be sent immediately or shown for editing first?
2. **Recording limit**: Should there be a maximum recording duration?
3. **Audio storage**: Should users be able to save/replay recordings?
4. **Whisper streaming**: Use Whisper streaming API for real-time preview?

## Appendix: Adding Apple Speech Provider to OmniVoice

If we decide to add Apple Speech Framework as a provider in omnivoice, here's the design:

### Provider Registration

```go
// providers/apple/register.go
package apple

import (
    "github.com/plexusone/omnivoice"
)

func init() {
    omnivoice.RegisterSTTProvider("apple", NewAppleSTTProvider)
}
```

### Implementation Options

**Option 1: cgo (Objective-C bridge)**

```go
// providers/apple/stt_darwin.go
// +build darwin

/*
#cgo CFLAGS: -x objective-c
#cgo LDFLAGS: -framework Speech -framework Foundation -framework AVFoundation

#import <Foundation/Foundation.h>
#import <Speech/Speech.h>
#import <AVFoundation/AVFoundation.h>

const char* transcribeFile(const char* path, const char* locale) {
    @autoreleasepool {
        NSString *filePath = [NSString stringWithUTF8String:path];
        NSString *localeId = [NSString stringWithUTF8String:locale];

        NSURL *url = [NSURL fileURLWithPath:filePath];
        NSLocale *loc = [NSLocale localeWithLocaleIdentifier:localeId];
        SFSpeechRecognizer *recognizer = [[SFSpeechRecognizer alloc] initWithLocale:loc];

        SFSpeechURLRecognitionRequest *request = [[SFSpeechURLRecognitionRequest alloc] initWithURL:url];

        __block NSString *result = nil;
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);

        [recognizer recognitionTaskWithRequest:request resultHandler:^(SFSpeechRecognitionResult *res, NSError *error) {
            if (res.isFinal) {
                result = res.bestTranscription.formattedString;
                dispatch_semaphore_signal(sem);
            }
        }];

        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        return result ? [result UTF8String] : "";
    }
}
*/
import "C"

import (
    "context"
    "unsafe"

    "github.com/plexusone/omnivoice-core/stt"
)

type AppleSTTProvider struct {
    locale string
}

func NewAppleSTTProvider(opts ...omnivoice.ProviderOption) (stt.Provider, error) {
    cfg := &providerConfig{locale: "en-US"}
    for _, opt := range opts {
        opt(cfg)
    }
    return &AppleSTTProvider{locale: cfg.locale}, nil
}

func (p *AppleSTTProvider) TranscribeFile(ctx context.Context, path string, config stt.TranscriptionConfig) (*stt.TranscriptionResult, error) {
    cPath := C.CString(path)
    defer C.free(unsafe.Pointer(cPath))

    locale := config.Language
    if locale == "" {
        locale = p.locale
    }
    cLocale := C.CString(locale)
    defer C.free(unsafe.Pointer(cLocale))

    cResult := C.transcribeFile(cPath, cLocale)
    text := C.GoString(cResult)

    return &stt.TranscriptionResult{
        Text:     text,
        Language: locale,
    }, nil
}

func (p *AppleSTTProvider) Name() string { return "apple" }
func (p *AppleSTTProvider) Close() error { return nil }
```

**Option 2: Separate Swift helper binary**

Instead of cgo, build a small Swift CLI that omnivoice calls:

```swift
// apple-stt/main.swift
import Foundation
import Speech

@main
struct AppleSTT {
    static func main() async {
        let path = CommandLine.arguments[1]
        let locale = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "en-US"

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale))!
        let request = SFSpeechURLRecognitionRequest(url: URL(fileURLWithPath: path))

        do {
            let result = try await recognizer.recognitionTask(with: request)
            print(result.bestTranscription.formattedString)
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }
    }
}
```

```go
// providers/apple/stt_darwin.go
func (p *AppleSTTProvider) TranscribeFile(ctx context.Context, path string, config stt.TranscriptionConfig) (*stt.TranscriptionResult, error) {
    // Find apple-stt binary in same directory
    cmd := exec.Command("apple-stt", path, config.Language)
    output, err := cmd.Output()
    if err != nil {
        return nil, err
    }
    return &stt.TranscriptionResult{
        Text: strings.TrimSpace(string(output)),
    }, nil
}
```

### Build Configuration

```makefile
# Makefile for omnivoice with Apple provider

# Build Apple STT helper (Swift)
apple-stt:
	swiftc -O -o apple-stt Sources/apple-stt/main.swift

# Build omnivoice with cgo (macOS only)
build-darwin:
	CGO_ENABLED=1 GOOS=darwin go build -o omnivoice-darwin ./cmd/omnivoice

# Build universal binary
build-universal: apple-stt
	CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 go build -o omnivoice-arm64 ./cmd/omnivoice
	CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 go build -o omnivoice-amd64 ./cmd/omnivoice
	lipo -create -output omnivoice omnivoice-arm64 omnivoice-amd64
```

### Usage

```go
// With Apple provider
stt, _ := omnivoice.GetSTTProvider("apple")
result, _ := stt.TranscribeFile(ctx, "audio.wav", omnivoice.TranscriptionConfig{
    Language: "en-US",
})

// Fallback chain
providers := []string{"apple", "deepgram", "whisper"}
for _, name := range providers {
    stt, err := omnivoice.GetSTTProvider(name, omnivoice.WithAPIKey(keys[name]))
    if err == nil {
        result, err := stt.TranscribeFile(ctx, path, config)
        if err == nil {
            return result, nil
        }
    }
}
```

## References

- [Apple Speech Framework](https://developer.apple.com/documentation/speech)
- [AVAudioEngine](https://developer.apple.com/documentation/avfaudio/avaudioengine)
- [OpenAI Whisper API](https://platform.openai.com/docs/guides/speech-to-text)
- [OmniVoice](https://github.com/plexusone/omnivoice) - Go reference implementation
- [cgo Documentation](https://pkg.go.dev/cmd/cgo) - Go C interoperability
