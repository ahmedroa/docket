import Cocoa
import FlutterMacOS
import ServiceManagement
import UniformTypeIdentifiers

/// The single method channel between Dart and macOS.
///
/// Dart → native: panel, badge, hotkeys, notifications, login item, file panels.
/// Native → Dart: panelDidShow / panelDidHide / hotKey / notificationAction.
final class NativeBridge {
  private let channel: FlutterMethodChannel
  private let panel: PanelController
  private let reminders = Reminders()

  init(messenger: FlutterBinaryMessenger, panel: PanelController) {
    channel = FlutterMethodChannel(name: "docket/native", binaryMessenger: messenger)
    self.panel = panel

    panel.onShow = { [weak self] reason in
      self?.channel.invokeMethod("panelDidShow", arguments: ["reason": reason])
    }
    panel.onHide = { [weak self] in
      self?.channel.invokeMethod("panelDidHide", arguments: nil)
    }
    reminders.onAction = { [weak self] action, taskId in
      guard let self else { return }
      if action == "open" {
        self.panel.show(reason: "task:\(taskId)")
      } else {
        self.channel.invokeMethod("notificationAction", arguments: ["action": action, "taskId": taskId])
      }
    }
    HotKeyCenter.shared.onPressed = { [weak self] id in
      guard let self else { return }
      switch id {
      case HotKeyCenter.toggleId: self.panel.toggle(reason: "toggle")
      case HotKeyCenter.quickAddId:
        if self.panel.isShown {
          self.channel.invokeMethod("panelDidShow", arguments: ["reason": "quickAdd"])
        } else {
          self.panel.show(reason: "quickAdd")
        }
      default: break
      }
    }

    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {

    // MARK: Panel & status item
    case "showPanel":
      panel.show(reason: args["reason"] as? String ?? "toggle")
      result(nil)
    case "hidePanel":
      panel.hide()
      result(nil)
    case "setDisplayMode":
      // {mode: dropdown|curtain, width, height, curtainHeight, animated, blur, tone}
      func number(_ key: String, _ fallback: Double) -> CGFloat {
        CGFloat((args[key] as? NSNumber)?.doubleValue ?? fallback)
      }
      panel.configure(
        mode: PanelController.Mode(rawValue: args["mode"] as? String ?? "") ?? .dropdown,
        size: NSSize(width: number("width", 400), height: number("height", 640)),
        curtainHeight: number("curtainHeight", 0.78),
        animated: args["animated"] as? Bool ?? true,
        blur: number("blur", 0.85),
        tone: args["tone"] as? String ?? "auto")
      result(nil)
    case "setBadge":
      panel.setBadge(args["text"] as? String ?? "")
      result(nil)
    case "setLocalizedStrings":
      for (key, value) in args {
        if let text = value as? String { panel.labels[key] = text }
      }
      if let markDone = args["markDone"] as? String { reminders.setCompleteTitle(markDone) }
      result(nil)
    case "setShortcutLabels":
      panel.toggleShortcutLabel = args["toggle"] as? String ?? ""
      panel.quickAddShortcutLabel = args["quickAdd"] as? String ?? ""
      result(nil)

    // MARK: Global hotkeys
    case "registerHotKeys":
      // [{id, keyCode, modifiers}] → {id: "ok" | "taken" | "system" | "error"}
      let items = args["hotkeys"] as? [[String: Any]] ?? []
      var statuses: [String: String] = [:]
      HotKeyCenter.shared.unregisterAll()
      for item in items {
        guard let id = (item["id"] as? NSNumber)?.uint32Value,
          let keyCode = (item["keyCode"] as? NSNumber)?.uint32Value,
          let modifiers = (item["modifiers"] as? NSNumber)?.uint32Value
        else { continue }
        statuses[String(id)] = HotKeyCenter.shared.register(id: id, keyCode: keyCode, modifiers: modifiers)
      }
      result(statuses)
    case "checkHotKey":
      let keyCode = (args["keyCode"] as? NSNumber)?.uint32Value ?? 0
      let modifiers = (args["modifiers"] as? NSNumber)?.uint32Value ?? 0
      result(HotKeyCenter.systemConflict(keyCode: keyCode, modifiers: modifiers) ? "system" : "ok")
    case "suspendHotKeys":
      // While the user records a new shortcut, the old ones must not fire.
      HotKeyCenter.shared.unregisterAll()
      result(nil)

    // MARK: Notifications
    case "notificationStatus":
      reminders.status { result($0) }
    case "requestNotificationPermission":
      reminders.requestAuthorization { result($0) }
    case "scheduleNotifications":
      reminders.schedule(args["items"] as? [[String: Any]] ?? [])
      result(nil)
    case "openNotificationSettings":
      let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
      NSWorkspace.shared.open(url)
      result(nil)

    // MARK: Launch at login
    case "getLaunchAtLogin":
      result(launchAtLoginStatus())
    case "setLaunchAtLogin":
      let enabled = args["enabled"] as? Bool ?? false
      result(setLaunchAtLogin(enabled))

    // MARK: Files
    case "appSupportDirectory":
      result(appSupportDirectory().path)
    case "saveFile":
      let name = args["suggestedName"] as? String ?? "docket-backup.json"
      panel.runModal { done in
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = name
        savePanel.allowedContentTypes = [.json]
        savePanel.canCreateDirectories = true
        savePanel.level = .modalPanel
        savePanel.begin { response in
          result(response == .OK ? savePanel.url?.path : nil)
          done()
        }
      }
    case "openFile":
      panel.runModal { done in
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.level = .modalPanel
        openPanel.begin { response in
          result(response == .OK ? openPanel.url?.path : nil)
          done()
        }
      }
    case "revealInFinder":
      if let path = args["path"] as? String {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        panel.hide()
      }
      result(nil)

    // MARK: App
    case "appInfo":
      let info = Bundle.main.infoDictionary ?? [:]
      result([
        "version": info["CFBundleShortVersionString"] as? String ?? "",
        "build": info["CFBundleVersion"] as? String ?? "",
        "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
        "bundlePath": Bundle.main.bundlePath,
      ])
    case "quit":
      result(nil)
      DispatchQueue.main.async { NSApp.terminate(nil) }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func appSupportDirectory() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Docket", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func launchAtLoginStatus() -> String {
    guard #available(macOS 13.0, *) else { return "unsupported" }
    switch SMAppService.mainApp.status {
    case .enabled: return "enabled"
    case .requiresApproval: return "requiresApproval"
    case .notRegistered, .notFound: return "disabled"
    @unknown default: return "disabled"
    }
  }

  private func setLaunchAtLogin(_ enabled: Bool) -> String {
    guard #available(macOS 13.0, *) else { return "unsupported" }
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      NSLog("Docket: launch at login change failed: \(error.localizedDescription)")
    }
    return launchAtLoginStatus()
  }
}
