import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let store: UsageStore
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let statusHostView: ClickThroughHostingView<MenuBarStatusView>

    init(store: UsageStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: 180)
        popover = NSPopover()
        statusHostView = ClickThroughHostingView(rootView: MenuBarStatusView(store: store))

        super.init()

        configurePopover()
        configureStatusItem()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .vibrantDark)
        popover.contentSize = NSSize(width: 320, height: 360)
        popover.contentViewController = NSHostingController(
            rootView: UsagePopoverView(store: store)
                .frame(width: 320)
                .preferredColorScheme(.dark)
        )
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.title = ""
        button.image = nil
        button.target = self
        button.action = #selector(togglePopover(_:))

        statusHostView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(statusHostView)

        NSLayoutConstraint.activate([
            statusHostView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 2),
            statusHostView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -2),
            statusHostView.topAnchor.constraint(equalTo: button.topAnchor),
            statusHostView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
    }

    @objc
    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            store.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.becomeKey()
        }
    }
}

final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
