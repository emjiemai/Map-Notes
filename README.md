# Map Notes

Field visit logging for B2B sales reps: pin where you went, leave a note. Built with Flutter and Supabase.

## Architecture

- **App**: Flutter (single codebase, iOS + Android)
- **Map**: `flutter_map` + free OpenStreetMap tiles for now (no API key, no native setup) — swap for Yandex MapKit before release, see [Switching to Yandex MapKit](#switching-to-yandex-mapkit-before-release)
- **Backend**: Supabase — Postgres + PostGIS, Auth (email/OTP for now, phone/OTP for release), Realtime, Storage (for photos later)
- **Dedupe**: `places` are canonical locations, deduped by proximity (~50m) via the `log_visit()` Postgres function. `visits` are never deduped — every pin a rep drops is its own row, always attached to the nearest existing place or a new one. See `supabase/migrations/0001_init.sql`.
- **Deletion**: a rep can delete their own visit any time (RLS-scoped to `auth.uid()`); a place is auto-removed once its last visit is gone. A team can only be deleted once every *current* member has voted to — tracked in `group_delete_votes`, enforced by a trigger server-side so it can't race. See `supabase/migrations/0005_delete_visits_and_teams.sql`.

## One-time setup

### 1. Install Flutter

Follow https://docs.flutter.dev/get-started/install, then confirm with `flutter doctor`. If install is giving you trouble, see [No local Flutter install](#no-local-flutter-install) below — you don't strictly need one.

### 2. Generate the platform folders

This repo only has `lib/` and `pubspec.yaml` — `android/`, `ios/`, etc. are generated locally (gitignored, since they're machine/SDK-version specific):

```bash
flutter create --org com.mapnotes --project-name map_notes .
```

Say yes if it asks to overwrite `pubspec.yaml`-adjacent files — it won't touch `lib/`.

### 3. Set up Supabase

1. Create a project at https://supabase.com.
2. In the SQL editor, run `supabase/migrations/0001_init.sql`.
3. Email/OTP auth is on by default — nothing to configure for that. (Phone auth needs an SMS provider; see "Switching to phone auth" below.)
4. Copy your project URL and anon key (Project Settings → API).

### 4. Configure environment

```bash
cp .env.example .env
```

Fill in `.env` (leave `YANDEX_MAPKIT_API_KEY` blank for now — not used until you switch off OpenStreetMap):
```
SUPABASE_URL=...
SUPABASE_ANON_KEY=...
```

### 5. Run

```bash
flutter pub get
flutter run
```

## No local Flutter install

Two ways to develop and ship without installing Flutter on your own machine:

**Cloud IDE (for writing/testing code):** GitHub Codespaces (or any devcontainer-based cloud IDE) can run a full Flutter environment in the browser — add a Flutter devcontainer to the repo and it installs the SDK for you server-side. Good if the local install itself is the blocker (disk space, permissions, PATH issues on Windows are the usual culprits — worth mentioning what error you hit, it's often a quick fix).

**Cloud build/release (for producing installable apps):** [Codemagic](https://codemagic.io) is the standard choice for Flutter — connects directly to a GitHub repo, builds both Android and iOS in the cloud (no Mac needed for iOS, unlike most CI), and has a free tier (500 build minutes/month). `codemagic.yaml` in this repo is already configured for it:

1. Sign up at codemagic.io with your GitHub account and add this repo.
2. Codemagic auto-detects `codemagic.yaml` — you'll see the `android-debug` workflow.
3. App settings → Environment variables → add `SUPABASE_URL` and `SUPABASE_ANON_KEY` (from Supabase Project Settings → API — the anon key is the public/client-safe one, fine to paste here).
4. Start a build. It produces an installable `.apk` under Artifacts — download it straight to an Android phone to test (enable "install from unknown sources" if prompted), no Play Store needed.

Once you're ready for wider testing, pair it with **Firebase App Distribution** (free) — Codemagic can push builds there automatically and testers get a simple install link. Real Play Store release needs a proper signing keystore (the workflow currently uses debug signing, which installs fine but Play Store will reject) — Codemagic's docs cover generating and wiring one up when you get there.

## Switching to Yandex MapKit (before release)

The map is isolated to two files: `lib/screens/map_screen.dart` and `lib/screens/add_visit_screen.dart`. Nothing in `models/`, `services/`, or the Supabase schema depends on which map renders — `lat`/`lng` doubles are all that's stored.

To switch:
1. `flutter pub add yandex_mapkit`, remove `flutter_map`/`latlong2` from `pubspec.yaml`.
2. Get a key at https://developer.tech.yandex.ru/services (MapKit Mobile SDK product). It's set **natively**, not in Dart:
   - **Android** — `android/app/src/main/kotlin/.../MainApplication.kt`, inside `onCreate()`: `MapKitFactory.setApiKey("YOUR_KEY")`
   - **iOS** — `ios/Runner/AppDelegate.swift`, inside `application(_:didFinishLaunchingWithOptions:)`: `YMKMapKit.setApiKey("YOUR_KEY")`
   - Add `INTERNET` and `ACCESS_FINE_LOCATION` to `android/app/src/main/AndroidManifest.xml`.
3. Replace `FlutterMap`/`TileLayer`/`MarkerLayer` in the two screens with `YandexMap`/`PlacemarkMapObject` (same declarative shape — list of markers in, tap callbacks out).

## Switching to phone auth (before release)

`login_screen.dart` uses email/OTP for now since it needs zero setup. To switch to phone/OTP (better fit for field reps — no email to remember):

1. In Supabase: Authentication → Providers → Phone → enable, and configure an SMS provider (Twilio, MessageBird, etc. — this requires their own account/billing).
2. In `login_screen.dart`: change `signInWithOtp(email: ...)` to `signInWithOtp(phone: ...)`, `OtpType.email` to `OtpType.sms`, and the email `TextField` to a phone one (the original phone version is in git history / this conversation if you want it back verbatim).

## Project layout

```
lib/
  main.dart                    # bootstraps Supabase, routes to login or map
  models/                      # Place, Visit
  services/visits_repository.dart  # all Supabase reads/writes go through here
  screens/
    login_screen.dart          # phone/OTP sign-in
    map_screen.dart            # main map, pins, "+" to add
    add_visit_screen.dart      # drop a pin: name + note (photo comes later)
    place_detail_screen.dart   # a place's visit history
supabase/migrations/0001_init.sql  # schema, RLS, dedupe function
```

## Notes / what's deliberately not here yet

- **Photos** are visible in the UI (category picker, the Photos row on Add Pin) but disabled — attaching does nothing right now. The schema (`visits.photo_urls`, the `visit-photos` storage bucket) and repository method (`uploadPhotos`) are already in place from when this was wired up; re-enabling is just re-connecting the Add Pin screen's photo picker to them (`image_picker` is still a dependency for exactly this reason).
- **Avatars are generated, not uploaded** — `lib/widgets/user_avatar.dart` derives a stable image from each user's id via DiceBear (free, no API key, no schema needed: `https://api.dicebear.com/9.x/avataaars/png?seed=<user_id>`). This is what makes reps recognizable to each other on the map/pinned strip/comments without a photo-upload feature. Swap for real profile photos later by adding an `avatar_url` column to `profiles` and changing `UserAvatar` to prefer it, falling back to the generated one.
- **No state management library** — screens call `VisitsRepository` directly and hold state locally. Fine at this size; revisit only if screens start needing to share live state.
- **OpenStreetMap tile usage** is fine for development but has fair-use limits for production traffic — another reason to switch to Yandex MapKit (or another paid tile provider) before a real release, not just for CIS-market accuracy.
- **Live-status ("Live Now"/attendee counts)** from the original mockup was intentionally adapted rather than copied — pins are visit records, not RSVP'd events, so the map shows a "Recent" badge on pins from the last 2 hours instead.
