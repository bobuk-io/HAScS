import SwiftUI
import HAScSCore

struct SettingsView: View {
    let repository: ConfigurationRepository
    let onSaved: () -> Void
    let onCancel: () -> Void

    @State private var address = ""
    @State private var newToken = ""
    @State private var hasSavedToken = false
    @State private var message: String?
    @State private var isSaving = false
    @State private var language = InterfaceLanguage.selected()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "house.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.tint)
                    .frame(width: 46, height: 46)
                    .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Home Assistant").font(.title3.weight(.semibold))
                    Text("Connection to your home", bundle: L10n.bundle).font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 24)

            Form {
                TextField(text: $address, prompt: Text(verbatim: "https://homeassistant.local:8123")) {
                    Text("Server URL", bundle: L10n.bundle)
                }
                .textContentType(.URL)
                SecureField(text: $newToken, prompt: tokenPrompt) {
                    Text("Access token", bundle: L10n.bundle)
                }
                .textContentType(.password)
                if hasSavedToken {
                    Text("Leave this field empty to keep the current token.", bundle: L10n.bundle)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker(selection: $language) {
                    ForEach(InterfaceLanguage.allCases) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                } label: {
                    Text("Language", bundle: L10n.bundle)
                }
                Text("Language changes take effect after restarting HAScS.", bundle: L10n.bundle)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: hasSavedToken ? 245 : 215)

            Label {
                Text("The URL and token are stored in macOS Keychain, not inside the app.", bundle: L10n.bundle)
            } icon: {
                Image(systemName: "lock.shield")
            }
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.top, 4)

            if let message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }
            Spacer(minLength: 20)
            Divider()
            HStack {
                Spacer()
                Button(action: onCancel) { Text("Cancel", bundle: L10n.bundle) }.keyboardShortcut(.cancelAction)
                Button(action: save) { Text("Save", bundle: L10n.bundle) }.keyboardShortcut(.defaultAction).disabled(isSaving)
            }
            .padding(.top, 16)
        }
        .padding(24)
        .frame(width: 540, height: 485)
        .onAppear(perform: load)
        .onDisappear { newToken = "" }
    }

    private var tokenPrompt: Text {
        if hasSavedToken {
            Text("Saved in Keychain", bundle: L10n.bundle)
        } else {
            Text("Long-lived access token", bundle: L10n.bundle)
        }
    }

    private func load() {
        newToken = ""
        message = nil
        do {
            let config = try repository.load()
            address = config.baseURL.absoluteString
            hasSavedToken = true
        } catch ConfigurationError.notFound {
            hasSavedToken = false
        } catch {
            hasSavedToken = false
            message = error.localizedDescription
        }
    }

    private func save() {
        isSaving = true
        defer { isSaving = false }
        do {
            let addressString = address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: addressString) else { throw ConfigurationError.invalidURL }
            let token: String
            if newToken.isEmpty && hasSavedToken {
                token = try repository.load().token
            } else {
                token = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let configuration = try Configuration(baseURL: url, token: token)
            try repository.save(configuration)
            language.save()
            newToken = ""
            message = nil
            onSaved()
        } catch {
            message = error.localizedDescription
        }
    }
}
