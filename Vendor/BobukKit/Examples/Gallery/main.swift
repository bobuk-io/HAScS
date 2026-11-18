import AppKit
import SwiftUI
import BobukUI

// Offline, invisible windows: no activation, live websites, key presses or user settings.
@MainActor func render(width: CGFloat, dark: Bool, output: URL) throws {
    let palette = PickerPalette(surface: dark ? NSColor(calibratedWhite: 0.12, alpha: 1) : NSColor(calibratedWhite: 0.96, alpha: 1),
        text: dark ? .white : .black, secondary: dark ? .lightGray : .darkGray,
        accent: dark ? NSColor.systemOrange : NSColor.systemBlue, border: .gray,
        badgeInk: dark ? .black : .white)
    let aliases = ["HA", "NOTES", "A-VERY-LONG-ALIAS"]
    let badgeWidth = PickerMetrics.badgeWidth(for: aliases)
    let content = VStack(alignment: .leading, spacing: 0) {
        Text("Alias or address").font(.system(size: 18)).padding(16)
        Divider()
        VStack(spacing: 0) {
            ForEach(Array(aliases.enumerated()), id: \.element) { index, alias in
                PickerRow(selected: index == 1, palette: palette) {
                    HStack(spacing: PickerMetrics.columnSpacing) {
                        PickerBadge(alias, width: badgeWidth, palette: palette)
                        Text(["Home Control", "Project Notes", "Long labels stay inside the row"][index])
                            .font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                }
            }
            PickerRow(selected: false, palette: palette) {
                HStack(spacing: PickerMetrics.columnSpacing) {
                    PickerBadge("↺", width: badgeWidth, palette: palette, emphasized: false)
                    Text("https://example.com/demo").font(.system(size: 13)).lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }.padding(.horizontal, 6).padding(.vertical, 4)
        Divider()
        ShortcutFooter([.init("↩", "open in this profile"), .init("⌘↩", "new window"),
                        .init("↑↓", "choose"), .init("⌘C", "copy URL"), .init("esc", "close")], palette: palette)
            .padding(16)
    }
    .foregroundStyle(Color(nsColor: palette.text))
    .padding(.top, PickerMetrics.accentHeight)
    .frame(width: width)
    .pickerPanel(palette: palette)
    let hosting = NSHostingView(rootView: content)
    let size = hosting.fittingSize
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless,
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.contentView = hosting
    hosting.setFrameSize(size)
    hosting.layoutSubtreeIfNeeded()
    guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw CocoaError(.fileWriteUnknown) }
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try data.write(to: output)
    window.close()
    print(output.path)
}

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/bobukkit-gallery", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try MainActor.assumeIsolated {
    _ = NSApplication.shared
    for dark in [false, true] {
        for width in [CGFloat(340), 560] {
            try render(width: width, dark: dark, output: output.appendingPathComponent("picker-\(dark ? "dark" : "light")-\(Int(width)).png"))
        }
    }
}
