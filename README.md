# PodTrackio

PodTrackio is a native macOS learning companion for educational video and
podcast sessions. It helps people build a deliberate watching habit with a
library, progress goals, focused playback, local notifications, and optional
AI-generated study summaries.

## What is included

- Native SwiftUI app for macOS 26 and later
- YouTube metadata, captions, and playback support
- Local library, categories, learning activity, goals, and notifications
- Optional Groq-powered transcript summaries; keys stay in macOS Keychain
- Supabase schema and migrations for an optional account-backed sync layer

## Run it

1. Install Xcode Beta with the macOS 26 SDK.
2. Clone this repository and open it in Terminal.
3. Run `./script/build_and_run.sh`.

The script builds a local `dist/PodTrackio.app`, ad-hoc signs it, and launches
it. Run `./script/build_and_run.sh --verify` to check the generated bundle.

## Configuration and privacy

The app stores local learning data under `~/Library/Application Support/PodcastTracker/`.
Groq API keys are entered by the user in Settings and saved only in that user's
macOS Keychain. Do not add keys to source files, plist files, commit messages,
or issues.

The optional Supabase integration uses a client-side anon/publishable key. It
is not a service-role secret; production deployments must enable Row Level
Security and keep all privileged credentials outside the client.

## Contributing

Open an issue with a clear reproduction before a large change. Keep pull
requests focused, do not commit generated build output, and run the test suite
or the applicable build verification before submitting.

## License

Released under the [MIT License](LICENSE). You may use, modify, distribute,
and sell derivative work, subject to the license notice and warranty disclaimer.
