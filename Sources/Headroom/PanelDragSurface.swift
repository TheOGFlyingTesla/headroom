import AppKit
import SwiftUI

/// SwiftUI hosting content consumes clicks that NSPanel's background-drag flag
/// would otherwise receive. Move the borderless panel from pointer deltas in
/// noninteractive areas; native performDrag can return without moving it.
private struct PanelDragSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        private var dragStart: (pointer: NSPoint, origin: NSPoint)?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            dragStart = (window.convertPoint(toScreen: event.locationInWindow), window.frame.origin)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window, let start = dragStart else { return }
            let pointer = window.convertPoint(toScreen: event.locationInWindow)
            window.setFrameOrigin(NSPoint(x: start.origin.x + pointer.x - start.pointer.x,
                                          y: start.origin.y + pointer.y - start.pointer.y))
        }

        override func mouseUp(with event: NSEvent) {
            dragStart = nil
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}

extension View {
    func floatingDragSurface(_ enabled: Bool) -> some View {
        overlay {
            if enabled {
                PanelDragSurface()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
        }
    }
}
