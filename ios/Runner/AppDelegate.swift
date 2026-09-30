import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var brandingTimer: Timer?
  private func updateBranding() {
    guard UIApplication.shared.applicationState == .active,
          UIApplication.shared.supportsAlternateIcons else { return }
    let icon: String? = Calendar.current.component(.weekday, from: Date()) == 7 ? "GoldIcon" : nil
    if UIApplication.shared.alternateIconName != icon {
      UIApplication.shared.setAlternateIconName(icon)
    }
  }
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
        object: nil, queue: .main) { [weak self] _ in self?.updateBranding() }
    brandingTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.updateBranding() }
  }
}
