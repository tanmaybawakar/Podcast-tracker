import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    var body: some View {
        TabView {
            HabitSettingsView().tabItem { Label("Habits", systemImage: "target") }
            NotificationSettingsView().tabItem { Label("Notifications", systemImage: "bell") }
            AISettingsView().tabItem { Label("AI", systemImage: "sparkles") }
            CategorySettingsView().tabItem { Label("Categories", systemImage: "tag") }
            AccountSettingsView().tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .padding(18)
        .onDisappear { viewModel.saveData(); viewModel.rescheduleNotifications() }
    }
}

private struct HabitSettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @StateObject private var launchAtLogin = LaunchAtLoginController.shared
    var body: some View {
        Form {
            Section {
                Toggle("Adaptive Build-Up Mode", isOn: $viewModel.habitSettings.adaptiveBuildUpEnabled)
                LabeledContent("Current target") { Text("\(Int(viewModel.habitSettings.currentDailyGoalMinutes)) minutes") }
                Slider(value: $viewModel.habitSettings.currentDailyGoalMinutes, in: 5...180, step: 5)
                LabeledContent("Long-term target") { Text("\(Int(viewModel.habitSettings.targetDailyGoalMinutes)) minutes") }
                Slider(value: $viewModel.habitSettings.targetDailyGoalMinutes, in: max(5, viewModel.habitSettings.currentDailyGoalMinutes)...240, step: 5)
            } header: { Text("Daily learning") }
              footer: { Text("At the start of each local week, the daily target rises by five minutes only after at least five successful days in the previous seven. It never drops automatically.") }
            Section("Consistency") {
                LabeledContent("Minimum streak session") { Text("\(Int(viewModel.habitSettings.minimumQualifyingSessionMinutes)) minutes") }
                Stepper("Weekly goal: \(viewModel.stats.weeklyGoalHours.formatted()) hours", value: $viewModel.stats.weeklyGoalHours, in: 1...40, step: 0.5)
            }
            Section {
                Toggle("Keep Rescue ready after login", isOn: Binding(
                    get: { launchAtLogin.isRequested },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                LabeledContent("Login item", value: launchAtLogin.statusText)
                if launchAtLogin.status == .requiresApproval {
                    Button("Open Login Items Settings") { launchAtLogin.openLoginItemsSettings() }
                }
                if let message = launchAtLogin.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Fast access")
            } footer: {
                Text("Keeps the menu-bar Rescue available after you sign in to your Mac. PodTrackio remains a regular visible app, and macOS controls this permission.")
            }
        }.formStyle(.grouped)
            .onChange(of: viewModel.habitSettings.currentDailyGoalMinutes) { _, value in viewModel.setDailyGoal(value) }
            .onAppear { launchAtLogin.refresh() }
    }
}

private struct NotificationSettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @StateObject private var manager = NotificationManager.shared
    var body: some View {
        Form {
            Section("Delivery") {
                Toggle("Learning reminders", isOn: $viewModel.notificationPreferences.isEnabled)
                LabeledContent("Permission") { Text(statusText).foregroundStyle(manager.authorizationStatus == .authorized ? .green : .secondary) }
                if manager.authorizationStatus != .authorized {
                    Button("Allow Notifications") { Task { _ = await manager.requestAuthorization(); viewModel.rescheduleNotifications() } }
                }
            }
            Section("Daily cues") {
                Stepper("Morning · \(hour(viewModel.notificationPreferences.morning.hour))", value: $viewModel.notificationPreferences.morning.hour, in: 0...23)
                Stepper("Afternoon · \(hour(viewModel.notificationPreferences.afternoon.hour))", value: $viewModel.notificationPreferences.afternoon.hour, in: 0...23)
                Stepper("Evening · \(hour(viewModel.notificationPreferences.evening.hour))", value: $viewModel.notificationPreferences.evening.hour, in: 0...23)
            }
            Section("Adaptive rescue") {
                if let pattern = viewModel.learnedDistractionPattern {
                    LabeledContent("Learned window") {
                        Text("\(pattern.cue.title) · \(weekday(pattern.weekday)) at \(time(pattern.hour, pattern.minute))")
                    }
                    Text("Based on \(pattern.observations) similar Rescue attempts stored on this Mac. PodTrackio replaces a nearby generic reminder when possible.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("After three similar Rescue attempts on the same weekday and time window, PodTrackio can intervene ten minutes before that pattern—once per week, not every day.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Reminder days") {
                ForEach(Array(Calendar.current.weekdaySymbols.enumerated()), id: \.offset) { index, name in
                    Toggle(name, isOn: Binding(
                        get: { viewModel.notificationPreferences.enabledWeekdays.contains(index + 1) },
                        set: { enabled in
                            if enabled { viewModel.notificationPreferences.enabledWeekdays.insert(index + 1) }
                            else { viewModel.notificationPreferences.enabledWeekdays.remove(index + 1) }
                        }
                    ))
                }
            }
            Section("Quiet hours") {
                Toggle("Use quiet hours", isOn: $viewModel.notificationPreferences.quietHoursEnabled)
                Stepper("From \(hour(viewModel.notificationPreferences.quietHoursStart.hour))", value: $viewModel.notificationPreferences.quietHoursStart.hour, in: 0...23)
                Stepper("Until \(hour(viewModel.notificationPreferences.quietHoursEnd.hour))", value: $viewModel.notificationPreferences.quietHoursEnd.hour, in: 0...23)
            }
        }.formStyle(.grouped)
    }
    private var statusText: String {
        switch manager.authorizationStatus { case .authorized, .provisional, .ephemeral: "Allowed"; case .denied: "Denied in System Settings"; case .notDetermined: "Not requested"; @unknown default: "Unknown" }
    }
    private func hour(_ value: Int) -> String { DateComponents(calendar: .current, hour: value).date?.formatted(date: .omitted, time: .shortened) ?? "\(value):00" }
    private func weekday(_ value: Int) -> String {
        let names = Calendar.current.weekdaySymbols
        return names.indices.contains(value - 1) ? names[value - 1] : "Weekly"
    }
    private func time(_ hour: Int, _ minute: Int) -> String {
        DateComponents(calendar: .current, hour: hour, minute: minute).date?.formatted(date: .omitted, time: .shortened)
            ?? String(format: "%02d:%02d", hour, minute)
    }
}

private struct AISettingsView: View {
    @State private var key = ""
    @State private var hasStoredKey = KeychainStore.groqAPIKey() != nil
    @State private var status: String?
    @State private var isTesting = false

    var body: some View {
        Form {
            Section {
                SecureField(hasStoredKey ? "Stored in Keychain" : "gsk_…", text: $key)
                HStack {
                    Button("Save") {
                        do { try KeychainStore.saveGroqAPIKey(key); hasStoredKey = true; key = ""; status = "Saved securely in Keychain." }
                        catch { status = error.localizedDescription }
                    }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove", role: .destructive) {
                        do { try KeychainStore.removeGroqAPIKey(); hasStoredKey = false; status = "Key removed." }
                        catch { status = error.localizedDescription }
                    }.disabled(!hasStoredKey)
                    Button("Test Connection") { test() }.disabled(!hasStoredKey || isTesting)
                    if isTesting { ProgressView().controlSize(.small) }
                }
                if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            } header: { Text("Groq API key") }
              footer: { Text("The key is stored only in macOS Keychain. It is never written to app JSON or synced to Supabase.") }
            Section("Models") {
                LabeledContent("Summaries", value: "openai/gpt-oss-120b")
                LabeledContent("Transcription", value: "whisper-large-v3-turbo")
            }
        }.formStyle(.grouped)
    }

    private func test() {
        guard let stored = KeychainStore.groqAPIKey() else { return }
        isTesting = true; status = nil
        Task {
            do { try await GroqClient.shared.testConnection(apiKey: stored); status = "Connected to Groq." }
            catch { status = error.localizedDescription }
            isTesting = false
        }
    }
}

private struct CategorySettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var editor: CategoryDraft?
    @State private var deletion: LearningCategory?
    @State private var replacementID: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) { Text("Categories").font(.title2.bold()); Text("Names can change without breaking podcast references.").foregroundStyle(.secondary) }
                Spacer()
                Button("New Category", systemImage: "plus") { editor = .new(sortOrder: viewModel.categories.count) }.buttonStyle(.glassProminent)
            }
            List {
                ForEach(viewModel.categories) { category in
                    HStack {
                        Image(systemName: category.symbolName).foregroundStyle(category.color).frame(width: 26)
                        Text(category.name)
                        Spacer()
                        Text("\(viewModel.podcasts.filter { $0.categoryID == category.id }.count) episodes").foregroundStyle(.secondary)
                        Button("Edit", systemImage: "pencil") { editor = .init(category) }.labelStyle(.iconOnly).buttonStyle(.borderless)
                        Button("Delete", systemImage: "trash", role: .destructive) { deletion = category; replacementID = viewModel.categories.first(where: { $0.id != category.id })?.id }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).disabled(viewModel.categories.count == 1)
                    }.padding(.vertical, 5)
                }.onMove { viewModel.moveCategories(from: $0, to: $1) }
            }
            Text("Drag to reorder. The final remaining category cannot be deleted.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $editor) { CategoryEditorSheet(draft: $0) }
        .sheet(item: $deletion) { category in DeleteCategorySheet(category: category, replacementID: $replacementID, errorMessage: $errorMessage) }
    }
}

