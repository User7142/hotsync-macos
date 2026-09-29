import SwiftUI

struct SetupView: View {
    @Environment(AppState.self) var appState

    @State private var showNameEntry = false
    @State private var username: String = NSFullUserName()
    @FocusState private var isUsernameFocused: Bool

    private var isValid: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if showNameEntry {
                nameEntryView
            } else {
                welcomeView
            }

            Spacer()

            // Zurück-Button
            HStack {
                if showNameEntry {
                    Button(L10n.back) {
                        withAnimation { showNameEntry = false }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
        .frame(minWidth: 480, minHeight: 400)
    }

    // MARK: - Willkommen

    private var welcomeView: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text(L10n.welcomeTitle)
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(L10n.welcomeSubtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: {
                withAnimation { showNameEntry = true }
            }) {
                Text(L10n.setupDevice)
                    .frame(minWidth: 160)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Name eingeben

    private var nameEntryView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text(L10n.setupDevice)
                .font(.title2)
                .fontWeight(.semibold)

            Text(L10n.setupNameHint)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.deviceNameLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(L10n.deviceNamePlaceholder, text: $username)
                    .textFieldStyle(.roundedBorder)
                    .focused($isUsernameFocused)
                    .onSubmit { createProfile() }
            }
            .frame(width: 280)

            Button(action: createProfile) {
                Text(L10n.done)
                    .frame(minWidth: 160)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(!isValid)
            .padding(.top, 8)
        }
        .padding(.horizontal, 40)
        .onAppear { isUsernameFocused = true }
    }

    // MARK: - Action

    private func createProfile() {
        let name = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let userId = UInt.random(in: 10000...99999)
        appState.deviceManager.addProfile(
            username: name,
            userId: userId,
            deviceNote: nil
        )
        appState.setupCompleted()
    }
}
