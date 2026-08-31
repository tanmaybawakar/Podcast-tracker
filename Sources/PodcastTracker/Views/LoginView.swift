import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authManager: AuthManager
    var body: some View {
        ZStack {
            Rectangle().fill(.background).ignoresSafeArea()
            VStack(spacing: 22) {
                Image(systemName: "headphones.circle.fill").font(.system(size: 58)).foregroundStyle(.tint)
                VStack(spacing: 7) {
                    Text("PodTrackio").font(.largeTitle.bold())
                    Text("A quiet place to turn podcasts into practiced knowledge.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                GlassEffectContainer(spacing: 10) {
                    VStack(spacing: 10) {
                        Button("Continue with Google", systemImage: "globe") { authManager.signInWithGoogle() }.buttonStyle(.glassProminent).controlSize(.large)
                        Button("Continue with Apple", systemImage: "applelogo") { authManager.signInWithApple() }.buttonStyle(.glass).controlSize(.large)
                    }
                }
                Label("Your learning data syncs privately to your account", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
            }
            .padding(36).frame(width: 410)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
        }
    }
}
