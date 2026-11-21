import Cocoa
import FlutterMacOS

/// Borderless panel that can take keyboard focus (borderless windows can't by default).
final class DocketPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  /// ⌘W closes the panel even though the app has no visible menu bar.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
      (delegate as? PanelController)?.hide()
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
}

/// The curtain's frosted glass. Purely visual: it must never take part in
/// mouse handling, or AppKit swallows clicks meant for the Flutter view above it.
final class GlassView: NSVisualEffectView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override var mouseDownCanMoveWindow: Bool { false }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }
}

/// Hosts the Flutter view. In curtain mode a native frosted-glass
/// NSVisualEffectView sits behind the (transparent) Flutter content.
final class PanelContainerViewController: NSViewController {
  let content: NSViewController
  let glass = GlassView()

  init(content: NSViewController) {
    self.content = content
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func loadView() {
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 620))
    container.wantsLayer = true
    container.layer?.masksToBounds = true
    view = container

    glass.frame = container.bounds
    glass.autoresizingMask = [.width, .height]
    glass.blendingMode = .behindWindow
    glass.material = .hudWindow
    glass.state = .active
    glass.isHidden = true
    container.addSubview(glass)

    addChild(content)
    content.view.frame = container.bounds
    content.view.autoresizingMask = [.width, .height]
    container.addSubview(content.view)
  }

  /// Rounded on all corners (drop-down) or only at the bottom (curtain).
  func applyShape(radius: CGFloat, bottomOnly: Bool) {
    guard let layer = view.layer else { return }
    layer.cornerRadius = radius
    // AppKit layers are not flipped: MinY is the bottom edge.
    layer.maskedCorners = bottomOnly
      ? [.layerMinXMinYCorner, .layerMaxXMinYCorner]
      : [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    // Behind-window blur doesn't always honour the parent's mask; give it its own.
    glass.maskImage = Self.maskImage(radius: radius, bottomOnly: bottomOnly)
  }

  private static func maskImage(radius: CGFloat, bottomOnly: Bool) -> NSImage {
    let edge = radius * 2 + 1
    let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
      let path = NSBezierPath()
      if bottomOnly {
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX, y: rect.minY + radius))
        path.appendArc(
          withCenter: NSPoint(x: rect.minX + radius, y: rect.minY + radius),
          radius: radius, startAngle: 180, endAngle: 270)
        path.line(to: NSPoint(x: rect.maxX - radius, y: rect.minY))
        path.appendArc(
          withCenter: NSPoint(x: rect.maxX - radius, y: rect.minY + radius),
          radius: radius, startAngle: 270, endAngle: 360)
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.close()
      } else {
        path.appendRoundedRect(rect, xRadius: radius, yRadius: radius)
      }
      NSColor.black.setFill()
      path.fill()
      return true
    }
    image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
    image.resizingMode = .stretch
    return image
  }
}

/// Owns the status item and the panel: drop-down or curtain placement,
/// show/hide animations, click-outside dismissal and the right-click menu.
final class PanelController: NSObject, NSWindowDelegate {
  enum Mode: String { case dropdown, curtain }

  let panel: DocketPanel
  let statusItem: NSStatusItem
  private let flutterViewController: FlutterViewController
  private let container: PanelContainerViewController
  private var clickMonitor: Any?
  private var hideGeneration = 0
  /// Keeps App Nap from throttling rendering and animations while visible.
  private var visibleActivity: NSObjectProtocol?

  private(set) var isShown = false
  /// Set while a native modal (save/open panel) is up so losing key status doesn't dismiss us.
  var suppressAutoHide = false

  // Display configuration (sent from Dart).
  private(set) var mode: Mode = .dropdown
  var size = NSSize(width: 400, height: 640)
  var curtainHeight: CGFloat = 0.78
  var curtainAnimated = true

  var onShow: ((String) -> Void)?
  var onHide: (() -> Void)?
  var onMenuAction: ((String) -> Void)?

  /// Menu titles in the interface language, sent from Dart.
  var labels: [String: String] = [:]

  /// Display strings for the right-click menu, kept in sync with the user's shortcuts.
  var toggleShortcutLabel = ""
  var quickAddShortcutLabel = ""

