import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // اعمال رنگ پایه OLED Dark (#0B0F19)
    let oledDarkColor = NSColor(
      calibratedRed: 11.0 / 255.0,
      green: 15.0 / 255.0,
      blue: 25.0 / 255.0,
      alpha: 1.0
    )
    self.backgroundColor = oledDarkColor
    flutterViewController.backgroundColor = oledDarkColor

    // ادغام پنجره با CustomDesktopTitleBar در فلاتر
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = false
    self.standardWindowButton(.closeButton)?.isHidden = true
    self.standardWindowButton(.miniaturizeButton)?.isHidden = true
    self.standardWindowButton(.zoomButton)?.isHidden = true

    // تنظیم ابعاد استاندارد پنجره
    let targetSize = NSSize(width: 400, height: 800)
    self.minSize = NSSize(width: 360, height: 700)
    self.setContentSize(targetSize)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    MacOSVpnBridge.shared.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}