# Map Notes

Field visit logging for B2B sales reps: pin where you went, leave a note. Built with Flutter and Supabase.

## Architecture

- **App**: Flutter (single codebase, iOS + Android)
- **Map**: `flutter_map` + free OpenStreetMap tiles for now (no API key, no native setup) — swap for Yandex MapKit before release, see [Switching to Yandex MapKit](#switching-to-yandex-mapkit-before-release)
- **Backend**: Supabase — Postgres + PostGIS, Auth (name + PIN, no email/SMS, see below), Realtime, Storage (for photos later)
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
2. In the SQL editor, run every file in `supabase/migrations/`, in order (`0001` through `0005`).
3. Authentication → Providers → Email → turn **off** "Confirm email" (required — sign-up uses a synthetic address under a real, mail-capable domain, so a confirmation link would never get clicked; see "Auth" below).
4. Copy your project URL and anon key (Project Settings → API).

### 4. Configure environment

```bash
cp app.env.example app.env
```

Fill in `app.env` (leave `YANDEX_MAPKIT_API_KEY` blank for now — not used until you switch off OpenStreetMap). Named without a leading dot deliberately — see the Notes section at the bottom of this file:
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

## Auth: name + PIN, no email or SMS

With a small, known team (a handful of reps), real verification is overkill, but pure anonymous sign-in (an earlier version of this) turned out to be worse: it mints a *brand-new* identity every time a session is lost, which is trivial on web (clear cookies, use incognito, switch browsers) — the same person ends up as multiple "different" reps, duplicate names on the map, and each fragment can't manage its own past pins.

`login_screen.dart` instead takes a name + a 6-digit PIN the rep picks themselves. Under the hood it's ordinary Supabase email/password auth — the name is normalized into a synthetic address under a real, mail-capable domain (`mapnotes.ulugbek@gmail.com`-shaped) purely as a stable account key, nothing is ever actually sent there. First "Continue" tap creates the account; every tap after that signs back into the *same* `auth.uid()`, from any device or browser — which is what makes it a real fix rather than a smaller version of the same bug. RLS, dedupe, and per-rep pin/vote deletion all work exactly as they would with any other auth method, since none of that depends on *how* someone authenticated.

Two things worth knowing about the domain choice: Supabase validates that an email's *domain* can actually receive mail, so it rejects `.internal`, and even `example.com` (no MX records) — a made-up domain never gets past sign-up, which is what broke the first attempt at this. And phone/password auth was tried as an alternative (phone numbers only get format-checked, no MX-style validation) but hit a harder wall: Supabase's dashboard requires picking an SMS provider before it lets you enable the Phone provider at all, even though password-based phone auth never actually sends an SMS — not worth pairing Twilio just to get past a UI gate.

Two things worth knowing:
- **The typed name is part of the account key** (normalized: trimmed, lowercased, whitespace collapsed) — a rep has to type it consistently to land on the same account. Fine for people typing their own name from memory; two reps who happen to share an exact name would collide (rare for a handful of known people, but if it happens, one of them adding a last initial resolves it).
- **Test accounts from earlier development** (anonymous sessions, email/OTP attempts) are still sitting in `auth.users`/`profiles` — harmless, but worth clearing out via Supabase Dashboard → Authentication → Users once you're done testing, so they don't clutter the team roster.

If the team grows past the point where a shared PIN scheme is comfortable, swap in real email or phone OTP: replace the sign-in/sign-up calls with `signInWithOtp(email: ...)` (needs custom SMTP) or `signInWithOtp(phone: ...)` (needs an SMS provider like Twilio).

## Deploying to web (Netlify) — the iOS alternative

Real iOS distribution needs an Apple Developer Program account ($99/year) — even for ad-hoc testing on your own iPhone, unlike Android's free sideloading. Until/unless that's worth it, the web build covers iOS (and everyone else) via a browser instead: same Flutter codebase, `flutter build web`, no App Store involved.

`netlify.toml` in this repo is already configured:

1. Sign up at [netlify.com](https://netlify.com) with your GitHub account and add this repo as a new site.
2. Site settings → Environment variables → add `SUPABASE_URL` and `SUPABASE_ANON_KEY` (same values as everywhere else).
3. Deploy. Netlify installs Flutter fresh each build (no Flutter in their default image) and publishes `build/web` — first deploy takes a few minutes longer than later ones.
4. You get a `*.netlify.app` URL — open it on any phone's browser (add to home screen on iOS for an app-like icon) or desktop.

Geolocation (for dropping a pin) needs HTTPS, which Netlify provides by default, so the "move the map to your location" flow works the same as it does locally.

## Project layout

```
lib/
  main.dart                    # bootstraps Supabase, routes to login or map
  models/                      # Place, Visit
  services/visits_repository.dart  # all Supabase reads/writes go through here
  screens/
    login_screen.dart          # name + PIN sign-in/sign-up
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
- **The env file is named `app.env`, not `.env`** — deliberately. Web servers commonly refuse to serve dotfiles, which silently breaks `flutter_dotenv` specifically on web (`dotenv.load()` doesn't throw, it just leaves every value empty) while working fine on Android/iOS, since native builds bundle it into the app rather than serving it over HTTP. Cost an afternoon to track down — don't rename it back.
