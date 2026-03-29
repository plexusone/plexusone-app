# Feature: AgentSentinel Integration

## Overview

**Feature Name:** AgentSentinel Integration
**Status:** Draft
**Last Updated:** 2026-03-20
**Related Projects:**
- [PlexusOne Desktop](https://github.com/plexusone/plexusone-apps) - macOS terminal multiplexer for AI agents
- [AgentSentinel](https://github.com/plexusone/agentsentinel) - Auto-approval system for AI CLI tools

## Problem Statement

When running multiple AI CLI agents (Claude Code, Codex, Kiro, Gemini CLI), users face two challenges:

1. **Manual approval fatigue**: AI tools frequently ask for permission to run commands, requiring constant "y" responses
2. **Lack of visibility**: When AgentSentinel runs in the background, users don't know:
   - How many AgentSentinel processes are running
   - Which panes/sessions are being monitored
   - How many approvals have occurred
   - Whether dangerous commands were blocked

## Goals

1. **Visibility**: Show AgentSentinel status within PlexusOne Desktop UI
2. **Control**: Enable/disable auto-approval per pane from PlexusOne Desktop
3. **Safety**: Surface blocked dangerous commands to the user
4. **Simplicity**: Minimal changes to both projects; loose coupling

## Non-Goals

- Embedding AgentSentinel logic directly in PlexusOne Desktop (keep as separate process)
- Real-time streaming of approval events (polling is sufficient)
- Replacing AgentSentinel's CLI interface

## Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         PlexusOne Desktop App                               │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Grid Layout                           │   │
│  │  ┌─────────────────┐  ┌─────────────────┐               │   │
│  │  │ Pane 1          │  │ Pane 2          │               │   │
│  │  │ 🤖 Auto-approve │  │ ⏸ Manual        │               │   │
│  │  │ ✓ 12 | ✗ 0     │  │                 │               │   │
│  │  │ coder-1         │  │ reviewer        │               │   │
│  │  └─────────────────┘  └─────────────────┘               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ SentinelManager                                          │   │
│  │ - Reads ~/.agentsentinel/status.json (every 2s)         │   │
│  │ - Provides status per session/pane                       │   │
│  │ - Can start/stop sentinel via CLI                        │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
              reads status    │    (optional) sends commands
                              ▼
              ~/.agentsentinel/status.json
              ~/.agentsentinel/control.sock (future)
                              │
                              │
┌─────────────────────────────────────────────────────────────────┐
│              AgentSentinel Daemon (Go)                          │
│                                                                 │
│  - Single process watching all tmux panes                       │
│  - Writes status.json every 2 seconds                          │
│  - Logs approvals/blocks to stats file                         │
│  - Runs independently of PlexusOne Desktop                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Communication Protocol

**Phase 1: Status File (Read-only)**

AgentSentinel writes status to `~/.agentsentinel/status.json`:

```json
{
  "version": 1,
  "pid": 12345,
  "started_at": "2026-03-20T10:00:00Z",
  "uptime_seconds": 3600,
  "config": {
    "interval_ms": 500,
    "block_danger": true,
    "notifications": true
  },
  "watching": [
    {
      "session": "coder-1",
      "pane_id": "%5",
      "pane_title": "claude",
      "approvals": 12,
      "blocked": 0,
      "last_approval_at": "2026-03-20T10:05:00Z",
      "last_blocked_at": null,
      "last_blocked_command": null
    },
    {
      "session": "reviewer",
      "pane_id": "%8",
      "pane_title": "codex",
      "approvals": 5,
      "blocked": 1,
      "last_approval_at": "2026-03-20T10:04:30Z",
      "last_blocked_at": "2026-03-20T10:03:00Z",
      "last_blocked_command": "rm -rf /"
    }
  ],
  "totals": {
    "approvals": 17,
    "blocked": 1,
    "panes_watched": 2
  },
  "updated_at": "2026-03-20T10:05:02Z"
}
```

**Phase 2: Control Socket (Future)**

Unix socket at `~/.agentsentinel/control.sock` for commands:

```json
// Request
{"command": "pause", "session": "coder-1"}
{"command": "resume", "session": "coder-1"}
{"command": "status"}

// Response
{"ok": true}
{"ok": false, "error": "session not found"}
```

## Changes Required

### AgentSentinel (Go)

#### New Package: `internal/status`

```go
package status

import (
    "encoding/json"
    "os"
    "path/filepath"
    "time"
)

type Status struct {
    Version      int            `json:"version"`
    PID          int            `json:"pid"`
    StartedAt    time.Time      `json:"started_at"`
    UptimeSeconds int64         `json:"uptime_seconds"`
    Config       ConfigStatus   `json:"config"`
    Watching     []PaneStatus   `json:"watching"`
    Totals       TotalStatus    `json:"totals"`
    UpdatedAt    time.Time      `json:"updated_at"`
}

type ConfigStatus struct {
    IntervalMs    int  `json:"interval_ms"`
    BlockDanger   bool `json:"block_danger"`
    Notifications bool `json:"notifications"`
}

type PaneStatus struct {
    Session           string     `json:"session"`
    PaneID            string     `json:"pane_id"`
    PaneTitle         string     `json:"pane_title,omitempty"`
    Approvals         int        `json:"approvals"`
    Blocked           int        `json:"blocked"`
    LastApprovalAt    *time.Time `json:"last_approval_at,omitempty"`
    LastBlockedAt     *time.Time `json:"last_blocked_at,omitempty"`
    LastBlockedCmd    string     `json:"last_blocked_command,omitempty"`
}

type TotalStatus struct {
    Approvals    int `json:"approvals"`
    Blocked      int `json:"blocked"`
    PanesWatched int `json:"panes_watched"`
}

type Writer struct {
    path      string
    startedAt time.Time
}

func NewWriter() *Writer {
    home, _ := os.UserHomeDir()
    dir := filepath.Join(home, ".agentsentinel")
    os.MkdirAll(dir, 0755)

    return &Writer{
        path:      filepath.Join(dir, "status.json"),
        startedAt: time.Now(),
    }
}

func (w *Writer) Write(status *Status) error {
    status.Version = 1
    status.PID = os.Getpid()
    status.StartedAt = w.startedAt
    status.UptimeSeconds = int64(time.Since(w.startedAt).Seconds())
    status.UpdatedAt = time.Now()

    data, err := json.MarshalIndent(status, "", "  ")
    if err != nil {
        return err
    }

    // Write atomically
    tmpPath := w.path + ".tmp"
    if err := os.WriteFile(tmpPath, data, 0644); err != nil {
        return err
    }
    return os.Rename(tmpPath, w.path)
}

func (w *Writer) Remove() error {
    return os.Remove(w.path)
}
```

#### Update Watcher

```go
// In watcher.go, add status writing to the main loop:

func (w *Watcher) Run(ctx context.Context) error {
    statusWriter := status.NewWriter()
    defer statusWriter.Remove()  // Clean up on exit

    ticker := time.NewTicker(w.interval)
    statusTicker := time.NewTicker(2 * time.Second)
    defer ticker.Stop()
    defer statusTicker.Stop()

    for {
        select {
        case <-ctx.Done():
            return nil
        case <-ticker.C:
            w.scan()
        case <-statusTicker.C:
            w.writeStatus(statusWriter)
        }
    }
}

func (w *Watcher) writeStatus(sw *status.Writer) {
    panes := w.getPaneStatuses()

    sw.Write(&status.Status{
        Config: status.ConfigStatus{
            IntervalMs:    int(w.interval.Milliseconds()),
            BlockDanger:   w.blockDanger,
            Notifications: w.notifications,
        },
        Watching: panes,
        Totals: status.TotalStatus{
            Approvals:    w.totalApprovals,
            Blocked:      w.totalBlocked,
            PanesWatched: len(panes),
        },
    })
}
```

#### New CLI Command: `agentsentinel status --json`

```go
// cmd/status.go - add JSON output option

var statusJSONFlag bool

func init() {
    statusCmd.Flags().BoolVar(&statusJSONFlag, "json", false, "Output status as JSON")
}

func runStatus(cmd *cobra.Command, args []string) error {
    status, err := readStatusFile()
    if err != nil {
        if os.IsNotExist(err) {
            if statusJSONFlag {
                fmt.Println(`{"running": false}`)
            } else {
                fmt.Println("AgentSentinel is not running")
            }
            return nil
        }
        return err
    }

    if statusJSONFlag {
        data, _ := json.MarshalIndent(status, "", "  ")
        fmt.Println(string(data))
    } else {
        printHumanStatus(status)
    }
    return nil
}
```

### PlexusOne Desktop (Swift)

#### New Service: `SentinelManager`

```swift
// Services/SentinelManager.swift

import Foundation
import Observation

struct SentinelStatus: Codable {
    let version: Int
    let pid: Int
    let startedAt: Date
    let uptimeSeconds: Int64
    let config: SentinelConfig
    let watching: [PaneWatchStatus]
    let totals: SentinelTotals
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case version, pid, config, watching, totals
        case startedAt = "started_at"
        case uptimeSeconds = "uptime_seconds"
        case updatedAt = "updated_at"
    }
}

struct SentinelConfig: Codable {
    let intervalMs: Int
    let blockDanger: Bool
    let notifications: Bool

    enum CodingKeys: String, CodingKey {
        case intervalMs = "interval_ms"
        case blockDanger = "block_danger"
        case notifications
    }
}

struct PaneWatchStatus: Codable {
    let session: String
    let paneId: String
    let paneTitle: String?
    let approvals: Int
    let blocked: Int
    let lastApprovalAt: Date?
    let lastBlockedAt: Date?
    let lastBlockedCommand: String?

    enum CodingKeys: String, CodingKey {
        case session, approvals, blocked
        case paneId = "pane_id"
        case paneTitle = "pane_title"
        case lastApprovalAt = "last_approval_at"
        case lastBlockedAt = "last_blocked_at"
        case lastBlockedCommand = "last_blocked_command"
    }
}

struct SentinelTotals: Codable {
    let approvals: Int
    let blocked: Int
    let panesWatched: Int

    enum CodingKeys: String, CodingKey {
        case approvals, blocked
        case panesWatched = "panes_watched"
    }
}

@Observable
class SentinelManager {
    private(set) var status: SentinelStatus?
    private(set) var isRunning: Bool = false
    private(set) var lastError: Error?

    private var refreshTask: Task<Void, Never>?
    private let statusPath: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        statusPath = home.appendingPathComponent(".agentsentinel/status.json")
    }

    func startMonitoring() {
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopMonitoring() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() async {
        do {
            let data = try Data(contentsOf: statusPath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            status = try decoder.decode(SentinelStatus.self, from: data)
            isRunning = true
            lastError = nil
        } catch {
            if (error as NSError).code == NSFileReadNoSuchFileError {
                isRunning = false
                status = nil
            } else {
                lastError = error
            }
        }
    }

    func statusForSession(_ session: String) -> PaneWatchStatus? {
        status?.watching.first { $0.session == session }
    }

    func isWatching(_ session: String) -> Bool {
        statusForSession(session) != nil
    }
}
```

#### Update PaneHeaderView

```swift
// In PaneView.swift, update header to show sentinel status:

struct PaneHeaderView: View {
    // ... existing properties ...
    let sentinelStatus: PaneWatchStatus?

    var body: some View {
        HStack(spacing: 4) {
            // Session dropdown (existing)
            // ...

            Spacer()

            // Sentinel status indicator
            if let sentinel = sentinelStatus {
                HStack(spacing: 2) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.green)
                    Text("✓\(sentinel.approvals)")
                        .font(.system(size: 9))
                        .foregroundColor(.green)
                    if sentinel.blocked > 0 {
                        Text("✗\(sentinel.blocked)")
                            .font(.system(size: 9))
                            .foregroundColor(.red)
                    }
                }
                .help("Auto-approve active: \(sentinel.approvals) approved, \(sentinel.blocked) blocked")
            }

            // ... rest of header ...
        }
    }
}
```

## UI Mockups

### Pane Header with Sentinel Status

```
┌──────────────────────────────────────────────────────────────┐
│ [▼ coder-1 🟢]            ⚡✓12 ✗0            #1    [×]     │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  Terminal content here...                                    │
│                                                              │
└──────────────────────────────────────────────────────────────┘

Legend:
⚡ = Sentinel active (bolt icon)
✓12 = 12 approvals (green)
✗0 = 0 blocked (red if > 0)
```

### Status Bar with Global Sentinel Status

```
┌──────────────────────────────────────────────────────────────┐
│ #1 🟢 coder-1 │ #2 🟡 reviewer │  ⚡ Sentinel: ✓45 ✗2  │ + │
└──────────────────────────────────────────────────────────────┘
```

### Blocked Command Alert (Toast)

```
┌────────────────────────────────────────┐
│ ⚠️ Dangerous command blocked          │
│ rm -rf / in coder-1                    │
│ [View] [Dismiss]                       │
└────────────────────────────────────────┘
```

## Implementation Phases

### Phase 1: Status File (MVP)

**AgentSentinel:**
- [ ] Add `internal/status` package
- [ ] Update watcher to write status.json every 2s
- [ ] Add `--json` flag to `status` command
- [ ] Clean up status file on graceful shutdown

**PlexusOne Desktop:**
- [ ] Add `SentinelManager` service
- [ ] Display sentinel status in pane header
- [ ] Show global totals in status bar

### Phase 2: Enhanced Visibility

**PlexusOne Desktop:**
- [ ] Toast notifications for blocked commands
- [ ] Sentinel status in Settings
- [ ] Historical stats view (read from log file)

### Phase 3: Control (Future)

**AgentSentinel:**
- [ ] Unix socket for control commands
- [ ] Pause/resume per session
- [ ] Dynamic pattern updates

**PlexusOne Desktop:**
- [ ] Start/stop sentinel from UI
- [ ] Per-pane enable/disable toggle
- [ ] Pattern configuration UI

## Testing

### AgentSentinel

```bash
# Start sentinel
agentsentinel watch --notify &

# Check status file
cat ~/.agentsentinel/status.json

# Check JSON output
agentsentinel status --json
```

### PlexusOne Desktop

```swift
// Unit test for SentinelManager
func testStatusParsing() {
    let json = """
    {"version":1,"pid":123,"watching":[...]}
    """
    let status = try JSONDecoder().decode(SentinelStatus.self, from: json.data(using: .utf8)!)
    XCTAssertEqual(status.pid, 123)
}
```

## Open Questions

1. **Status file location**: `~/.agentsentinel/status.json` or XDG-compliant path?
2. **Polling interval**: 2 seconds sufficient? Should it be configurable?
3. **Multiple instances**: Should we support multiple sentinel processes? (Current design assumes single daemon)
4. **Startup**: Should PlexusOne Desktop auto-start AgentSentinel if not running?

## References

- [AgentSentinel Repository](https://github.com/plexusone/agentsentinel)
- [PlexusOne Desktop PRD](./prd.md)
- [PlexusOne Desktop TRD](./trd.md)
