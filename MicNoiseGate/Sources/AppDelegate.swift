import AppKit
import SwiftUI
import CoreAudio

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var audioManager = AudioManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Mic Noise Gate")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create the popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 480)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ContentView(audioManager: audioManager))
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

struct ContentView: View {
    @ObservedObject var audioManager: AudioManager
    @State private var showUninstallConfirm = false

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "mic.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("Mic Noise Gate")
                    .font(.headline)
                Spacer()
            }

            Divider()

            // Noise Suppression Toggle
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Noise Suppression")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    HStack(spacing: 8) {
                        Text(audioManager.isNoiseSuppressionEnabled ? "Active" : "Disabled")
                            .font(.caption)
                            .foregroundColor(audioManager.isNoiseSuppressionEnabled ? .green : .secondary)
                        if audioManager.isVirtualMicActive {
                            Text("Virtual Mic")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                    }
                }

                Spacer()

                Toggle("", isOn: $audioManager.isNoiseSuppressionEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(audioManager.isNoiseSuppressionEnabled ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
            )

            // Input Device Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Input Device")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if audioManager.inputDevices.isEmpty {
                    Text("No input devices found")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    Picker("", selection: $audioManager.selectedDeviceID) {
                        ForEach(audioManager.inputDevices) { device in
                            Text(device.name).tag(device.id as AudioDeviceID?)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }

            Divider()

            // Waveform Visualizers
            if audioManager.isNoiseSuppressionEnabled {
                VStack(spacing: 12) {
                    Text("Audio Visualization")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    WaveformView(
                        samples: audioManager.inputWaveform,
                        color: .orange,
                        label: "Input (Raw)",
                        level: audioManager.inputLevel
                    )

                    WaveformView(
                        samples: audioManager.outputWaveform,
                        color: .green,
                        label: "Output (Processed)",
                        level: audioManager.outputLevel
                    )

                    Divider()

                    // Level Meters
                    LevelMeterView(
                        inputLevel: audioManager.inputLevel,
                        outputLevel: audioManager.outputLevel
                    )
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Enable noise suppression to see audio visualization")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }

            Spacer()

            Divider()

            // Footer
            HStack {
                Text("v1.0")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: {
                    showUninstallConfirm = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Uninstall MicNoiseGate")

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 320, height: 480)
        .alert("Uninstall MicNoiseGate", isPresented: $showUninstallConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Uninstall", role: .destructive) {
                uninstallApp()
            }
        } message: {
            Text("This will remove MicNoiseGate and its audio driver from your system. You'll need to enter your admin password.")
        }
    }

    private func uninstallApp() {
        // Create AppleScript to run uninstall with admin privileges
        let script = """
        do shell script "
        # Stop the app
        pkill -9 MicNoiseGate 2>/dev/null || true

        # Remove driver
        rm -rf '/Library/Audio/Plug-Ins/HAL/MicNoiseGate.driver'

        # Restart coreaudiod
        launchctl kickstart -kp system/com.apple.audio.coreaudiod

        # Remove app
        rm -rf '/Applications/MicNoiseGate.app'

        # Clean up receipts
        pkgutil --forget com.micnoisegate.app 2>/dev/null || true
        pkgutil --forget com.micnoisegate.driver 2>/dev/null || true
        " with administrator privileges
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if error == nil {
                // Show success and quit
                let alert = NSAlert()
                alert.messageText = "Uninstall Complete"
                alert.informativeText = "MicNoiseGate has been removed from your system."
                alert.alertStyle = .informational
                alert.runModal()
                NSApp.terminate(nil)
            }
        }
    }
}
