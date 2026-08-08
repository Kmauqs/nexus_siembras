# AGENTS.md

## Cursor Cloud specific instructions

NEXUS Siembras is a single Flutter app (`nexus_siembras`) — an offline-first agriculture
control tool. Its core value works 100% locally (encrypted SQLite via Drift + SQLCipher);
Supabase is only for optional cloud sync/multi-user. Standard commands live in `README.md`
(section "Ejecutar") and `pubspec.yaml`; this section only captures the non-obvious cloud caveats.

### Toolchain (already provisioned in the VM snapshot)
- Flutter **3.44.4 stable** (the revision pinned in `.metadata`) lives at `~/flutter` and is
  symlinked into `/usr/local/bin`, so `flutter`/`dart` resolve in any shell (including the
  non-interactive startup update script). Dart is 3.12.2.
- Linux desktop build toolchain and native-plugin deps are installed:
  `clang g++ cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-14-dev
  libsecret-1-dev libjsoncpp-dev libssl-dev` (SQLCipher needs OpenSSL),
  plus `gnome-keyring dbus-x11 xdg-user-dirs` for the runtime caveats below.

### Which platform to run/test on
- The repo officially targets **Android, Web, Windows** (no `linux/` is committed). On this
  Linux VM, run and test on **Linux desktop** — it is the only target that runs the full
  DB-backed app here.
- **Web will NOT work for real E2E**: `lib/data/database/db_connection_stub.dart` throws
  `UnsupportedError` (drift_wasm is not implemented yet), so the app breaks as soon as it
  touches the database. Do not use `-d chrome` to validate app functionality.
- The `linux/` runner scaffolding is generated locally and is **not committed**. If it is
  missing, regenerate it (idempotent): `flutter create --platforms=linux .` This also touches
  `.metadata`; do not commit that change.

### Running the GUI app (two non-obvious runtime requirements)
The desktop UI renders on `DISPLAY=:1`. Two things will otherwise crash startup:
1. `flutter_secure_storage` (stores the SQLCipher key) needs a **D-Bus session with an
   unlocked Secret Service**. Launch the app inside `dbus-run-session` with `gnome-keyring`
   unlocked, e.g.:
   ```bash
   export DISPLAY=:1
   dbus-run-session -- bash -c \
     'printf "nexuspw" | gnome-keyring-daemon --unlock --components=secrets,pkcs11 & \
      sleep 2; flutter run -d linux'
   ```
   Without this you get `PlatformException(KeyringLocked)` on the last onboarding step.
2. `path_provider` (`getApplicationDocumentsDirectory`) needs XDG user dirs. `xdg-user-dirs`
   is installed and `~/Documents` + `~/.config/user-dirs.dirs` exist in the snapshot; if a
   fresh home is used, run `xdg-user-dirs-update` and ensure `~/Documents` exists, otherwise
   you get `MissingPlatformDirectoryException`.

GPU acceleration is unavailable (`libEGL ... DRI3` warnings are harmless — it falls back to
software rendering; the UI still renders and is interactive).

### Lint / test / codegen
- Lint: `flutter analyze` (exits 0; there are ~100 pre-existing info/warning lints against the
  newer SDK — no errors).
- Tests: `flutter test` (16 unit/widget tests in `test/widget_test.dart`).
- Drift codegen: `dart run build_runner build --delete-conflicting-outputs` regenerates
  `*.g.dart` (e.g. `lib/data/database/database.g.dart`, which is committed). Run this after
  changing Drift table/DAO definitions. It is not in the startup update script (the generated
  file is committed and `flutter pub get` alone is enough for analyze/test/build).

### Supabase / .env
- `.env` is committed with real Supabase URL + publishable key and `SYNC_MODE=offline_first`,
  so Supabase init succeeds at startup. The app is fully usable without it — set
  `SYNC_MODE=local_only` (or blank `SUPABASE_URL`) for a self-contained local run.