private struct CategoryDraft: Identifiable {
    var id: String; var name: String; var symbolName: String; var colorToken: String; var sortOrder: Int; var isNew: Bool
    init(_ category: LearningCategory) { id = category.id; name = category.name; symbolName = category.symbolName; colorToken = category.colorToken; sortOrder = category.sortOrder; isNew = false }
    static func new(sortOrder: Int) -> CategoryDraft { .init(id: UUID().uuidString.lowercased(), name: "", symbolName: "book.closed.fill", colorToken: "blue", sortOrder: sortOrder, isNew: true) }
    private init(id: String, name: String, symbolName: String, colorToken: String, sortOrder: Int, isNew: Bool) { self.id = id; self.name = name; self.symbolName = symbolName; self.colorToken = colorToken; self.sortOrder = sortOrder; self.isNew = isNew }
}

private struct CategoryEditorSheet: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State var draft: CategoryDraft
    @State private var errorMessage: String?
    private let symbols = ["book.closed.fill", "brain.head.profile", "cpu", "atom", "briefcase.fill", "chart.line.uptrend.xyaxis", "heart.fill", "globe", "function", "lightbulb.fill", "graduationcap.fill", "figure.mind.and.body"]
    private let colors = ["blue", "indigo", "purple", "pink", "red", "orange", "yellow", "green", "mint", "teal", "cyan", "brown", "gray"]
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $draft.name)
                Picker("Symbol", selection: $draft.symbolName) { ForEach(symbols, id: \.self) { Label($0, systemImage: $0).tag($0) } }
                Picker("Color", selection: $draft.colorToken) { ForEach(colors, id: \.self) { Text($0.capitalized).tag($0) } }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }.formStyle(.grouped).navigationTitle(draft.isNew ? "New Category" : "Edit Category")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.buttonStyle(.glassProminent) }
                }
        }.frame(width: 450, height: 310)
    }
    private func save() {
        do {
            if draft.isNew { try viewModel.createCategory(name: draft.name, symbolName: draft.symbolName, colorToken: draft.colorToken) }
            else { try viewModel.updateCategory(.init(id: draft.id, name: draft.name, symbolName: draft.symbolName, colorToken: draft.colorToken, sortOrder: draft.sortOrder)) }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct DeleteCategorySheet: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    let category: LearningCategory
    @Binding var replacementID: String?
    @Binding var errorMessage: String?
    private var count: Int { viewModel.podcasts.filter { $0.categoryID == category.id }.count }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Delete \(category.name)?").font(.title2.bold())
            if count > 0 {
                Text("\(count) episodes use this category. Choose where they should move before deletion.")
                Picker("Replacement", selection: $replacementID) {
                    ForEach(viewModel.categories.filter { $0.id != category.id }) { Text($0.name).tag(Optional($0.id)) }
                }
            } else { Text("This category is unused and can be deleted immediately.") }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Delete", role: .destructive) { remove() }.buttonStyle(.glassProminent).tint(.red) }
        }.padding(24).frame(width: 460)
    }
    private func remove() {
        do { try viewModel.deleteCategory(id: category.id, replacementID: count > 0 ? replacementID : nil); dismiss() }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct AccountSettingsView: View {
    @EnvironmentObject private var authManager: AuthManager
    var body: some View {
        Form {
            Section("Signed in") {
                LabeledContent("Name", value: authManager.displayName ?? "—")
                LabeledContent("Email", value: authManager.email ?? "—")
                Button("Sign Out", role: .destructive) { authManager.signOut() }
            }
            Section { Text("Raw transcripts and the Groq key stay on this Mac. Categories, daily activity, compact summaries, and action completion can sync through your account.") }
        }.formStyle(.grouped)
    }
}