  init(content: FlutterViewController) {
    flutterViewController = content
    container = PanelContainerViewController(content: content)
    panel = DocketPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .fullSizeContentView],
      backing: .buffered,
      defer: false)
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    super.init()

    panel.isOpaque = false
    panel.backgroundColor = .clear
    // A transparent window is click-through by default: macOS sends clicks on
    // "see-through" pixels (the Metal-drawn Flutter content, the glass) to the
    // app behind. Claim every click inside the frame explicitly.
    panel.ignoresMouseEvents = false
    panel.hasShadow = true
    // isFloatingPanel resets the level to .floating, so set the level after it.
    panel.isFloatingPanel = true
    panel.level = .statusBar
    panel.hidesOnDeactivate = false
    panel.isMovable = false
    panel.isMovableByWindowBackground = false
    panel.isReleasedWhenClosed = false
    panel.animationBehavior = .none
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    panel.contentViewController = container
    panel.setContentSize(size)
    panel.delegate = self
    container.applyShape(radius: 12, bottomOnly: false)

    statusItem.autosaveName = "DocketStatusItem"
    if let button = statusItem.button {
      let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
      let image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Docket")?
        .withSymbolConfiguration(config)
      image?.isTemplate = true
      button.image = image
      button.imagePosition = .imageLeading
      button.target = self
      button.action = #selector(statusItemClicked(_:))
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
      button.toolTip = "Docket"
    }

    // Resolution changes, displays plugged in or out.
    NotificationCenter.default.addObserver(
      self, selector: #selector(screensChanged),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)
  }

  @objc private func screensChanged() {
    if isShown { panel.setFrame(targetFrame(), display: true) }
  }

  // MARK: Status item

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    let event = NSApp.currentEvent
    let isRightClick = event?.type == .rightMouseUp
      || (event?.modifierFlags.contains(.control) ?? false)
    if isRightClick {
      showStatusMenu()
    } else {
      toggle(reason: "toggle")
    }
  }

  private func showStatusMenu() {
    hide(animated: false, reason: "status menu")
    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.addItem(menuItem(labels["open"] ?? "Open Docket", action: "open", hint: toggleShortcutLabel))
    menu.addItem(menuItem(labels["quickAdd"] ?? "Quick Add…", action: "quickAdd", hint: quickAddShortcutLabel))
    menu.addItem(.separator())
    menu.addItem(menuItem(labels["settings"] ?? "Settings…", action: "settings", hint: ""))
    menu.addItem(.separator())
    let quit = NSMenuItem(
      title: labels["quit"] ?? "Quit Docket", action: #selector(quitApp), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)
    statusItem.menu = menu
    statusItem.button?.performClick(nil)
    statusItem.menu = nil
  }

  private func menuItem(_ title: String, action: String, hint: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: #selector(menuItemChosen(_:)), keyEquivalent: "")
    item.target = self
    item.representedObject = action
    if !hint.isEmpty {
      item.toolTip = hint
      let attributed = NSMutableAttributedString(string: title)
      attributed.append(NSAttributedString(
        string: "   \(hint)",
        attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
      item.attributedTitle = attributed
    }
    return item
  }

  @objc private func menuItemChosen(_ sender: NSMenuItem) {
    guard let action = sender.representedObject as? String else { return }
    switch action {
    case "open": show(reason: "toggle")
    case "quickAdd": show(reason: "quickAdd")
    case "settings": show(reason: "settings")
    default: onMenuAction?(action)
    }
  }

  @objc private func quitApp() {
    NSApp.terminate(nil)
  }

  func setBadge(_ text: String) {
    guard let button = statusItem.button else { return }
    if text.isEmpty {
      button.title = ""
      button.imagePosition = .imageOnly
    } else {
      button.imagePosition = .imageLeading
      button.attributedTitle = NSAttributedString(
        string: " \(text)",
        attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)])
    }
  }

  // MARK: Display mode

  /// Applies the display configuration; when the panel is open the change is live.
  func configure(
    mode newMode: Mode, size newSize: NSSize, curtainHeight height: CGFloat,
    animated: Bool, blur: CGFloat, tone: String
  ) {
    let modeChanged = newMode != mode
    mode = newMode
    size = newSize
    curtainHeight = min(max(height, 0.4), 1)
    curtainAnimated = animated

    let glass = container.glass
    glass.isHidden = mode != .curtain
    glass.alphaValue = min(max(blur, 0), 1)
    switch tone {
    case "light": glass.appearance = NSAppearance(named: .vibrantLight)
    case "dark": glass.appearance = NSAppearance(named: .vibrantDark)
    default: glass.appearance = nil
    }
    container.applyShape(radius: mode == .curtain ? 18 : 12, bottomOnly: mode == .curtain)

    guard isShown else {
      panel.setContentSize(mode == .curtain ? targetFrame().size : size)
      return
    }
    let frame = targetFrame()
    if modeChanged && curtainAnimated {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.3
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        panel.animator().setFrame(frame, display: true)
      }
    } else {
      panel.setFrame(frame, display: true)
    }
    panel.invalidateShadow()
  }

  /// Diagnostics only: take the glass view out of the hierarchy.
  func debugHideGlass() { container.glass.removeFromSuperview() }

  /// The screen under the pointer — where the user is working.
  private func targetScreen() -> NSScreen {
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
      ?? NSScreen.main ?? NSScreen.screens[0]
  }

  private func targetFrame() -> NSRect {
    mode == .curtain ? curtainFrame(on: targetScreen()) : dropdownFrame()
  }

  /// Full screen width, hanging from just below the menu bar.
  private func curtainFrame(on screen: NSScreen) -> NSRect {
    let visible = screen.visibleFrame
    let height = max(360, (visible.height * curtainHeight).rounded())
    return NSRect(
      x: screen.frame.minX, y: visible.maxY - height, width: screen.frame.width, height: height)
  }

  /// Same size, parked above the top edge of the screen: the start/end of the slide.
  private func curtainHiddenFrame(on screen: NSScreen) -> NSRect {
    var frame = curtainFrame(on: screen)
    frame.origin.y = screen.frame.maxY + 8
    return frame
  }

  /// Under the status item; on another display, at the same spot of that display's menu bar.
  private func dropdownFrame() -> NSRect {
    let screen = targetScreen()
    let visible = screen.visibleFrame
    let width = size.width
    let height = min(size.height, visible.height - 16)
    var x = visible.maxX - width - 12
    var top = visible.maxY - 6

    if let button = statusItem.button, let buttonWindow = button.window,
      let buttonScreen = buttonWindow.screen
    {
      let rect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
      if buttonScreen.frame.intersects(rect) {
        if buttonScreen == screen {
          x = rect.midX - width / 2
          top = rect.minY - 6
        } else {
          let fromRight = buttonScreen.frame.maxX - rect.midX
          x = screen.frame.maxX - fromRight - width / 2
        }
      }
    }
    x = min(max(x, visible.minX + 8), visible.maxX - width - 8)
    return NSRect(x: x, y: top - height, width: width, height: height)
  }

  // MARK: Show / hide

  private func beginVisibleActivity() {
    guard visibleActivity == nil else { return }
    visibleActivity = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiatedAllowingIdleSystemSleep], reason: "Docket panel is visible")
  }

  private func endVisibleActivity() {
    if let activity = visibleActivity {
      ProcessInfo.processInfo.endActivity(activity)
      visibleActivity = nil
    }
  }

  /// Renders the first Flutter frame off-screen so the first real open isn't blank.
  func prewarm() {
    panel.alphaValue = 0
    panel.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
    panel.orderFrontRegardless()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
      guard let self, !self.isShown else { return }
      self.panel.orderOut(nil)
    }
  }

  /// Harness runs: show without taking focus or reacting to clicks elsewhere.
  func showForHarness() {
    suppressAutoHide = true
    isShown = true
    beginVisibleActivity()
    panel.setFrame(targetFrame(), display: true)
    panel.alphaValue = 1
    panel.orderFrontRegardless()
    onShow?("harness")
  }

  func toggle(reason: String) {
    if isShown { hide() } else { show(reason: reason) }
  }

  func show(reason: String) {
    let wasShown = isShown
    hideGeneration += 1  // cancels a hide animation still running
    beginVisibleActivity()
    if NSApp.isHidden { NSApp.unhideWithoutActivation() }
    NSApp.activate(ignoringOtherApps: true)

    if mode == .curtain {
      let screen = targetScreen()
      let final = curtainFrame(on: screen)
      if !wasShown || !panel.isVisible {
        panel.alphaValue = 1
        panel.setFrame(curtainAnimated ? curtainHiddenFrame(on: screen) : final, display: false)
        if !curtainAnimated { panel.alphaValue = 0 }
      }
      panel.makeKeyAndOrderFront(nil)
      NSAnimationContext.runAnimationGroup { context in
        // A curtain drop: quick start, soft landing.
        context.duration = curtainAnimated ? 0.42 : 0.14
        context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        panel.animator().setFrame(final, display: true)
        panel.animator().alphaValue = 1
      }
    } else {
      panel.setFrame(dropdownFrame(), display: true)
      if !wasShown { panel.alphaValue = 0 }
      panel.makeKeyAndOrderFront(nil)
      if !wasShown {
        NSAnimationContext.runAnimationGroup { context in
          context.duration = 0.12
          panel.animator().alphaValue = 1
        }
      }
    }
    panel.makeFirstResponder(flutterViewController.view)
    isShown = true
    statusItem.button?.highlight(true)
    installClickMonitor()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
      self?.panel.invalidateShadow()
    }
    onShow?(reason)
  }

  func hide() { hide(animated: true) }

  /// Why the panel last closed — logged, so "it disappeared" can be diagnosed.
  private(set) var lastHideReason = ""

  func hide(animated: Bool, reason: String = "request") {
    guard isShown else { return }
    lastHideReason = reason
    NSLog("Docket: panel hidden (\(reason))")
    isShown = false
    statusItem.button?.highlight(false)
    removeClickMonitor()
    hideGeneration += 1
    let generation = hideGeneration

    let finish = { [weak self] in
      guard let self, self.hideGeneration == generation, !self.isShown else { return }
      self.panel.orderOut(nil)
      self.panel.alphaValue = 0
      self.endVisibleActivity()
    }
    if mode == .curtain && animated && curtainAnimated {
      let screen = panel.screen ?? targetScreen()
      NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.3
        context.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.75, 0)
        panel.animator().setFrame(curtainHiddenFrame(on: screen), display: true)
      }, completionHandler: finish)
    } else if mode == .curtain && animated {
      NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.14
        panel.animator().alphaValue = 0
      }, completionHandler: finish)
    } else {
      finish()
    }
    // Hand focus back to whatever app the user was in.
    if NSApp.isActive { NSApp.hide(nil) }
    onHide?()
  }

  /// Runs a native modal (save/open panel) without the panel dismissing itself.
  func runModal(_ body: (@escaping () -> Void) -> Void) {
    suppressAutoHide = true
    panel.level = .normal
    NSApp.activate(ignoringOtherApps: true)
    body { [weak self] in
      guard let self else { return }
      self.panel.level = .statusBar
      self.suppressAutoHide = false
      if self.isShown {
        self.panel.makeKeyAndOrderFront(nil)
        self.panel.makeFirstResponder(self.flutterViewController.view)
      }
    }
  }

  private func installClickMonitor() {
    guard clickMonitor == nil else { return }
    clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
      [weak self] _ in
      guard let self, !self.suppressAutoHide else { return }
      // Never treat a click inside our own frame as "outside".
      if self.panel.frame.contains(NSEvent.mouseLocation) { return }
      self.hide(animated: true, reason: "click outside")
    }
  }

  private func removeClickMonitor() {
    if let monitor = clickMonitor {
      NSEvent.removeMonitor(monitor)
      clickMonitor = nil
    }
  }

  // MARK: NSWindowDelegate

  func windowDidResignKey(_ notification: Notification) {
    guard isShown, !suppressAutoHide else { return }
    // A click on our own status item also resigns key; let its action toggle instead.
    DispatchQueue.main.async { [weak self] in
      guard let self, self.isShown, !self.suppressAutoHide, !self.panel.isKeyWindow else { return }
      if NSApp.isActive, NSApp.keyWindow == nil, NSApp.modalWindow == nil {
        // Still frontmost with nothing else key (e.g. a menu just closed): keep focus.
        self.panel.makeKeyAndOrderFront(nil)
        return
      }
      self.hide(animated: true, reason: "another app became active")
    }
  }
}
