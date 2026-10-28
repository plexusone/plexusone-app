# Terminal Scrollbar - Technical Requirements Document

## Overview

This document defines the implementation approach for fixing terminal scrollbar functionality in the PlexusOne Desktop desktop app.

## Background

See [FEAT_SCROLLBAR_RESEARCH.md](FEAT_SCROLLBAR_RESEARCH.md) for problem analysis, attempted solutions, and research findings.

**Root Cause**: The current implementation uses `NSViewControllerRepresentable` to embed SwiftTerm's `LocalProcessTerminalView`. This appears to interfere with event routing, preventing scroll events from reaching the terminal view and its internal `NSScroller`.

## Chosen Approach

**Use `NSViewRepresentable` with a custom terminal subclass**, following SwiftTerm's own iOS SwiftUI implementation pattern.

### Rationale

1. SwiftTerm's iOS implementation (`SwiftUITerminalView.swift`) uses `UIViewRepresentable` directly - not a view controller wrapper
2. They create a custom subclass that explicitly handles layout changes
3. This pattern has been tested by the SwiftTerm maintainers

## Implementation Design

### Component Changes

#### 1. New: `AppTerminalView` (Custom Subclass)

Location: `Sources/PlexusOneDesktop/Views/AppTerminalView.swift`

```swift
import AppKit
import SwiftTerm

/// Custom LocalProcessTerminalView subclass for SwiftUI integration
/// Handles explicit size tracking and layout updates
class AppTerminalView: LocalProcessTerminalView {
    private var lastAppliedSize: CGSize = .zero

    /// Callback when session ends
    var onSessionEnded: (() -> Void)?

    /// Callback when terminal title changes
    var onTitleChanged: ((String) -> Void)?

    override func layout() {
        super.layout()
        updateSizeIfNeeded()
    }

    func updateSizeIfNeeded() {
        let newSize = bounds.size
        guard newSize.width > 0, newSize.height > 0 else { return }
        guard newSize != lastAppliedSize else { return }

        lastAppliedSize = newSize
        // SwiftTerm recalculates terminal dimensions on layout
        // No additional action needed - layout() triggers this
    }

    // MARK: - Session Management

    func attach(to session: Session) {
        let (tmuxPath, baseArgs) = findTmuxExecutable()
        let args = baseArgs + ["attach", "-t", session.tmuxSession]

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        if env["LANG"] == nil {
            env["LANG"] = "en_US.UTF-8"
        }

        let envArray = env.map { "\($0.key)=\($0.value)" }

        startProcess(
            executable: tmuxPath,
            args: args,
            environment: envArray,
            execName: "tmux"
        )
    }

    private func findTmuxExecutable() -> (path: String, baseArgs: [String]) {
        let paths = [
            "/usr/local/bin/tmux",
            "/opt/homebrew/bin/tmux",
            "/usr/bin/tmux"
        ]

        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return (path, [])
            }
        }

        return ("/usr/bin/env", ["tmux"])
    }
}
```

#### 2. Modified: `TerminalViewRepresentable`

Change from `NSViewControllerRepresentable` to `NSViewRepresentable`:

```swift
import SwiftUI
import AppKit
import SwiftTerm

/// SwiftUI wrapper for AppTerminalView using NSViewRepresentable
struct TerminalViewRepresentable: NSViewRepresentable {
    typealias NSViewType = AppTerminalView

    @Binding var attachedSession: Session?
    let sessionManager: SessionManager
    var onSessionEnded: (() -> Void)?

    func makeNSView(context: Context) -> AppTerminalView {
        let view = AppTerminalView(frame: .zero)
        view.processDelegate = context.coordinator

        // Configure appearance
        configureAppearance(view)

        return view
    }

    func updateNSView(_ view: AppTerminalView, context: Context) {
        // Ensure layout is current
        view.updateSizeIfNeeded()

        // Handle session attachment changes
        if let session = attachedSession {
            // Check if we need to attach to a new session
            // (view doesn't track session ID, so we use coordinator)
            if context.coordinator.currentSessionId != session.id {
                context.coordinator.currentSessionId = session.id
                view.attach(to: session)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func configureAppearance(_ view: AppTerminalView) {
        let fontSize: CGFloat = 13
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        view.font = font

        view.nativeBackgroundColor = NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        view.nativeForegroundColor = NSColor(calibratedRed: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)
        view.caretColor = NSColor.white
        view.changeScrollback(10000)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var parent: TerminalViewRepresentable
        var currentSessionId: UUID?

        init(_ parent: TerminalViewRepresentable) {
            self.parent = parent
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            DispatchQueue.main.async { [weak self] in
                self?.currentSessionId = nil
                self?.parent.onSessionEnded?()
            }
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            // Terminal size changed - tmux handles via SIGWINCH
        }

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            // Could propagate to parent if needed
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            // Could be used to update UI
        }

        func requestOpenLink(source: LocalProcessTerminalView, link: String, params: [String: String]) {
            if let url = URL(string: link) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
```

#### 3. Remove: `TerminalViewController`

The `TerminalViewController.swift` file becomes unnecessary and can be deleted.

### File Changes Summary

| File | Action |
|------|--------|
| `Sources/PlexusOneDesktop/Views/AppTerminalView.swift` | Create new |
| `Sources/PlexusOneDesktop/Views/TerminalViewRepresentable.swift` | Rewrite |
| `Sources/PlexusOneDesktop/Controllers/TerminalViewController.swift` | Delete |

### No Changes Required

- `PaneView.swift` - Already uses `TerminalViewRepresentable`
- `ContentView.swift` - No direct terminal dependencies
- `GridLayoutView.swift` - No direct terminal dependencies

## Acceptance Criteria

1. **Scrollbar Visibility**
   - [ ] Scrollbar visible when terminal has scrollback content
   - [ ] Scrollbar thumb size reflects content proportion

2. **Scrollbar Interaction**
   - [ ] Click and drag scrollbar thumb to scroll
   - [ ] Click on scrollbar track to page up/down

3. **Trackpad/Mouse Scrolling**
   - [ ] Two-finger scroll on trackpad works
   - [ ] Mouse wheel scrolling works

4. **Existing Functionality Preserved**
   - [ ] Keyboard input works
   - [ ] Terminal fills pane correctly
   - [ ] Session attach/detach works
   - [ ] Multiple panes work independently
   - [ ] Restore modal works and is clickable
   - [ ] App activates properly (dock, cmd+tab)

## Testing Plan

1. **Build and launch app**
2. **Create/attach to tmux session**
3. **Generate scrollback content**: `for i in {1..200}; do echo "line $i"; done`
4. **Test scrollbar**:
   - Verify thumb appears
   - Drag thumb up/down
   - Click track to page
5. **Test trackpad**: Two-finger scroll up/down
6. **Test keyboard**: Type commands, verify input works
7. **Test multiple panes**: Ensure each pane scrolls independently
8. **Test app lifecycle**: Close/reopen, dock click, cmd+tab

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| NSViewRepresentable may have same issues | Revert to previous working state; file GitHub issue |
| Detach handling changes | Track session state in Coordinator |
| Performance with multiple terminals | Monitor; each view is independent |

## Rollback Plan

If implementation fails:
1. `git checkout` to restore previous working state
2. Document findings in FEAT_SCROLLBAR_RESEARCH.md
3. Consider filing GitHub issue with SwiftTerm maintainers
