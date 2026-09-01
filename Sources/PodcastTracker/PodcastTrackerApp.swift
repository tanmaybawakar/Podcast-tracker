import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var primaryWindowController: NSWindowController?
    private var requestedInitialWindow = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        Task { @MainActor in NotificationManager.shared.registerBeforeLaunchCompletes() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        requestInitialWindowIfNeeded()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        requestInitialWindowIfNeeded()
        AppViewModel.shared.refreshCloudData()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPrimaryWindow()
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "podtrackio" {
            AuthManager.shared.handleCallback(url: url)
        }
        showPrimaryWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppViewModel.shared.saveData()
    }

    func showPrimaryWindow() {
        if let window = primaryWindowController?.window {
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if let window = NSApp.windows.first(where: { $0.title == "PodTrackio" }) {
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = MainView()
            .environmentObject(AppViewModel.shared)
            .environmentObject(AuthManager.shared)
            .frame(minWidth: 860, minHeight: 620)
        let hostingController = NSHostingController(rootView: rootView)
        #if APP_STORE
        let initialSize = NSSize(width: 1440, height: 900)
        #else
        let initialSize = NSSize(width: 1280, height: 820)
        #endif
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "PodTrackio"
        window.minSize = NSSize(width: 860, height: 620)
        window.contentViewController = hostingController
        window.setContentSize(initialSize)
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        #if !APP_STORE
        window.setFrameAutosaveName("PodTrackioMainWindow")
        #endif
        window.center()

        let controller = NSWindowController(window: window)
        primaryWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        captureScreenshotIfRequested(from: window)
    }

    private func captureScreenshotIfRequested(from window: NSWindow) {
        #if SCREENSHOT_CAPTURE
        let environment = ProcessInfo.processInfo.environment
        guard let outputPath = environment["PODTRACKIO_SCREENSHOT_PATH"] else { return }
        switch environment["PODTRACKIO_SCREENSHOT_VIEW"] {
        case "library": AppViewModel.shared.selectedSection = .library
        case "progress": AppViewModel.shared.selectedSection = .progress
        case "add": AppViewModel.shared.showAddPodcast = true
        default: AppViewModel.shared.selectedSection = .today
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard let view = window.contentView,
                  let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: representation)
            guard let data = representation.representation(using: .png, properties: [:]) else { return }
            try? data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        }
        #endif
    }

    private func requestInitialWindowIfNeeded() {
        guard !requestedInitialWindow else { return }
        requestedInitialWindow = true
        DispatchQueue.main.async { [weak self] in
            self?.showPrimaryWindow()
        }
    }
}

@main
struct PodcastTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel.shared

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(viewModel)
                .environmentObject(AuthManager.shared)
                .frame(minWidth: 680, minHeight: 540)
        }

        MenuBarExtra {
            MenuBarLearningView()
                .environmentObject(viewModel)
        } label: {
            MenuBarStatusLabel().environmentObject(viewModel)
        }
        .menuBarExtraStyle(.menu)
        .commands {
            // The main window is owned by AppDelegate. Replacing the standard
            // New Window command prevents SwiftUI from creating a second copy.
            CommandGroup(replacing: .newItem) {
                Button("Add Episode…") {
                    appDelegate.showPrimaryWindow()
                    viewModel.showAddPodcast = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Learning") {
                Button("Today") {
                    appDelegate.showPrimaryWindow()
                    viewModel.selectedPodcast = nil
                    viewModel.selectedSection = .today
                }
                .keyboardShortcut("1", modifiers: .command)
                Button("Library") {
                    appDelegate.showPrimaryWindow()
                    viewModel.selectedPodcast = nil
                    viewModel.selectedSection = .library
                }
                .keyboardShortcut("2", modifiers: .command)
                Button("Progress") {
                    appDelegate.showPrimaryWindow()
                    viewModel.selectedPodcast = nil
                    viewModel.selectedSection = .progress
                }
                .keyboardShortcut("3", modifiers: .command)
                Divider()
                Button("Distraction Rescue…") {
                    appDelegate.showPrimaryWindow()
                    viewModel.showRescueSheet = true
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(viewModel.nextPodcast == nil)
            }
        }
    }
}

private struct MenuBarStatusLabel: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var requestedInitialWindow = false

    var body: some View {
        Label(
            viewModel.isTracking ? "PodTrackio learning" : "PodTrackio",
            systemImage: viewModel.isTracking ? "waveform.circle.fill" : "headphones.circle"
        )
        .task {
            guard !requestedInitialWindow else { return }
            requestedInitialWindow = true
            try? await Task.sleep(for: .milliseconds(150))
            (NSApp.delegate as? AppDelegate)?.showPrimaryWindow()
        }
    }
}
