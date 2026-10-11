# NeuroLens mobile app (Flutter)

The phone version of NeuroLens: analyze Reels, videos and images, import your Instagram / YouTube history, look after a child's feed, and run Feed checks.
It is a thin client. Every analysis runs on your NeuroLens server (`backend/`), and the app talks to it over the same HTTP API the website uses.

## Run it

```bash
cd flutter
flutter pub get
flutter run                  # a connected phone or emulator
flutter build apk            # an installable Android app (build/app/outputs/flutter-apk/)
```

The server address is built in (`AppSettings.defaultServer` in `lib/core/settings.dart`), so nobody has to type it. **Settings → Server** can point
the app at another server (for example one on your Wi-Fi). An address saved as `localhost` is ignored: on a phone it means the phone itself.

## Accounts

People sign up or sign in on the first screen (email and password, stored hashed on the server). Each account has its own history, child profiles,
imports, Instagram sessions and alerts, and a plan (Starter, Creator & Family, Studio) with monthly analyses and child-profile limits that the
server enforces. Choosing a paid plan is a demo (no real payment) until a payment provider is connected. **Account** also changes the password and
deletes the account and its data.

## What is in it

| Tab | What it does | API |
|---|---|---|
| **Home** | Greeting, plan and usage, this week's numbers, your mood mix, recent analyses, shortcuts | local |
| **Analyze** | Paste links or pick videos and images. Runs in the background, so you can keep browsing | `POST /api/analyze-link`, `POST /api/analyze`, `GET /api/jobs/{id}` |
| **Import** | Pick an Instagram or Google Takeout export; it is read on the phone and turned into a habits report | local |
| **Feed** | Sign in to Instagram in the app, check what a feed shows, monitor a child's account (with their knowledge), alerts | `/api/sessions`, `/api/scans`, `/api/monitors`, `/api/alerts` |
| **Family** | Child profiles, weekly wellbeing summary, jump to analysis, history or feed monitoring | local |

Every tab has the same header: the logo, the screen name, alerts and the account. History, Plans and Settings are reached from Home or the account button.

**Share to NeuroLens (Android):** share a Reel or YouTube Short link from Instagram, YouTube or a browser, choose NeuroLens, and the analysis starts
straight away (`MainActivity.kt` receives the share; `lib/core/share_intake.dart`).

### Import

`lib/core/imports` is a port of the website's importer: only an allowlist of history files is opened (messages and personal information are never
read), parsing and scoring run in a background isolate, and only the finished report is kept on the phone for the signed-in account. Instagram and
YouTube reports are always separate.

### Instagram sign-in

The app shows Instagram's own sign-in page inside the app (`ui/screens/instagram_signin.dart`). The password goes straight to Instagram. When you are
in, the session cookies are sent to your NeuroLens server (`POST /api/sessions/{id}/import`), which keeps them in a private browser profile so checks
can run there, and uses them to download Instagram links that need a login. Disconnecting deletes them.

## Code map

```
lib/
  core/      api.dart (HTTP client), auth.dart, models.dart, stores.dart (history, profiles, job queue), settings.dart,
             share_intake.dart, imports/ (parse, habits, import_store), alerts.dart, wellbeing.dart, moods.dart
  ui/        theme.dart, shell_nav.dart, widgets/ (common, tab_bar), screens/*
test/        core, API, auth, job queue, imports, share, accessibility, screens, and real server results (test/fixtures)
tool/        shots_test.dart renders every screen to PNG for review (flutter test tool/shots_test.dart)
```

State is kept with `provider`. History, profiles and import reports are stored on the phone, per account (`shared_preferences`); the session token is
in the secure store.

## Tests

```bash
flutter analyze
flutter test
```

`test/a11y_test.dart` checks every main screen for touch-target size, labelled controls, text contrast (light and dark) and 200% text size.
The fixtures in `test/fixtures` are real results from the backend, so a change in the server's response shape fails a test here.

## Limits

- **Background notifications:** alerts are fetched while the app is open. Pushing them when the app is closed needs Firebase (a project, `google-services.json`), which is not set up.
- **Share target is Android only.** iOS needs a share extension built in Xcode.
- **Payments are a demo** and there is no password reset email yet.
- Instagram may ask for an extra check when a session made on the phone is used from the server.
