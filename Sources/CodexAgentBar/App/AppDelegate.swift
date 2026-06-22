import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = QuotaStore()
    private var statusItem: NSStatusItem?
    private var menuBarView: MenuBarQuotaView?
    private var popover: NSPopover?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        bindStore()
        updateMenuBarTitle()
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: 84)
        statusItem = item

        guard let button = item.button else {
            return
        }

        let view = MenuBarQuotaView(frame: NSRect(x: 0, y: 0, width: 84, height: NSStatusBar.system.thickness))
        view.target = self
        view.action = #selector(togglePopover(_:))
        view.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            view.topAnchor.constraint(equalTo: button.topAnchor),
            view.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
        menuBarView = view
    }

    private func configurePopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 320, height: 248)
        popover.contentViewController = NSHostingController(
            rootView: QuotaPopoverView(
                store: store,
                onQuit: {
                    NSApp.terminate(nil)
                }
            )
        )
        self.popover = popover
    }

    private func bindStore() {
        store.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMenuBarTitle()
            }
            .store(in: &cancellables)

        store.$statusMessage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMenuBarTitle()
            }
            .store(in: &cancellables)
    }

    private func updateMenuBarTitle() {
        menuBarView?.update(snapshot: store.snapshot, statusMessage: store.statusMessage)
    }

    @objc private func togglePopover(_ sender: NSControl) {
        guard let popover else {
            return
        }

        if popover.isShown {
            closePopover(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            installOutsideClickMonitors()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        removeOutsideClickMonitors()
    }

    private func closePopover(_ sender: Any?) {
        popover?.performClose(sender)
        removeOutsideClickMonitors()
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else {
                return event
            }

            if self.shouldClosePopover(for: event) {
                self.closePopover(event)
            }

            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.closePopover(event)
        }
    }

    private func removeOutsideClickMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }

        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    private func shouldClosePopover(for event: NSEvent) -> Bool {
        guard popover?.isShown == true else {
            return false
        }

        if let menuBarView, containsEventLocation(event, in: menuBarView) {
            return false
        }

        if let popoverView = popover?.contentViewController?.view, containsEventLocation(event, in: popoverView) {
            return false
        }

        return true
    }

    private func containsEventLocation(_ event: NSEvent, in view: NSView) -> Bool {
        guard let window = view.window else {
            return false
        }

        let pointInWindow = event.window === window
            ? event.locationInWindow
            : window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let pointInView = view.convert(pointInWindow, from: nil)
        return view.bounds.contains(pointInView)
    }
}
