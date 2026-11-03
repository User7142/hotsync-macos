import EventKit
import PalmSync
import PalmSyncMac
import SwiftUI

/// Der Kalender-Abgleich Mac → Palm eines Profils: ein- und ausschalten,
/// die Kalender wählen (je einer eine Kategorie auf dem Palm), das Fenster.
/// Was beim nächsten HotSync auf den Palm ginge, steht als Vorschau dabei.
struct CalendarSyncSection: View {
    @Environment(AppState.self) var appState
    let profileId: UUID

    @State private var calendars: [CalendarSource.Calendar] = []
    @State private var accessStatus: EKAuthorizationStatus = .notDetermined
    @State private var showCalendars = false

    private var settings: CalendarSyncSettings {
        appState.deviceManager.profile(profileId)?.calendarSync ?? CalendarSyncSettings()
    }

    private func update(_ change: (inout CalendarSyncSettings) -> Void) {
        var s = settings
        change(&s)
        appState.setCalendarSync(s, for: profileId)
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Toggle(isOn: Binding(get: { settings.enabled }, set: { on in update { $0.enabled = on } })) {
                        Text(L10n.calendarSyncToggle)
                    }
                    Spacer()
                    Button {
                        showCalendars.toggle()
                    } label: {
                        Label(L10n.calendarSyncChoose, systemImage: showCalendars ? "chevron.up" : "chevron.down")
                    }
                    .disabled(accessStatus != .fullAccess)
                }
                if settings.enabled {
                    let twoWay = appState.deviceManager.profile(profileId)?.isCalendarTwoWay ?? false
                    Text(twoWay ? L10n.twoWayHint : L10n.calendarSyncWarning)
                        .font(.caption)
                        .foregroundStyle(twoWay ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 16) {
                        Toggle(isOn: Binding(
                            get: { appState.deviceManager.profile(profileId)?.isCalendarTwoWay ?? false },
                            set: { appState.setCalendarTwoWay($0, for: profileId) }
                        )) {
                            Text(L10n.twoWayToggle)
                        }
                        if twoWay {
                            Picker(selection: Binding(get: { settings.conflicts }, set: { v in update { $0.conflictPolicy = v } })) {
                                ForEach(ConflictPolicy.allCases, id: \.self) { Text(L10n.conflictPolicyName($0)).tag($0) }
                            } label: {
                                Text(L10n.conflictPolicyLabel)
                            }
                            .pickerStyle(.menu)
                            .fixedSize()
                            .help(L10n.conflictPolicyHelp)
                        }
                    }
                    .font(.caption)
                }

                switch accessStatus {
                case .fullAccess:
                    if showCalendars { calendarList }
                    summary
                case .denied, .restricted, .writeOnly:
                    Text(L10n.calendarSyncDenied)
                        .font(.caption)
                        .foregroundStyle(.red)
                default:
                    Button(L10n.calendarSyncAllow) { requestAccess() }
                }
            }
            .padding(4)
        } label: {
            Label(appState.deviceManager.profile(profileId)?.isCalendarTwoWay == true ? L10n.calendarSyncTitleTwoWay : L10n.calendarSyncTitle, systemImage: "calendar")
        }
        .onAppear {
            refreshAccess()
            if appState.calendarPreview(for: profileId) == nil { appState.refreshCalendarPreview(for: profileId) }
        }
    }

    private var calendarList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(calendars) { cal in
                HStack {
                    Toggle(isOn: Binding(
                        get: { settings.calendars.contains { $0.id == cal.id } },
                        set: { on in
                            update { s in
                                s.calendars.removeAll { $0.id == cal.id }
                                if on { s.calendars.append(.init(id: cal.id, title: cal.title)) }
                            }
                        }
                    )) {
                        Text(cal.title)
                        Text(cal.source + (cal.isSubscribed ? " · " + L10n.calendarSubscribed : ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let choice = settings.calendars.first(where: { $0.id == cal.id }) {
                        TextField(L10n.calendarSyncCategory, text: Binding(
                            get: { choice.category ?? "" },
                            set: { text in
                                update { s in
                                    if let i = s.calendars.firstIndex(where: { $0.id == cal.id }) {
                                        s.calendars[i].category = text.isEmpty ? nil : String(text.prefix(15))
                                    }
                                }
                            }
                        ), prompt: Text(cal.title))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                        .help(L10n.calendarSyncCategoryHelp)
                    }
                }
            }
            HStack {
                Text(L10n.calendarSyncWindowLabel)
                Stepper(value: Binding(get: { settings.daysBack }, set: { v in update { $0.daysBack = v } }), in: 0...3650, step: 30) {
                    Text(L10n.calendarSyncDays(settings.daysBack, back: true))
                }
                Stepper(value: Binding(get: { settings.daysAhead }, set: { v in update { $0.daysAhead = v } }), in: 30...3650, step: 30) {
                    Text(L10n.calendarSyncDays(settings.daysAhead, back: false))
                }
            }
            .font(.caption)
        }
    }

    private var summary: some View {
        HStack {
            if settings.calendars.isEmpty {
                Text(L10n.calendarSyncNoCalendars)
            } else {
                Text(settings.calendars.map { $0.category ?? $0.title }.joined(separator: ", "))
                if let preview = appState.calendarPreview(for: profileId) {
                    Text("· " + preview)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func refreshAccess() {
        accessStatus = appState.calendarSource.accessStatus
        if accessStatus == .fullAccess {
            calendars = appState.calendarSource.calendars()
            // Kalender, die es nicht mehr gibt, bleiben in den Einstellungen,
            // bis sie abgewählt werden; die Liste zeigt sie mit
            for choice in settings.calendars where !calendars.contains(where: { $0.id == choice.id }) {
                calendars.append(.init(id: choice.id, title: choice.title, source: L10n.calendarGone, isSubscribed: false, isReadOnly: true))
            }
        }
    }

    private func requestAccess() {
        Task {
            _ = try? await appState.calendarSource.requestAccess()
            refreshAccess()
            appState.refreshCalendarPreview(for: profileId)
        }
    }
}
