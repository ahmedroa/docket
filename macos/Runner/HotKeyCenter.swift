import Carbon.HIToolbox
import Cocoa

/// System-wide shortcuts through Carbon's RegisterEventHotKey.
/// No Accessibility permission is needed, and registration is exclusive,
/// so a combination another app already owns is reported instead of silently shadowed.
final class HotKeyCenter {
  static let shared = HotKeyCenter()
  static let toggleId: UInt32 = 1
  static let quickAddId: UInt32 = 2

  var onPressed: ((UInt32) -> Void)?

  private var refs: [UInt32: EventHotKeyRef] = [:]
  private var handlerRef: EventHandlerRef?
  private let signature: OSType = 0x444B_5459  // 'DKTY'

  private init() {
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, _ -> OSStatus in
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
          event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
          nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
        if status == noErr {
          let id = hotKeyID.id
          DispatchQueue.main.async { HotKeyCenter.shared.onPressed?(id) }
        }
        return noErr
      }, 1, &spec, nil, &handlerRef)
  }

  /// Returns "ok", "system" (clashes with an enabled macOS shortcut),
  /// "taken" (another app holds it) or "error".
  func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> String {
    unregister(id: id)
    if HotKeyCenter.systemConflict(keyCode: keyCode, modifiers: modifiers) {
      return "system"
    }
    var ref: EventHotKeyRef?
    let hotKeyID = EventHotKeyID(signature: signature, id: id)
    let status = RegisterEventHotKey(
      keyCode, modifiers, hotKeyID, GetApplicationEventTarget(),
      OptionBits(kEventHotKeyExclusive), &ref)
    if status == noErr, let ref {
      refs[id] = ref
      return "ok"
    }
    return status == OSStatus(eventHotKeyExistsErr) ? "taken" : "error"
  }

  func unregister(id: UInt32) {
    if let ref = refs.removeValue(forKey: id) {
      UnregisterEventHotKey(ref)
    }
  }

  func unregisterAll() {
    for id in Array(refs.keys) { unregister(id: id) }
  }

  /// Checks the enabled shortcuts in System Settings › Keyboard › Keyboard Shortcuts
  /// (Spotlight, input sources, screenshots, Mission Control…).
  static func systemConflict(keyCode: UInt32, modifiers: UInt32) -> Bool {
    var unmanaged: Unmanaged<CFArray>?
    guard CopySymbolicHotKeys(&unmanaged) == noErr,
      let hotkeys = unmanaged?.takeRetainedValue() as? [[String: Any]]
    else { return false }
    let mask = UInt32(cmdKey | shiftKey | optionKey | controlKey)
    for hotkey in hotkeys {
      guard (hotkey[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
        let code = (hotkey[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint32Value,
        let mods = (hotkey[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value
      else { continue }
      if code == keyCode && (mods & mask) == (modifiers & mask) {
        return true
      }
    }
    return false
  }
}
