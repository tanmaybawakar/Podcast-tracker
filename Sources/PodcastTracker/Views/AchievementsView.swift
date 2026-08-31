import SwiftUI

struct AchievementsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Achievements").font(.title2.bold())
            Text("Earned through consistent learning—not repeatable taps.").foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                ForEach(viewModel.achievements) { achievement in
                    HStack(spacing: 12) {
                        Image(systemName: achievement.iconName).font(.title2)
                            .foregroundStyle(achievement.isUnlocked ? Color.accentColor : Color.secondary)
                            .frame(width: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(achievement.title).font(.headline)
                            Text(achievement.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        if achievement.isUnlocked { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) }
                    }.padding(14).background(.quaternary.opacity(achievement.isUnlocked ? 0.35 : 0.18), in: .rect(cornerRadius: 14))
                }
            }
        }
    }
}
