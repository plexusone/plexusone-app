# Terminal Scrollbar Research

## Problem Statement

The PlexusOne Desktop desktop app embeds SwiftTerm's `LocalProcessTerminalView` (an AppKit `NSView`) within SwiftUI using `NSViewControllerRepresentable`. The terminal's built-in scrollbar is visible but not interactive:

- Scrollbar appears as a grey bar on the right side of each terminal pane
- Clicking/dragging the scrollbar does not work
- Trackpad/mouse wheel scrolling does not work
- The scrollbar thumb (knob) only appears when there's scrollable content

## Requirements

1. **Scrollbar visibility**: Show a scrollbar when content exceeds visible area
2. **Scrollbar interaction**: Click and drag the scrollbar thumb to scroll
3. **Trackpad/wheel scrolling**: Support native scroll gestures
4. **Keyboard input**: Must not break terminal keyboard input
5. **Terminal sizing**: Terminal must fill the pane correctly

## Technical Context

### SwiftTerm Scrollbar Implementation

SwiftTerm creates an `NSScroller` internally in `MacTerminalView.swift`:

```swift
let scrollerStyle: NSScroller.Style = .legacy  // Always visible

func setupScroller() {
    scroller = NSScroller(frame: .zero)
    scroller.translatesAutoresizingMaskIntoConstraints = false
    addSubview(scroller)

    // Auto Layout constraints position scroller at trailing edge
    NSLayoutConstraint.activate([
        scroller.trailingAnchor.constraint(equalTo: trailingAnchor),
        scroller.topAnchor.constraint(equalTo: topAnchor),
        scroller.bottomAnchor.constraint(equalTo: bottomAnchor),
        scroller.widthAnchor.constraint(equalToConstant: scrollerWidth)
    ])

    scroller.scrollerStyle = scrollerStyle
    scroller.knobProportion = 0.1
    scroller.isEnabled = false  // Enabled when canScroll becomes true
    scroller.action = #selector(scrollerActivated)
    scroller.target = self
}
```

Key properties:
- `canScroll`: Returns `true` when `lines.count > rows` (content exceeds visible area)
- `scrollPosition`: Returns scroll position as 0.0-1.0
- `scrollThumbsize`: Returns thumb proportion based on visible vs total content
- `scrollWheel(with:)`: Handles trackpad/wheel events, calls `scrollUp/scrollDown`

### Debug Output (from our testing)

When running the app, the scroller IS present:
```
Scroller found - frame: (757.0, 0.0, 15.0, 743.0)
isEnabled: false, isHidden: false, knobProportion: 1.0, style: 0 (legacy)
canScroll: false, scrollPosition: 0.0
```

This confirms:
- Scroller exists at correct position (15px wide at right edge)
- Style is `.legacy` (always visible)
- `isEnabled: false` because no scrollable content yet
- `knobProportion: 1.0` means thumb fills entire bar (nothing to scroll)

## What We Tried

### Attempt 1: First Responder Focus

**Hypothesis**: Terminal view isn't receiving events because it's not the first responder.

**Changes**:
- Added `viewDidAppear()` to call `window?.makeFirstResponder(terminalView)`
- Added focus request after `attach(to:)` completes
- Added focus request in `updateNSViewController`

**Result**: Did not fix scrolling. Also caused issues with app activation and the restore modal becoming unresponsive.

### Attempt 2: Hit Testing on Overlay

**Hypothesis**: The SwiftUI border overlay on `PaneView` intercepts mouse events.

**Changes**:
- Added `.allowsHitTesting(false)` to the `RoundedRectangle` stroke overlay

**Result**: Did not fix scrolling.

### Attempt 3: Layout and Autoresizing

**Hypothesis**: Terminal view not properly sized, affecting scroller constraints.

**Changes**:
- Added `viewDidLayout()` to set `terminalView.frame = view.bounds`
- Set `translatesAutoresizingMaskIntoConstraints = true`
- Set `autoresizingMask = [.width, .height]`

**Result**: Did not fix scrolling.

### Attempt 4: Custom Scrollbar Overlay (Reverted)

**Hypothesis**: Replace SwiftTerm's internal scroller with a custom SwiftUI scrollbar.

**Changes**:
- Created `TerminalScrollbar` SwiftUI view with drag gesture
- Added scroll position bindings to `TerminalViewRepresentable`
- Wrapped terminal in `TerminalWithScrollbar` container

