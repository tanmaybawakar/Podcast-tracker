import SwiftUI

struct MainView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                authenticatedContent
            } else {
                LoginView()
            }
        }
        .onOpenURL { authManager.handleCallback(url: $0) }
        .applyingAppTheme()
    }

    private var authenticatedContent: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $viewModel.selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon).tag(section)
            }
            .navigationTitle("PodTrackio")
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                if viewModel.isTracking, let podcast = viewModel.selectedPodcast {
                    ActiveSessionView(podcast: podcast)
                        .environmentObject(viewModel)
                        .padding(10)
                }
            }
        } detail: {
            ZStack {
                ThemeBackdrop()
                Group {
                    if let podcast = viewModel.selectedPodcast {
                        PlayerView(podcast: podcast)
                    } else {
                        switch viewModel.selectedSection {
                        case .today: TodayView()
                        case .library: LibraryView()
                        case .progress: LearningProgressView()
                        }
                    }
                }
            }
            .navigationTitle(viewModel.selectedPodcast?.title ?? viewModel.selectedSection.rawValue)
            .toolbar {
                if viewModel.selectedPodcast != nil {
                    ToolbarItem {
                        Button("Back", systemImage: "chevron.backward") { viewModel.selectedPodcast = nil }
                            .help("Back to \(viewModel.selectedSection.rawValue)")
                    }
                    ToolbarSpacer(.fixed)
                }
                ToolbarItemGroup {
                    Button("Add Episode", systemImage: "plus") { viewModel.showAddPodcast = true }
                        .keyboardShortcut("n", modifiers: .command)
                    SettingsLink { Label("Settings", systemImage: "gearshape") }
                }
                if viewModel.selectedPodcast != nil {
                    ToolbarSpacer(.fixed)
                    ToolbarItem {
                        Button("Learning Inspector", systemImage: "sidebar.trailing") {
                            viewModel.inspectorPresented.toggle()
                        }
                    }
                }
            }
        }
        .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "Search episodes and categories")
        .sheet(isPresented: $viewModel.showAddPodcast) { AddPodcastSheet() }
        .sheet(isPresented: $viewModel.showRescueSheet) { DistractionRescueSheet() }
        .overlay(alignment: .top) { toastLayer }
        .onChange(of: viewModel.selectedSection) { _, _ in viewModel.selectedPodcast = nil }
    }

    @ViewBuilder private var toastLayer: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 8) {
                if viewModel.showLevelUpAlert {
                    Label("Level \(viewModel.stats.currentLevel.number) · \(viewModel.stats.currentLevel.title)", systemImage: viewModel.stats.currentLevel.iconName)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .glassEffect(.regular.tint(.accentColor), in: .capsule)
                        .task { try? await Task.sleep(for: .seconds(3)); viewModel.showLevelUpAlert = false }
                }
                if viewModel.showAchievementPopup, let achievement = viewModel.newlyUnlockedAchievement {
                    Label(achievement.title, systemImage: achievement.iconName)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .glassEffect(.regular, in: .capsule)
                        .task { try? await Task.sleep(for: .seconds(3)); viewModel.showAchievementPopup = false }
                }
            }.padding(.top, 8)
        }
    }
}

private struct ActiveSessionView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let podcast: Podcast
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Learning now").font(.caption).foregroundStyle(.secondary)
            Text(podcast.title).font(.callout.weight(.semibold)).lineLimit(2)
            HStack {
                Text(viewModel.currentSessionSeconds.formattedTime).monospacedDigit()
                Spacer()
                if let commitment = viewModel.activeCommitment {
                    Text("\(Int(ceil(commitment.remainingSeconds / 60))) min left")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                } else {
                    Label("Playing", systemImage: "waveform")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Active learning session, \(podcast.title), \(viewModel.currentSessionSeconds.formattedTime)")
    }
}
