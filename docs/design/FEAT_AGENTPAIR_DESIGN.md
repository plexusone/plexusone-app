# AgentPair Integration Design

## Overview

This document analyzes integration options for [AgentPair](https://github.com/plexusone/agentpair) with PlexusOne Desktop and Mobile. AgentPair is a Go-based orchestration tool for agent-to-agent pair programming between Claude and Codex CLI tools.

**Goal:** Enable PlexusOne Desktop users to launch, monitor, and control AgentPair sessions across multiple tmux panes with real-time status visibility in both desktop and mobile apps.

## Background

### What is AgentPair?

AgentPair orchestrates pair programming sessions between AI agents:

- One agent (Claude or Codex) works on a task
- The other agent reviews the work
- They iterate until completion or max iterations reached
- Communication happens via a JSONL-based bridge with SHA256 deduplication
- Supports single-agent mode (`--claude-only`, `--codex-only`) and paired mode

### Current AgentPair Architecture

```
agentpair CLI (Go)
├── internal/loop      # Orchestration state machine
├── internal/bridge    # Agent-to-agent messaging (JSONL + MCP server)
├── internal/agent     # Claude/Codex process wrappers
├── internal/run       # Run persistence (~/.agentpair/runs/)
├── internal/tmux      # tmux session management
└── internal/config    # YAML/JSON configuration
```

### Current PlexusOne Desktop Architecture

```
PlexusOne Desktop (Swift/SwiftUI)
├── SessionManager     # tmux session lifecycle
├── TerminalView       # SwiftTerm-based terminal emulation
└── GridLayoutView     # Multi-pane management

TUI Parser (Go)
├── WebSocket server   # Streams tmux output to mobile
└── PTY attachment     # Reads from tmux sessions

PlexusOne Mobile (Flutter)
├── WebSocket client   # Receives terminal output
└── Terminal view      # Displays streamed content
```

## Integration Options

### Option 1: No Integration (Composition)

Run AgentPair as a regular command in PlexusOne Desktop-managed tmux sessions.

```
PlexusOne Desktop
    └── manages tmux sessions
            └── pane 1: $ agentpair --prompt "implement feature X"
            │               ├── spawns claude CLI
            │               └── spawns codex CLI
            └── pane 2: $ agentpair --prompt "fix bug Y"
    └── TUI Parser streams output → Mobile
```

**Pros:**
- Zero code changes required
- Works today
- Clean separation of concerns

**Cons:**
- No structured status (just terminal output)
- Can't pause/resume from PlexusOne Desktop UI
- Mobile only sees raw text, not semantic state

**Verdict:** Good starting point, but limited visibility.

---

### Option 2: Swift Port with Direct Integration

Rewrite AgentPair in Swift and embed it directly into PlexusOne Desktop.

```
PlexusOne Desktop (Swift)
    └── AgentOrchestrator (in-process)
            ├── spawns claude CLI (Process)
            └── spawns codex CLI (Process)
    └── SwiftUI views observe orchestrator state directly
```

**Implementation sketch:**

```swift
@Observable
class AgentOrchestrator {
    var runs: [AgentRun] = []
    var activeRun: AgentRun?

    func startPairedRun(prompt: String, config: RunConfig) async throws -> AgentRun {
        let run = AgentRun(id: UUID(), prompt: prompt, config: config)
        runs.append(run)

        // Start agents as subprocesses
        let claudeProcess = Process()
        claudeProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/claude")
        claudeProcess.arguments = ["--json", "--prompt", prompt]

        let codexProcess = Process()
        codexProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/codex")
        // ...

        // Orchestration loop
        Task {
            while !run.isComplete && run.iteration < config.maxIterations {
                run.iteration += 1
                // Execute primary agent
                // Drain bridge messages
                // Execute secondary agent
                // Check for DONE/PASS/FAIL signals
            }
        }

        return run
    }

    func pauseRun(_ run: AgentRun) { /* ... */ }
    func resumeRun(_ run: AgentRun) { /* ... */ }
}

// Direct SwiftUI binding
struct AgentRunsView: View {
    @Environment(AgentOrchestrator.self) var orchestrator

    var body: some View {
        List(orchestrator.runs) { run in
            HStack {
                VStack(alignment: .leading) {
                    Text(run.prompt).lineLimit(1)
                    Text("Iteration \(run.iteration)/\(run.config.maxIterations)")
                        .font(.caption)
                }
                Spacer()
                StatusBadge(run.state)
            }
        }
    }
}
```

**Pros:**
- Native SwiftUI `@Observable` binding
- In-memory state sharing (no IPC)
- Single .app distribution
- Deep UI integration (progress bars, notifications, menu bar)

**Cons:**
- **Major rewrite:** ~2000+ lines of Go → Swift
- **Lost CLI usage:** Can't run headless or from terminal
- **macOS only:** No Linux, no CI/CD pipelines
- **Crash coupling:** Orchestrator crash takes down UI
- **Testing complexity:** Can't test orchestration independently
- **Subprocess management:** Swift's `Process` API is more verbose than Go's `os/exec`
- **Concurrency model:** Would need to adapt Go's goroutine patterns to Swift async/await

**Verdict:** High effort, significant trade-offs. Only justified if committed to macOS-exclusive product.

---

### Option 3: Go Service with API (Recommended)

Keep AgentPair as Go, add a lightweight HTTP/WebSocket API for PlexusOne Desktop integration.

```
┌─────────────────────────────────────────────────────────────┐
│                      PlexusOne Desktop (Swift)                   │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │ Terminal Panes  │  │ AgentPairClient │  │ Status View │ │
│  │ (tmux attach)   │  │ (WebSocket)     │  │ (SwiftUI)   │ │
│  └────────┬────────┘  └────────┬────────┘  └──────▲──────┘ │
└───────────┼─────────────────────┼─────────────────┼─────────┘
            │                     │                 │
            │ PTY                 │ WebSocket       │ @Published
            │                     │                 │
┌───────────▼─────────────────────▼─────────────────┴─────────┐
│                        tmux sessions                         │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ agentpair --prompt "task" --api-port 9100               ││
│  │     ├── claude CLI                                      ││
│  │     ├── codex CLI                                       ││
│  │     └── HTTP/WS API server (:9100)                      ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
            │
            │ WebSocket (via TUI Parser)
            ▼
┌─────────────────────────────────────────────────────────────┐
│                     PlexusOne Mobile (Flutter)                   │
│  ┌─────────────────┐  ┌─────────────────┐                   │
│  │ Terminal View   │  │ Status Widget   │                   │
│  └─────────────────┘  └─────────────────┘                   │
└─────────────────────────────────────────────────────────────┘
```

**AgentPair API additions (~300 lines of Go):**

```go
// internal/api/server.go
package api

type Server struct {
    manager *run.Manager
    mux     *http.ServeMux
}

func NewServer(manager *run.Manager) *Server {
    s := &Server{manager: manager}
    s.mux = http.NewServeMux()
    s.mux.HandleFunc("GET /api/runs", s.listRuns)
    s.mux.HandleFunc("GET /api/runs/{id}", s.getRun)
    s.mux.HandleFunc("GET /api/runs/{id}/bridge", s.getBridgeMessages)
    s.mux.HandleFunc("POST /api/runs/{id}/pause", s.pauseRun)
    s.mux.HandleFunc("POST /api/runs/{id}/resume", s.resumeRun)
    s.mux.HandleFunc("GET /api/events", s.streamEvents) // WebSocket
    return s
}

// GET /api/runs
func (s *Server) listRuns(w http.ResponseWriter, r *http.Request) {
    runs, _ := s.manager.ListActive()
    json.NewEncoder(w).Encode(runs)
}

// GET /api/runs/{id}
func (s *Server) getRun(w http.ResponseWriter, r *http.Request) {
    id, _ := strconv.Atoi(r.PathValue("id"))
    run, err := s.manager.Load(id)
    if err != nil {
        http.Error(w, "not found", 404)
        return
    }
    json.NewEncoder(w).Encode(RunStatus{
        ID:           run.Manifest.ID,
        Prompt:       run.Manifest.Prompt,
        State:        run.Manifest.State,
        Iteration:    run.Manifest.CurrentIteration,
        MaxIter:      run.Manifest.MaxIterations,
        PrimaryAgent: run.Manifest.PrimaryAgent,
        ReviewMode:   run.Manifest.ReviewMode,
        Bridge:       run.Bridge.Status(),
    })
}

// WebSocket for real-time events
func (s *Server) streamEvents(w http.ResponseWriter, r *http.Request) {
    conn, _ := websocket.Accept(w, r, nil)
    defer conn.Close(websocket.StatusNormalClosure, "")

    // Stream state changes
    ticker := time.NewTicker(500 * time.Millisecond)
    for range ticker.C {
        runs, _ := s.manager.ListActive()
        conn.Write(r.Context(), websocket.MessageText, toJSON(runs))
    }
}
```

**PlexusOne Desktop Swift client (~150 lines):**

```swift
@Observable
class AgentPairClient {
    var runs: [AgentRun] = []
    var isConnected = false

    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession.shared

    func connect(port: Int) {
        let url = URL(string: "ws://localhost:\(port)/api/events")!
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        isConnected = true
        receiveMessages()
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(.string(let text)):
                if let data = text.data(using: .utf8),
                   let runs = try? JSONDecoder().decode([AgentRun].self, from: data) {
                    Task { @MainActor in
                        self?.runs = runs
                    }
                }
            default:
                break
            }
            self?.receiveMessages() // Continue receiving
        }
    }

    func pauseRun(_ runID: Int) async throws {
        var request = URLRequest(url: URL(string: "http://localhost:9100/api/runs/\(runID)/pause")!)
        request.httpMethod = "POST"
        _ = try await session.data(for: request)
    }
}

// SwiftUI integration
struct AgentPairStatusView: View {
    @Environment(AgentPairClient.self) var client

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(client.isConnected ? .green : .red)
                    .frame(width: 8, height: 8)
                Text("AgentPair")
                    .font(.headline)
            }

            ForEach(client.runs) { run in
                AgentRunRow(run: run)
            }
        }
        .padding()
    }
}

struct AgentRunRow: View {
    let run: AgentRun
    @Environment(AgentPairClient.self) var client

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(run.prompt)
                    .lineLimit(1)
                Text("\(run.primaryAgent) • \(run.state)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ProgressView(value: Double(run.iteration), total: Double(run.maxIterations))
                .frame(width: 60)

            Button(run.state == "working" ? "Pause" : "Resume") {
                Task {
                    if run.state == "working" {
                        try? await client.pauseRun(run.id)
                    }
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}
```

**Pros:**
- **Minimal changes:** ~300 lines Go + ~150 lines Swift
- **Keeps CLI:** `agentpair` still works standalone
- **Cross-platform:** Linux, CI/CD, headless servers all work
- **Crash isolation:** AgentPair crash doesn't affect PlexusOne Desktop UI
- **Independent testing:** Each component testable separately
- **Mobile support:** TUI Parser can proxy API to mobile

**Cons:**
- Two processes to coordinate
- WebSocket latency (~ms, negligible)
- Need to handle disconnection/reconnection

**Verdict:** Best balance of integration depth vs. implementation effort.

---

### Option 4: Swift CLI (Not Recommended)

Port AgentPair to Swift but keep it as a separate CLI binary.

**Verdict:** Worst of both worlds. Full rewrite effort with no integration benefits. Go is better suited for CLI tools and subprocess management.

---

## Recommendation

**Implement Option 3: Go Service with API**

### Phase 1: Basic Integration (MVP)

1. Add `--api-port` flag to agentpair
2. Implement `/api/runs` and `/api/runs/{id}` endpoints
3. Add `AgentPairClient` to PlexusOne Desktop
4. Display run status in sidebar

**Effort:** ~2-3 days

### Phase 2: Real-time Updates

1. Add WebSocket `/api/events` endpoint
2. Stream state changes to PlexusOne Desktop
3. Add progress indicators and notifications

**Effort:** ~1-2 days

### Phase 3: Control Integration

1. Add pause/resume API endpoints
2. Add control buttons to PlexusOne Desktop UI
3. Add bridge message viewer

**Effort:** ~2-3 days

### Phase 4: Mobile Integration

1. Extend TUI Parser to proxy AgentPair API
2. Add status widget to PlexusOne Mobile
3. Add basic controls (pause/resume)

**Effort:** ~2-3 days

---

## Trade-off Summary

| Factor | Option 1 (Compose) | Option 2 (Swift Port) | Option 3 (Go API) |
|--------|-------------------|----------------------|-------------------|
| Implementation effort | None | High (~weeks) | Low (~days) |
| UI integration depth | None | Deep | Good |
| CLI preservation | Yes | No | Yes |
| Cross-platform | Yes | No | Yes |
| Crash isolation | Yes | No | Yes |
| Real-time status | No | Yes | Yes |
| Mobile support | Terminal only | N/A | Full |
| Maintenance burden | None | High (two langs) | Low |

---

## API Specification

### REST Endpoints

```
GET  /api/runs
     Response: [{ id, prompt, state, iteration, maxIterations, primaryAgent }]

GET  /api/runs/{id}
     Response: { id, prompt, state, iteration, maxIterations, primaryAgent,
                 reviewMode, bridgeStatus: { totalMessages, passCount, failCount } }

GET  /api/runs/{id}/bridge?limit=50
     Response: [{ id, type, from, to, content, timestamp }]

POST /api/runs/{id}/pause
     Response: { success: true }

POST /api/runs/{id}/resume
     Response: { success: true }
```

### WebSocket Events

```
WS /api/events

Server → Client:
{
  "type": "state_change",
  "runId": 1,
  "state": "reviewing",
  "iteration": 5,
  "timestamp": "2024-03-27T10:00:00Z"
}

{
  "type": "bridge_message",
  "runId": 1,
  "message": { "type": "signal", "from": "claude", "signal": "PASS" }
}

{
  "type": "run_complete",
  "runId": 1,
  "finalState": "completed",
  "totalIterations": 7
}
```

---

## Open Questions

1. **Port discovery:** How does PlexusOne Desktop know which port agentpair is using?
   - Option A: Fixed port (9100)
   - Option B: Write to `~/.agentpair/runs/{id}/api.port`
   - Option C: PlexusOne Desktop passes `--api-port` when launching

2. **Multi-run coordination:** Should there be one API server per run, or a central daemon?
   - Recommendation: One per run (simpler, isolated)

3. **Authentication:** Should the API require auth for non-localhost?
   - Recommendation: Localhost-only for v1, add token auth later

---

## References

- [AgentPair Repository](https://github.com/plexusone/agentpair)
- [PlexusOne Desktop TRD](./trd.md)
- [PlexusOne Desktop PRD](./prd.md)