**Result**:
- Scrollbar appeared with position indicator
- Could NOT scroll up/down or interact with scrollbar
- Keyboard input to terminal STOPPED working
- Terminal did NOT fill vertical height properly
- Had to revert all changes

### Attempt 5: App Activation Improvements (Reverted)

**Hypothesis**: Focus issues caused by improper app activation sequence.

**Changes**:
- Modified `applicationDidFinishLaunching` timing
- Added `applicationShouldHandleReopen` handler
- Added `applicationDidBecomeActive` handler
- Delayed restore prompt display

**Result**: Made things worse - app became completely unresponsive (greyed window controls, unclickable menu bar, restore modal buttons not working). Had to revert.

## Analysis

### Why Events Aren't Reaching the Scroller

The scroller exists and is positioned correctly. The issue is that mouse/scroll events aren't being delivered to it. Possible causes:

1. **SwiftUI/AppKit event routing**: When `NSView` is embedded via `NSViewControllerRepresentable`, SwiftUI may intercept or not forward certain events.

2. **Responder chain**: The scroller may not be in the responder chain properly when embedded in SwiftUI.

3. **Hit testing**: SwiftUI's hit testing may not resolve clicks to the scroller correctly.

4. **Layer interaction**: With `wantsLayer = true` and `clipsToBounds = true` (on macOS 14+), there may be layer-level event issues.

### Why `scrollWheel` Events Don't Work

SwiftTerm implements `scrollWheel(with:)` which should handle trackpad scrolling:

```swift
public override func scrollWheel(with event: NSEvent) {
    if event.deltaY == 0 { return }
    let velocity = calcScrollingVelocity(delta: Int(abs(event.deltaY)))
    if event.deltaY > 0 {
        scrollUp(lines: velocity)
    } else {
        scrollDown(lines: velocity)
    }
}
```

If this isn't being called, the events aren't reaching the terminal view at all.

## Research: Possible Solutions

### Option A: Wrap Terminal in NSScrollView

Instead of using SwiftTerm's internal scroller, embed the terminal in an `NSScrollView`:

```swift
let scrollView = NSScrollView()
scrollView.documentView = terminalView
scrollView.hasVerticalScroller = true
scrollView.autohidesScrollers = false
```

**Pros**: Native scroll behavior, proper event handling
**Cons**: May conflict with SwiftTerm's internal scroll handling, sizing complexity

**Research needed**: Check if SwiftTerm supports being embedded in NSScrollView, or if it expects to manage its own scrolling.

### Option B: Event Forwarding Layer

Create an NSView subclass that sits above the terminal and forwards scroll/click events:

```swift
class EventForwardingView: NSView {
    weak var targetView: NSView?

    override func scrollWheel(with event: NSEvent) {
        targetView?.scrollWheel(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        // Check if click is in scroller area, forward appropriately
    }
}
```

**Pros**: Minimal changes to existing code
**Cons**: May still not solve the underlying event routing issue

### Option C: SwiftUI ScrollViewReader Integration

Use SwiftUI's `ScrollView` with a `ScrollViewReader` and sync scroll position with terminal:

```swift
ScrollView {
    ScrollViewReader { proxy in
        TerminalViewRepresentable(...)
            .frame(height: calculatedContentHeight)
    }
}
```

**Pros**: Native SwiftUI scrolling
**Cons**: Complex height calculation, may conflict with terminal sizing

### Option D: Disable SwiftTerm's Scroller, Use Custom

Modify or subclass the terminal view to disable its internal scroller and implement scrolling externally:

1. Subclass `LocalProcessTerminalView`
2. Override/hide the internal scroller
3. Expose scroll control methods
4. Create external SwiftUI scrollbar that calls these methods

**Pros**: Full control over scroll UI
**Cons**: More code, potential maintenance burden

### Option E: SwiftTerm GitHub Issues/Discussions

Research if others have encountered this issue:
- Check SwiftTerm GitHub issues for SwiftUI embedding problems
- Look for example projects using SwiftTerm with SwiftUI
- Consider opening an issue to ask maintainers

**Research links**:
- https://github.com/migueldeicaza/SwiftTerm/issues
- https://github.com/migueldeicaza/SwiftTerm/discussions
- https://github.com/migueldeicaza/SwiftTermApp (reference app)

### Option F: Alternative Terminal Libraries

Research alternative terminal emulator libraries that may have better SwiftUI support:

