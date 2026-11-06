import SwiftUI
import HAScSCore

private enum RemoteStyle {
    static let featured = Color(red: 0.25, green: 0.30, blue: 0.25)
    static let featuredText = Color(red: 0.96, green: 0.96, blue: 0.92)
    static let accent = Color(red: 0.70, green: 0.36, blue: 0.22)
}

struct ScenePanelView: View {
    let store: SceneStore
    let activate: (Int) -> Void
    let close: () -> Void
    let refresh: () -> Void
    let settings: () -> Void
    @State private var dropTargetID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            title
            content
            footer
        }
        .frame(width: 622, height: 505)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.primary.opacity(0.10)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Home Assistant scene remote", bundle: L10n.bundle))
        .onChange(of: store.isReordering) { dropTargetID = nil }
    }

    private var header: some View {
        HStack {
            Image(systemName: "house")
                .foregroundStyle(RemoteStyle.accent)
                .accessibilityHidden(true)
            Text("HAScS").font(.system(.caption, design: .rounded, weight: .semibold))
            Spacer()
            Circle().fill(statusColor).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(statusLabel, bundle: L10n.bundle).font(.caption2).foregroundStyle(.secondary)
            if !store.isReordering && store.status == .ready && store.slots.count > 1 {
                Button(action: store.beginReordering) {
                    Label { Text("Reorder", bundle: L10n.bundle) } icon: { Image(systemName: "arrow.up.arrow.down") }
                }
                .disabled(store.isActivating || store.successName != nil)
                .help(Text("Reorder scenes", bundle: L10n.bundle))
                .accessibilityLabel(Text("Reorder scenes", bundle: L10n.bundle))
            }
            Button(action: settings) {
                Image(systemName: "gearshape").font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(Text("Home Assistant settings", bundle: L10n.bundle))
            .accessibilityLabel(Text("Home Assistant settings", bundle: L10n.bundle))
            .padding(.leading, 8)
        }
        .padding(.horizontal, 25)
        .padding(.top, 25)
    }

    private var title: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Home scenes", bundle: L10n.bundle).font(.system(size: 28, weight: .semibold)).tracking(-0.8)
                Text(store.isReordering ? "Drag tiles to reorder. Scenes will not run." : "Choose a scene or press a number", bundle: L10n.bundle)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if store.status == .ready {
                Text("\(store.totalScenes) scenes", bundle: L10n.bundle)
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.10)))
            }
        }
        .padding(.horizontal, 25)
        .padding(.top, 25)
        .padding(.bottom, 18)
    }

    @ViewBuilder private var content: some View {
        switch store.status {
        case .loading:
            VStack(spacing: 12) {
                ProgressView().controlSize(.regular)
                Text("Loading scenes…", bundle: L10n.bundle).font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            emptyState(symbol: "wifi.slash", title: "Cannot connect to your home", message: Text(message))
        case .ready:
            if store.slots.isEmpty {
                emptyState(symbol: "square.grid.2x2", title: "Your scenes will appear here",
                           message: Text("Create a scene in Home Assistant, then refresh the list.", bundle: L10n.bundle))
            } else {
                sceneGrid
            }
        }
    }

    private var sceneGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            // First tile spans two columns, like the chosen design. With more than
            // five scenes, the same compact grid scrolls without hiding any slot.
            ScrollViewReader { proxy in
                ScrollView {
                    Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                        let rows = SceneGridLayout.rows(for: store.slots)
                        ForEach(rows) { row in
                            GridRow {
                                ForEach(row.slots) { slot in
                                    sceneTile(slot, featured: row.featured && slot.id == store.slots.first?.id)
                                    .id(slot.id)
                                    .gridCellColumns(row.featured && slot.id == store.slots.first?.id ? 2 : 1)
                                }
                                if row.featured && row.slots.count == 1 { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                            }
                        }
                    }
                }
                .scrollIndicators(.automatic)
                .onChange(of: store.selectedNumber) {
                    if let id = store.slots.first(where: { $0.number == store.selectedNumber })?.id {
                        proxy.scrollTo(id, anchor: nil)
                    }
                }
            }
            if let message = store.activationError {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(message)
            } else if store.totalScenes > 9 {
                Text("Showing 9 of \(store.totalScenes) scenes. Only keys 1–9 are available.", bundle: L10n.bundle)
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 25)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if let success = store.successName {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 34)).foregroundStyle(.green)
                    Text(success).font(.title3.weight(.semibold))
                    Text("Activation request sent", bundle: L10n.bundle).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.regularMaterial)
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private func sceneTile(_ slot: SceneSlot, featured: Bool) -> some View {
        let tile = SceneTile(slot: slot, featured: featured,
                             selected: slot.number == store.selectedNumber,
                             busy: store.isActivating, editing: store.isReordering) {
            if store.isReordering { store.selectForReordering(slot.number) }
            else { activate(slot.number) }
        }
        if store.isReordering {
            tile
                .draggable(slot.id)
                .dropDestination(for: String.self) { ids, _ in
                    dropTargetID = nil
                    guard ids.count == 1, let id = ids.first,
                          let position = store.slots.firstIndex(where: { $0.id == slot.id }) else { return false }
                    return store.moveScene(id, toPosition: position)
                } isTargeted: { targeted in
                    if targeted { dropTargetID = slot.id }
                    else if dropTargetID == slot.id { dropTargetID = nil }
                }
                .overlay {
                    if dropTargetID == slot.id {
                        RoundedRectangle(cornerRadius: 11).strokeBorder(Color.accentColor, lineWidth: 3)
                            .allowsHitTesting(false)
                    }
                }
                .contextMenu {
                    Button {
                        if let index = store.slots.firstIndex(where: { $0.id == slot.id }) {
                            store.moveScene(slot.id, toPosition: index - 1)
                        }
                    } label: { Text("Move earlier", bundle: L10n.bundle) }
                    .disabled(slot.id == store.slots.first?.id)
                    Button {
                        if let index = store.slots.firstIndex(where: { $0.id == slot.id }) {
                            store.moveScene(slot.id, toPosition: index + 1)
                        }
                    } label: { Text("Move later", bundle: L10n.bundle) }
                    .disabled(slot.id == store.slots.last?.id)
                }
                .accessibilityAction(named: Text("Move earlier", bundle: L10n.bundle)) {
                    if let index = store.slots.firstIndex(where: { $0.id == slot.id }) {
                        store.moveScene(slot.id, toPosition: index - 1)
                    }
                }
                .accessibilityAction(named: Text("Move later", bundle: L10n.bundle)) {
                    if let index = store.slots.firstIndex(where: { $0.id == slot.id }) {
                        store.moveScene(slot.id, toPosition: index + 1)
                    }
                }
        } else {
            tile
        }
    }

    private func emptyState(symbol: String, title: LocalizedStringKey, message: Text) -> some View {
        VStack(spacing: 11) {
            Image(systemName: symbol).font(.system(size: 27)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(title, bundle: L10n.bundle).font(.headline)
            message.font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
            HStack {
                Button(action: refresh) { Text("Refresh", bundle: L10n.bundle) }
                Button(action: settings) { Text("Settings…", bundle: L10n.bundle) }
            }
            .padding(.top, 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                if store.isReordering {
                    Text("Shift + ←/→ move", bundle: L10n.bundle)
                    Spacer()
                    Button { store.finishReordering(save: false) } label: {
                        Text("Cancel", bundle: L10n.bundle)
                    }
                    Button { store.finishReordering(save: true) } label: {
                        Text("Done", bundle: L10n.bundle)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    if let last = store.lastSentName {
                        Text("Last request · \(last)", bundle: L10n.bundle).lineLimit(1)
                    } else {
                        Image(systemName: "keyboard").accessibilityHidden(true)
                        Text("1–9 run", bundle: L10n.bundle)
                    }
                    Spacer()
                    Text("↑↓ select   ↵ run", bundle: L10n.bundle)
                    Spacer()
                    Button(action: close) { Text("esc  close", bundle: L10n.bundle) }.buttonStyle(.plain)
                        .accessibilityLabel(Text("Close remote", bundle: L10n.bundle))
                }
            }
            .font(.caption2).foregroundStyle(.secondary)
            .padding(.horizontal, 25)
            .frame(height: 44)
        }
    }

    private var statusLabel: LocalizedStringKey {
        switch store.status {
        case .loading: "Connecting…"
        case .ready: "Home Assistant"
        case .error: "Not connected"
        }
    }
    private var statusColor: Color {
        switch store.status {
        case .loading: .secondary
        case .ready: .green
        case .error: .orange
        }
    }
}

private struct SceneTile: View {
    let slot: SceneSlot
    let featured: Bool
    let selected: Bool
    let busy: Bool
    let editing: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: symbol).font(.system(size: 22, weight: .regular)).accessibilityHidden(true)
                    Spacer()
                    if editing {
                        Image(systemName: "line.3.horizontal").font(.caption).accessibilityHidden(true)
                    }
                    Text("\(slot.number)").font(.caption2.monospacedDigit())
                        .frame(width: 23, height: 25)
                        .background(keyBackground, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(featured ? 0 : 0.12)))
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 16)
                Text(slot.scene.name).font(featured ? .title3 : .body).lineLimit(1).truncationMode(.tail)
                if !slot.scene.isAvailable { Text("Unavailable", bundle: L10n.bundle).font(.caption2).padding(.top, 3) }
            }
            .foregroundStyle(featured ? RemoteStyle.featuredText : Color.primary)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 120, alignment: .leading)
            .background(tileBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(selected ? (featured ? Color.white.opacity(0.45) : Color.accentColor.opacity(0.65)) : Color.primary.opacity(0.06), lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 11))
            .opacity(slot.scene.isAvailable ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled((!editing && !slot.scene.isAvailable) || busy)
        .onHover { hovering = $0 }
        .accessibilityLabel(accessibilityTitle)
        .accessibilityHint(Text(editing ? "Select to move with Shift and arrow keys" : "Run scene", bundle: L10n.bundle))
    }

    private var accessibilityTitle: Text {
        if slot.scene.isAvailable {
            Text("\(slot.scene.name), scene \(slot.number)", bundle: L10n.bundle)
        } else {
            Text("\(slot.scene.name), scene \(slot.number), unavailable", bundle: L10n.bundle)
        }
    }

    private var tileBackground: Color {
        if featured { return hovering ? RemoteStyle.featured.opacity(0.87) : RemoteStyle.featured }
        return Color.primary.opacity(hovering ? 0.09 : (colorScheme == .dark ? 0.07 : 0.035))
    }
    private var keyBackground: Color {
        if featured { return Color.white.opacity(0.15) }
        return Color(nsColor: .controlBackgroundColor)
    }
    private var symbol: String {
        switch slot.scene.attributes.icon {
        case "mdi:camera-account": "camera"
        case "mdi:sleep": "moon.zzz"
        case "mdi:candelabra": "flame"
        case "mdi:clock": "clock"
        case "mdi:lightbulb-night-outline": "lightbulb"
        case let icon? where icon.contains("light"): "lightbulb"
        case let icon? where icon.contains("movie"): "film"
        case let icon? where icon.contains("sleep") || icon.contains("night"): "moon.stars"
        default: "sparkles"
        }
    }
}
