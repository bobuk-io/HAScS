import AppKit
import SwiftUI

/// Native single-line search input. Apps own filtering/results; the kit owns input geometry.
/// No saved recents, automatic focus, key interception or search service.
@MainActor
public struct PickerSearchField: NSViewRepresentable {
    @Binding private var text: String
    private let placeholder: String
    private let accessibilityLabel: String
    private let palette: PickerPalette

    public init(text: Binding<String>, placeholder: String, accessibilityLabel: String, palette: PickerPalette) {
        _text = text
        self.placeholder = placeholder
        self.accessibilityLabel = accessibilityLabel
        self.palette = palette
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField(frame: .zero)
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.maximumRecents = 0
        field.recentsAutosaveName = nil
        field.searchMenuTemplate = nil
        field.font = .systemFont(ofSize: 13)
        field.controlSize = .regular
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        update(field)
        return field
    }

    public func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        update(field)
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSearchField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 200, height: PickerMetrics.searchFieldHeight)
    }

    private func update(_ field: NSSearchField) {
        if field.stringValue != text { field.stringValue = text }
        field.textColor = palette.text
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [.foregroundColor: palette.secondary])
        field.setAccessibilityLabel(accessibilityLabel)
    }

    @MainActor
    public final class Coordinator: NSObject, NSSearchFieldDelegate {
        fileprivate var parent: PickerSearchField
        fileprivate init(_ parent: PickerSearchField) { self.parent = parent }

        @objc public func searchChanged(_ sender: NSSearchField) {
            if parent.text != sender.stringValue { parent.text = sender.stringValue }
        }

        public func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            searchChanged(field)
        }
        // Leave editing commands, cancel and Cmd-W in AppKit's normal responder chain.
    }
}
