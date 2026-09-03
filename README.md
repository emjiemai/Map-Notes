# Map Notes

Field visit logging for B2B sales reps: pin where you went, leave a note. Built with Flutter and Supabase.

## Architecture

- **App**: Flutter (single codebase, iOS + Android)
- **Map**: `flutter_map` + free OpenStreetMap tiles for now (no API key, no native setup) — swap for Yandex MapKit before release, see [Switching to Yandex MapKit](#switching-to-yandex-mapkit-before-release)
- **Backend**: Supabase — Postgres + PostGIS, Auth (name + PIN, no email/SMS, see below), Realtime, Storage (for photos later)
- **Dedupe**: `places` are canonical locations, deduped by proximity (~50m) via the `log_visit()` Postgres function. `visits` are never deduped — every pin a rep drops is its own row, always attached to the nearest existing place or a new one. See `supabase/migrations/0001_init.sql`.
- **Deletion**: a rep can delete their own visit any time (RLS-scoped to `auth.uid()`); a place is auto-removed once its last visit is gone. A team can only be deleted once every *current* member has voted to — tracked in `group_delete_votes`, enforced by a trigger server-side so it can't race. See `supabase/migrations/0005_delete_visits_and_teams.sql`.
- **Route tracking**: for transportation reimbursement, not general surveillance — see "Location tracking" below for exactly what it does and its real limits.

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
2. In the SQL editor, run every file in `supabase/migrations/`, in order (currently `0001` through `0008`).
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

## Location tracking (Routes tab)

Purpose is specifically transportation reimbursement (an accurate, hard-to-fake distance figure to base payment on) — not general "where is everyone right now" surveillance. `LocationTracker` (`lib/services/location_tracker.dart`) starts when `HomeShell` mounts (i.e. as soon as someone's signed in), only actually tracks during working hours (11:00–16:00 — reps are out finding customers then, not all day; edit `_windowStartMinutes`/`_windowEndMinutes` to change it), and logs a point to `rep_locations` whenever the device has moved at least 25m.

**Why distance-triggered, not a timer**: GPS is only accurate to a few meters even standing still. Sampling on a fixed interval (every 5s, every minute, whatever) means a stationary rep still accumulates random jitter that sums into fake "distance traveled" — the opposite of what this exists for. Logging only on real movement means no movement = no new point = nothing to sum, structurally, not by filtering after the fact.

**Two different tracking engines, chosen at runtime**: web and mobile can't share one implementation here — browsers have no background-location concept at all, and native background tracking has no web equivalent to fall back to.

- **Web**: `Geolocator.getPositionStream`. Its own `distanceFilter` asks the platform to only emit updates after real movement, but on web that request isn't actually honored — confirmed against a real test (449 points logged for a walk that should have produced maybe 30-40, most of it while stationary in one spot). The browser Geolocation API has no native distance-filter concept, so geolocator's web implementation emits on nearly every raw GPS update regardless of the setting. `LocationTracker` also checks distance from the last *logged* point itself before writing anything, which is what actually makes this correct on web.
- **Android**: [`tracelet`](https://pub.dev/packages/tracelet), a real native background-geolocation plugin (a foreground service under the hood, not a plain position stream) — this is what lets tracking survive the screen locking or the app being backgrounded, not just kept open on screen. Its own `distanceFilter` is honored natively, so no manual check is needed on this path.

  **The native store is the persistence path, not the `onLocation` callback** — this distinction is the whole reason an earlier version recorded nothing while the screen was off. tracelet's foreground service writes every fix to its own SQLite database in native code, which keeps running with the screen off; `onLocation` is a Dart callback, and Android suspends Flutter's Dart isolate the moment the app is backgrounded. Points were being collected natively the entire time and then never read by anyone. `LocationTracker._drainNativeStore()` reads that store (every minute while the app is alive, and immediately when the app returns to the foreground), uploads what it finds with each point's *own* recorded timestamp, and only then clears it from the device. Uploading before deleting is what makes this survive a failed upload — and incidentally makes it work offline, since points accumulate through a dead zone and sync once there's signal again. Configured with `stopOnTerminate: true` deliberately: tracking stops the instant the app process is actually killed, so the working-hours window can't quietly keep running (and draining battery, and showing its notification) for the rest of the day on a device that never reopens the app. The gap that leaves — a rep force-closing the app specifically to dodge tracking — is a narrower, more deliberate case than "screen locked while walking between visits," which is the case this was built to fix. iOS isn't wired up (no `ios/` project exists in this repo yet — that needs an Apple Developer Program account, see below); the tracelet calls themselves are already platform-neutral, so enabling iOS later is native-project setup, not a Dart rewrite.

**Foreground service = a persistent notification, by Android's own rule, not a choice made here**: while tracking is active, reps see a notification (something like "Map Notes is tracking your location") the whole time — Android requires this as the tradeoff for letting a background service keep running instead of being suspended. Nothing secret about it. Some phones (Xiaomi, Huawei, and other OEMs with aggressive battery managers) still kill background services despite this unless the app is manually exempted from battery optimization — the one-time "Battery settings" action on the tracking notice (`home_shell.dart`) sends a rep straight to that OS settings screen; there's no reliable way to detect in advance whether a given phone needs it.

**No delete/update policy on `rep_locations` at all** — unlike visits, a rep can't edit or remove their own trail. That's deliberate: this data exists specifically to be checked against, so self-service deletion would defeat the purpose. Retention is capped server-side instead: a `pg_cron` job (migration `0008`) purges anything older than 14 days daily, matching how far back the Routes tab lets you look.

The **Routes** tab (bottom nav) lets anyone pick a rep and a day (◀/▶, capped to the 14-day retention window) and see that day's trail as a line on the map, plus total distance — computed from the same points, not a separate calculation. Small time labels ("09:10", "09:20"...) sit along the line at 10-minute intervals — one label per bucket, not per raw GPS point, since points log irregularly (only on movement) and a label per point would be unreadable.

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
  models/                      # Place, Visit, Group, LocationPoint
  services/
    visits_repository.dart     # all Supabase reads/writes go through here
    location_tracker.dart      # distance-triggered movement logging (web: geolocator, Android: tracelet background service)
  screens/
    login_screen.dart          # name + PIN sign-in/sign-up
    home_shell.dart            # bottom nav (Map/Add/Routes/Profile), starts location tracking
    map_screen.dart            # main map, pins, "+" to add
    add_visit_screen.dart      # drop a pin: name + note (photo comes later)
    place_detail_screen.dart   # a place's visit history
    routes_screen.dart         # a rep's today-route + distance, for reimbursement
supabase/migrations/            # run in order — schema, RLS, dedupe, location tracking
```

## Notes / what's deliberately not here yet

- **Photos** are visible in the UI (category picker, the Photos row on Add Pin) but disabled — attaching does nothing right now. The schema (`visits.photo_urls`, the `visit-photos` storage bucket) and repository method (`uploadPhotos`) are already in place from when this was wired up; re-enabling is just re-connecting the Add Pin screen's photo picker to them (`image_picker` is still a dependency for exactly this reason).
- **Avatars are generated, not uploaded** — `lib/widgets/user_avatar.dart` derives a stable image from each user's id via DiceBear (free, no API key, no schema needed: `https://api.dicebear.com/9.x/avataaars/png?seed=<user_id>`). This is what makes reps recognizable to each other on the map/pinned strip/comments without a photo-upload feature. Swap for real profile photos later by adding an `avatar_url` column to `profiles` and changing `UserAvatar` to prefer it, falling back to the generated one.
- **No state management library** — screens call `VisitsRepository` directly and hold state locally. Fine at this size; revisit only if screens start needing to share live state.
- **OpenStreetMap tile usage** is fine for development but has fair-use limits for production traffic — another reason to switch to Yandex MapKit (or another paid tile provider) before a real release, not just for CIS-market accuracy.
- **Live-status ("Live Now"/attendee counts)** from the original mockup was intentionally adapted rather than copied — pins are visit records, not RSVP'd events, so the map shows a "Recent" badge on pins from the last 2 hours instead.
- **The env file is named `app.env`, not `.env`** — deliberately. Web servers commonly refuse to serve dotfiles, which silently breaks `flutter_dotenv` specifically on web (`dotenv.load()` doesn't throw, it just leaves every value empty) while working fine on Android/iOS, since native builds bundle it into the app rather than serving it over HTTP. Cost an afternoon to track down — don't rename it back.
