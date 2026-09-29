import SwiftUI

struct UsernameSheet: View {
    let suggestion: String?
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var username: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text(L10n.usernameSheetTitle)
                .font(.headline)

            Text(L10n.usernameSheetMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField(L10n.usernamePlaceholder, text: $username)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .frame(width: 260)
                .onSubmit { confirmIfValid() }

            HStack(spacing: 12) {
                Button(L10n.cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.usernameSheetSet) { confirmIfValid() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(30)
        .frame(width: 360)
        .onAppear {
            username = suggestion ?? ""
            isFocused = true
        }
    }

    private func confirmIfValid() {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onConfirm(trimmed)
    }
}
