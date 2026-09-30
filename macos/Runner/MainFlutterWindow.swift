import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var brandingTimer: Timer?
  private func updateBranding() {
    let gold = Calendar.current.component(.weekday, from: Date()) == 7
    let name = gold ? "icon_gold_blue" : "icon_silver_blue"
    let path = Bundle.main.bundlePath + "/Contents/Frameworks/App.framework/Resources/flutter_assets/assets/branding/\(name).png"
    if let icon = NSImage(contentsOfFile: path) { NSApp.applicationIconImage = icon }
  }
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    updateBranding()
    brandingTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.updateBranding() }

    super.awakeFromNib()
  }
}
