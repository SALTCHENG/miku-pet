import AppKit
import SwiftUI

@main
struct MikuPetApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)   // 不占 Dock，后台运行
        let delegate = PetDelegate()
        app.delegate = delegate
        app.run()
    }
}

class PetDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var petView: PetView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = NSSize(width: 258, height: 419)   // 516x838 @ 2x Retina
        let screen = NSScreen.main!
        let origin = NSPoint(x: screen.visibleFrame.maxX - size.width - 20,
                            y: screen.visibleFrame.minY + 20)
        let frame = NSRect(origin: origin, size: size)

        window = NSWindow(contentRect: frame, styleMask: .borderless,
                          backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = true
        window.acceptsMouseMovedEvents = true

        petView = PetView(frame: NSRect(origin: .zero, size: size))
        window.contentView = petView
        window.orderFrontRegardless()
        petView.startAnimations()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