- Check if there are SwiftUI-native terminal implementations
- Look at how other macOS terminal apps handle this

## Recommended Next Steps

1. **Research SwiftTerm GitHub** (Option E): Check for existing issues/solutions about SwiftUI embedding
2. **Study SwiftTermApp**: Examine how the reference app handles scrolling
3. **Test NSScrollView wrapper** (Option A): Try wrapping in NSScrollView as simplest native solution
4. **Consider filing issue**: If no existing solution, file issue with SwiftTerm maintainers

## New Research Findings

### SwiftTerm's Own SwiftUI Implementation (iOS)

SwiftTerm has an internal iOS SwiftUI view in `SwiftTerm/Sources/SwiftTerm/iOS/SwiftUITerminalView.swift` that shows the recommended pattern:

```swift
// Uses UIViewRepresentable (NOT UIViewControllerRepresentable)
private struct TerminalViewContainer: UIViewRepresentable {
    typealias UIViewType = SwiftUITerminalHostView

    func makeUIView(context: Context) -> SwiftUITerminalHostView {
        let view = SwiftUITerminalHostView(frame: .zero)
        view.terminalDelegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: SwiftUITerminalHostView, context: Context) {
        uiView.updateSizeIfNeeded()
    }
}

// Custom subclass handles size updates
private final class SwiftUITerminalHostView: TerminalView {
    private var lastAppliedSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        updateSizeIfNeeded()
    }

    func updateSizeIfNeeded() {
        let newSize = bounds.size
        guard newSize.width.isFinite, newSize.width > 0,
              newSize.height.isFinite, newSize.height > 0 else { return }
        if newSize != lastAppliedSize {
            lastAppliedSize = newSize
            processSizeChange(newSize: newSize)
        }
    }
}
```

**Key differences from our implementation:**
1. Uses `UIViewRepresentable` directly on the view (not `UIViewControllerRepresentable`)
2. Creates a custom subclass that handles layout explicitly
3. Calls `processSizeChange(newSize:)` when bounds change

### SwiftTerm GitHub Issues Analysis

Relevant issues found:
- **#181**: "SwiftUI implementation not working as expected" - Solution was to use `terminalView.feed()` instead of `terminal.feed()`
- **#469**: "Fix NSScroller layout when TerminalView uses Auto Layout constraints" - Merged, included in v1.10.0+
- **#330**: "TerminalView does not respect frame height on macOS Sonoma" - Frame sizing issues

### Recommended Approach: NSViewRepresentable

Based on SwiftTerm's own iOS implementation, we should try using `NSViewRepresentable` instead of `NSViewControllerRepresentable`:

```swift
struct TerminalViewRepresentable: NSViewRepresentable {
    typealias NSViewType = AppTerminalView  // Custom subclass

    func makeNSView(context: Context) -> AppTerminalView {
        let view = AppTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: AppTerminalView, context: Context) {
        nsView.updateSizeIfNeeded()
    }
}

class AppTerminalView: LocalProcessTerminalView {
    private var lastAppliedSize: CGSize = .zero

    override func layout() {
        super.layout()
        updateSizeIfNeeded()
    }

    func updateSizeIfNeeded() {
        let newSize = bounds.size
        guard newSize.width > 0, newSize.height > 0 else { return }
        if newSize != lastAppliedSize {
            lastAppliedSize = newSize
            // Trigger terminal size recalculation
        }
    }
}
```

## Updated Recommendations

Based on new research:

1. **Try NSViewRepresentable** (HIGH PRIORITY): Switch from `NSViewControllerRepresentable` to `NSViewRepresentable` following SwiftTerm's own iOS pattern

2. **Create custom TerminalView subclass**: Override `layout()` to handle size changes explicitly

3. **File GitHub issue**: If the above doesn't work, file an issue on SwiftTerm specifically about macOS SwiftUI embedding with scroll issues

## References

- SwiftTerm repository: https://github.com/migueldeicaza/SwiftTerm
- SwiftTerm v1.12.0 (current version in use)
- PR #469: Fix NSScroller layout when TerminalView uses Auto Layout constraints
- Issue #181: SwiftUI implementation not working as expected
- SwiftTermApp (reference): https://github.com/migueldeicaza/SwiftTermApp
- SwiftTerm iOS SwiftUI implementation: `Sources/SwiftTerm/iOS/SwiftUITerminalView.swift`
- macOS AppKit/SwiftUI interop documentation
