# PodTrackio

PodTrackio is a native macOS learning companion for educational YouTube videos
and podcasts. It keeps a focused library, gives you a proper player, turns
episodes into structured study notes, and helps you follow through on a real
learning habit instead of another passive watch list.

## Install

1. Download [PodTrackio.dmg](PodTrackio.dmg).
2. Open the disk image.
3. Drag **PodTrackio** to **Applications**.
4. Open it from Applications.

PodTrackio currently targets macOS 26 or later. The included app is ad-hoc
signed for local distribution; if macOS shows a Gatekeeper warning, open it
once from Finder with Control-click → **Open**. A Developer ID-notarized build
is required for a warning-free public release.

## What it does

- Builds a personal library from YouTube URLs and playlists.
- Plays video in-app, tracks watch progress, and supports local downloads.
- Organizes episodes into collections, categories, and scheduled learning time.
- Creates timestamped study briefs, key topics, takeaways, action plans, and
  follow-up chat from a transcript.
- Stores Groq and TranscriptAPI credentials in the macOS Keychain, not in app
  data or this repository.
- Keeps downloaded media local to the Mac; it is never synced through Supabase.

## AI summary setup

Add your Groq and TranscriptAPI keys in **Settings**. PodTrackio fetches a
timestamped transcript when possible and uses Groq to create the learning
brief. If a transcript is unavailable, you can import or paste one instead.

## Build from source

PodTrackio is a Swift Package that requires Xcode Beta with the macOS 26 SDK.

```bash
./script/build_and_run.sh
```

Useful commands:

```bash
./script/build_and_run.sh --verify  # build, validate, and launch the app
./script/build_and_run.sh --dmg     # build a drag-to-Applications installer
swift test                          # run the package test suite
```

The installer is created as `PodTrackio.dmg` at the repository root when
prepared for a release. Local build output stays in `dist/` and is ignored by
Git.

## Privacy and security

Your local library data lives under
`~/Library/Application Support/PodcastTracker/`. Never commit API keys,
service-role credentials, signing certificates, or local configuration. The
optional Supabase client uses a publishable/anon client identifier; production
deployments must enforce Row Level Security and keep privileged credentials on
the server.

## License

[MIT](LICENSE) © 2026 Tangenix Pvt. Ltd.
