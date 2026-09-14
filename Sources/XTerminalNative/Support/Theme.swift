import SwiftUI
import AppKit

enum Theme {
    static let accent = Color(red: 0.25, green: 0.76, blue: 0.52)
    static let canvas = Color(nsColor: NSColor(calibratedWhite: 0.055, alpha: 1))
    static let sidebar = Color(nsColor: NSColor(calibratedWhite: 0.075, alpha: 1))
    static let panel = Color(nsColor: NSColor(calibratedWhite: 0.095, alpha: 1))
    static let elevated = Color(nsColor: NSColor(calibratedWhite: 0.13, alpha: 1))
    static let line = Color.white.opacity(0.075)
    static let muted = Color.white.opacity(0.42)
    static let terminal = NSColor(red: 0.055, green: 0.06, blue: 0.09, alpha: 1)
}

struct ActionButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .foregroundStyle(primary ? Color.white : Color.primary.opacity(0.85))
            .padding(.horizontal, 12).frame(height: 28)
            .background(primary ? Theme.accent.opacity(configuration.isPressed ? 0.65 : 0.82) : Color.white.opacity(configuration.isPressed ? 0.12 : 0.035), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(primary ? Theme.accent.opacity(0.3) : Theme.line))
    }
}

struct IconButton: View {
    var symbol: String
    var help: String
    var active = false
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 13)).frame(width: 28, height: 27)
                .foregroundStyle(active ? Theme.accent : Color.secondary)
                .background(active ? Theme.accent.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 5)) }
            .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }
}

struct Badge: View {
    var text: String
    var color: Color = .secondary
    var body: some View {
        Text(text).font(.system(size: 10)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color.opacity(0.15)))
    }
}

func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
