import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController.init()
    self.contentViewController = flutterViewController

    // Set window to iPhone-like aspect ratio (iPhone 15 Pro Max: 430 x 932)
    let phoneWidth: CGFloat = 390
    let phoneHeight: CGFloat = 844
    let newFrame = NSRect(x: self.frame.origin.x, y: self.frame.origin.y,
                          width: phoneWidth, height: phoneHeight)
    self.setFrame(newFrame, display: true)
    self.minSize = NSSize(width: 320, height: 568)  // iPhone SE minimum
    self.maxSize = NSSize(width: 430, height: 932)  // iPhone Pro Max maximum

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
