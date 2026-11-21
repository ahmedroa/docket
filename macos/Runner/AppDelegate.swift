import Carbon.HIToolbox
import Cocoa
import FlutterMacOS

/// Docket lives in the menu bar. There is no Dock icon and no main window:
/// a single Flutter engine renders into a floating panel that drops down
/// from the status item (see `PanelController`).
@main
class AppDelegate: FlutterAppDelegate {
  private var engine: FlutterEngine!
  private var flutterViewController: FlutterViewController!
  private var panelController: PanelController!
  private var bridge: NativeBridge!

  override func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    // allowHeadlessExecution lets Dart start (load data, schedule reminders,
    // update the menu bar badge) before the panel has ever been shown.
    engine = FlutterEngine(name: "docket", project: nil, allowHeadlessExecution: true)
    RegisterGeneratedPlugins(registry: engine)

    flutterViewController = TracingFlutterViewController(engine: engine, nibName: nil, bundle: nil)
    flutterViewController.backgroundColor = .clear
    flutterViewController.mouseTrackingMode = .always

    panelController = PanelController(content: flutterViewController)
    bridge = NativeBridge(messenger: engine.binaryMessenger, panel: panelController)

    engine.run(withEntrypoint: nil)
    panelController.prewarm()

    let harness = ProcessInfo.processInfo.environment["DOCKET_HARNESS"]
    if harness == "activation" {
      let start = Date()
      func stamp() -> String { String(format: "%.2fs", Date().timeIntervalSince(start)) }
      NotificationCenter.default.addObserver(
        forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
      ) { _ in
        print("DOCKET_EVENT \(stamp()) app resigned active; front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-") buttons=\(NSEvent.pressedMouseButtons) mouse=\(NSEvent.mouseLocation)")
      }
      NotificationCenter.default.addObserver(
        forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
      ) { note in
        print("DOCKET_EVENT \(stamp()) window resigned key: \(type(of: note.object!)) buttons=\(NSEvent.pressedMouseButtons)")
      }
      _ = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
        print("DOCKET_EVENT \(stamp()) real click in another app at \(NSEvent.mouseLocation)")
      }
      // Opens the panel from a timer (no user input — the strictest case for
      // macOS activation rules) and reports whether it could take keyboard focus.
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        if ProcessInfo.processInfo.environment["DOCKET_ACTIVATION_MODE"] == "curtain" {
          let env = ProcessInfo.processInfo.environment
          self.panelController.configure(
            mode: .curtain, size: NSSize(width: 400, height: 640), curtainHeight: 0.78,
            animated: env["DOCKET_ACTIVATION_NOANIM"] != "1", blur: 0.85, tone: "auto")
          if env["DOCKET_ACTIVATION_NOGLASS"] == "1" { self.panelController.debugHideGlass() }
        }
        self.panelController.show(reason: "toggle")
        let stateAfterShow = "active=\(NSApp.isActive) key=\(self.panelController.panel.isKeyWindow) frame=\(self.panelController.panel.frame)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
          print("DOCKET_AT_SHOW \(stateAfterShow)")
          print("DOCKET_AFTER_SLIDE active=\(NSApp.isActive) key=\(self.panelController.panel.isKeyWindow) shown=\(self.panelController.isShown) lastHide=\(self.panelController.lastHideReason)")
          self.panelController.suppressAutoHide = true
          if ProcessInfo.processInfo.environment["DOCKET_ACTIVATION_DEACTIVATE"] == "1" {
            NSApp.deactivate()
          }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
          let report = "active=\(NSApp.isActive) key=\(self.panelController.panel.isKeyWindow) "
            + "frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-")"
          print("DOCKET_ACTIVATION \(report)")
          if let screen = self.panelController.panel.screen {
            print("DOCKET_FRAME panel=\(self.panelController.panel.frame) screen=\(screen.frame) visible=\(screen.visibleFrame)")
          }
          // Which window would a mouse-down at points inside the panel hit?
          let panel = self.panelController.panel
          let f = panel.frame
          var hits = 0, total = 0
          for fx in stride(from: 0.1, through: 0.9, by: 0.2) {
            for fy in stride(from: 0.1, through: 0.9, by: 0.2) {
              let point = NSPoint(x: f.minX + f.width * fx, y: f.minY + f.height * fy)
              total += 1
              if NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0) == panel.windowNumber { hits += 1 }
            }
          }
          print("DOCKET_HITTEST \(hits)/\(total) points inside the panel hit the panel")
          let probe = NSPoint(x: f.midX, y: f.midY)
          let hitNumber = NSWindow.windowNumber(at: probe, belowWindowWithWindowNumber: 0)
          let owner = (CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(hitNumber)) as? [[String: Any]])?
            .first?[kCGWindowOwnerName as String] ?? "?"
          print("DOCKET_LAST_HIDE \(self.panelController.lastHideReason)")
          // Responder chain from the Flutter view upwards.
          var chain: [String] = []
          let centre = NSPoint(x: panel.frame.width / 2, y: panel.frame.height / 2)
          var responder: NSResponder? = panel.contentView?.hitTest(centre)
          while let r = responder, chain.count < 8 {
            chain.append(String(describing: type(of: r)))
            responder = r.nextResponder
          }
          print("DOCKET_CHAIN \(chain.joined(separator: " → "))")
          // A click through AppKit's normal dispatch, at the panel's centre.
          _ = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            let view = panel.contentView?.hitTest(event.locationInWindow)
            print("DOCKET_APPKIT_MOUSEDOWN window=\(event.windowNumber) at=\(event.locationInWindow) view=\(view.map { String(describing: type(of: $0)) } ?? "nil")")
            return event
          }
          let local = NSPoint(x: panel.frame.width / 2, y: panel.frame.height / 2)
          for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(
              with: type, location: local, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
              windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            {
              NSApp.sendEvent(event)
            }
          }
          print("DOCKET_PANEL frame=\(f) visible=\(panel.isVisible) alpha=\(panel.alphaValue) level=\(panel.level.rawValue) ignores=\(panel.ignoresMouseEvents) number=\(panel.windowNumber) hit=\(hitNumber) hitOwner=\(owner)")
          let item = self.panelController.statusItem
          print("DOCKET_STATUS_ITEM visible=\(item.isVisible) frame=\(item.button?.window?.frame ?? .zero) image=\(item.button?.image != nil)")
          let hk = HotKeyCenter.shared
          print("DOCKET_HOTKEY ctrl-opt-T=\(hk.register(id: 1, keyCode: 17, modifiers: UInt32(controlKey | optionKey))) ctrl-opt-N=\(hk.register(id: 2, keyCode: 45, modifiers: UInt32(controlKey | optionKey)))")
          print("DOCKET_CONFLICT cmd-space=\(HotKeyCenter.systemConflict(keyCode: 49, modifiers: UInt32(cmdKey))) cmd-shift-4=\(HotKeyCenter.systemConflict(keyCode: 21, modifiers: UInt32(cmdKey | shiftKey)))")
          hk.unregisterAll()
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
          self.panelController.hide()
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("DOCKET_AFTER_HIDE active=\(NSApp.isActive) frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-") visible=\(self.panelController.panel.isVisible) frame=\(self.panelController.panel.frame)")
            exit(0)
          }
          }
        }
      }
      return
    }

    // Harness runs (screenshots / self-tests) need the view on screen to render.
    if harness != nil {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        self.panelController.showForHarness()
      }
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Clicking the app in Finder/Spotlight while it is already running opens the panel.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    panelController.show(reason: "toggle")
    return false
  }
}

/// Logs clicks reaching Flutter's controller during the activation harness.
final class TracingFlutterViewController: FlutterViewController {
  static let tracing = ProcessInfo.processInfo.environment["DOCKET_HARNESS"] == "activation"

  override func mouseDown(with event: NSEvent) {
    if Self.tracing { print("DOCKET_CONTROLLER mouseDown at \(event.locationInWindow)") }
    super.mouseDown(with: event)
  }

  override func mouseUp(with event: NSEvent) {
    if Self.tracing { print("DOCKET_CONTROLLER mouseUp") }
    super.mouseUp(with: event)
  }
}
