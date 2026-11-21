import Cocoa
import UserNotifications

/// Native macOS notifications. Dart computes the full schedule; this class
/// replaces the pending set each time so it never drifts from the data.
final class Reminders: NSObject, UNUserNotificationCenterDelegate {
  /// (action, taskId) — action is "open" or "complete".
  var onAction: ((String, String) -> Void)?

  private let center = UNUserNotificationCenter.current()
  private static let taskCategory = "docket.task"
  private static let completeAction = "docket.complete"

  override init() {
    super.init()
    center.delegate = self
    setCompleteTitle("Mark as Done")
  }

  /// (Re)registers the notification action so its button follows the interface language.
  func setCompleteTitle(_ title: String) {
    let complete = UNNotificationAction(
      identifier: Reminders.completeAction, title: title, options: [])
    let category = UNNotificationCategory(
      identifier: Reminders.taskCategory, actions: [complete], intentIdentifiers: [], options: [])
    center.setNotificationCategories([category])
  }

  func requestAuthorization(completion: @escaping (Bool) -> Void) {
    center.requestAuthorization(options: [.alert, .sound]) { granted, error in
      if let error { NSLog("Docket: notification authorization failed: \(error.localizedDescription)") }
      DispatchQueue.main.async { completion(granted) }
    }
  }

  func status(completion: @escaping (String) -> Void) {
    center.getNotificationSettings { settings in
      let value: String
      switch settings.authorizationStatus {
      case .authorized, .provisional: value = "authorized"
      case .denied: value = "denied"
      case .notDetermined: value = "notDetermined"
      @unknown default: value = "notDetermined"
      }
      DispatchQueue.main.async { completion(value) }
    }
  }

  /// items: [{id, title, body, at (ms since epoch), taskId?}]
  func schedule(_ items: [[String: Any]]) {
    center.removeAllPendingNotificationRequests()
    let now = Date()
    for item in items.prefix(60) {
      guard let id = item["id"] as? String,
        let title = item["title"] as? String,
        let atMs = (item["at"] as? NSNumber)?.doubleValue
      else { continue }
      let date = Date(timeIntervalSince1970: atMs / 1000)
      guard date > now else { continue }

      let content = UNMutableNotificationContent()
      content.title = title
      content.body = item["body"] as? String ?? ""
      content.sound = .default
      if let taskId = item["taskId"] as? String, !taskId.isEmpty {
        content.userInfo = ["taskId": taskId]
        content.categoryIdentifier = Reminders.taskCategory
        content.threadIdentifier = taskId
      } else {
        content.threadIdentifier = "docket.summary"
      }
      let components = Calendar.current.dateComponents(
        [.year, .month, .day, .hour, .minute, .second], from: date)
      let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
      center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) { error in
        if let error { NSLog("Docket: failed to schedule \(id): \(error.localizedDescription)") }
      }
    }
  }

  // Show banners even while the panel is open.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let taskId = response.notification.request.content.userInfo["taskId"] as? String ?? ""
    DispatchQueue.main.async {
      switch response.actionIdentifier {
      case Reminders.completeAction:
        if !taskId.isEmpty { self.onAction?("complete", taskId) }
      case UNNotificationDefaultActionIdentifier:
        self.onAction?("open", taskId)
      default:
        break
      }
      completionHandler()
    }
  }
}
