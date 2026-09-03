import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        ZStack {
            ThemeBackdrop()

            Circle()
                .fill(.cyan.opacity(0.16))
                .frame(width: 460, height: 460)
                .blur(radius: 85)
                .offset(x: -340, y: 250)
                .accessibilityHidden(true)

            HStack(spacing: 72) {
                brandPanel
                signInPanel
            }
            .padding(64)
            .frame(maxWidth: 1120)
        }
        .onAppear {
            DispatchQueue.main.async {
                NSApplication.shared.keyWindow?.title = "PodTrackio"
            }
        }
    }

    private var brandPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.18), radius: 24, y: 14)
                .accessibilityLabel("PodTrackio logo")

            VStack(alignment: .leading, spacing: 12) {
                Text("PodTrackio")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                Text("Turn podcasts into\nknowledge you keep.")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                benefit("Keep every episode and note in one focused library", icon: "books.vertical.fill")
                benefit("Pick up from the same moment across your Macs", icon: "arrow.triangle.2.circlepath")
                benefit("Sync privately through your PodTrackio account", icon: "lock.shield.fill")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var signInPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Welcome")
                    .font(.title.bold())
                Text("Sign in to continue to your learning workspace.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                SignInWithAppleButton(.continue) { request in
                    authManager.prepareAppleSignInRequest(request)
                } onCompletion: { result in
                    authManager.handleAppleSignIn(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .clipShape(.rect(cornerRadius: 10))
                .disabled(authManager.isSigningIn)

                Button {
                    authManager.signInWithGoogle()
                } label: {
                    Label("Continue with Google", systemImage: "globe")
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .tint(.white.opacity(0.16))
                .disabled(authManager.isSigningIn)
            }

            if authManager.isSigningIn {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Connecting securely…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            if let message = authManager.authErrorMessage, !message.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Dismiss", systemImage: "xmark") {
                        authManager.clearAuthError()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(.orange.opacity(0.10), in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.orange.opacity(0.24), lineWidth: 1)
                }
            }

            Label("Signing out never deletes your library from this Mac.", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
        .frame(width: 420)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private func benefit(_ title: String, icon: String) -> some View {
        Label {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 22)
        }
    }
}
