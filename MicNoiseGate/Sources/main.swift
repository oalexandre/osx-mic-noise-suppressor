import AppKit
import SwiftUI

// Create and configure the application
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Hide from Dock, show only in menu bar
app.setActivationPolicy(.accessory)

// Run the app
app.run()
