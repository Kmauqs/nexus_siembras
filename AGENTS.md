# AGENTS.md

## Cursor Cloud specific instructions

NEXUS Siembras is a **Flutter** (Dart) offline-first agricultural app. Standard
commands and architecture are documented in `README.md`; this section only
captures non-obvious, durable setup/run caveats for this cloud VM. The update
script already runs `flutter pub get` + `dart run build_runner build` on startup.

### Toolchain (already provisioned in the VM image)
- Flutter stable lives in `/opt/flutter`; `flutter` and `dart` are symlinked into
  `/usr/local/bin`, so they work in any shell without PATH tweaks.
- Linux desktop build deps are installed (`ninja-build`, `libgtk-3-dev`,
  `libssl-dev` for SQLCipher, `build-essential`, `libstdc++-14-dev`, Mesa
  software GL). A `clang` linker fix symlink exists at
  `/usr/lib/x86_64-linux-gnu/libstdc++.so`.

### Lint / test / build / run
- Lint: `flutter analyze` — NOTE it reports ~100 pre-existing warnings/infos
  (mostly deprecations against the newer Flutter stable + a few unused
  elements) and exits non-zero. These are the repo's existing state, not a
  setup failure.
- Test: `flutter test` (unit tests in `test/`).
- Codegen: Drift's `database.g.dart` is committed, but rerun
  `dart run build_runner build --delete-conflicting-outputs` after schema edits.

### Runnable target = Linux desktop only
- The **web** target is a stub: `lib/data/database/db_connection_stub.dart`
  throws `UnsupportedError` for the local DB (drift_wasm is a future item), so
  the app is NOT functional on web. Android/Windows aren't runnable here.
- The `linux/` desktop scaffold is **not committed**. Generate it once per fresh
  checkout: `flutter create --platforms=linux .` (this also rewrites
  `.metadata`; run `git checkout -- .metadata` afterward to keep the tree
  clean). Then build: `flutter build linux --debug`.

### Running the app headlessly (required to reach the dashboard)
The app needs two OS services that are not on by default headless, or it dies at
the end of onboarding:
- `path_provider` needs XDG dirs — ensure `~/Documents` exists and run
  `xdg-user-dirs-update`.
- `flutter_secure_storage` (the SQLCipher DB key) needs a **D-Bus session with an
  unlocked gnome-keyring**, otherwise onboarding fails with
  `PlatformException(KeyringLocked)`.

A ready launcher is at `~/run_nexus.sh` (wraps the app in
`dbus-run-session` + `gnome-keyring-daemon --unlock` on `DISPLAY=:1`). Run it
after building, e.g. inside tmux. Equivalent inline command:

```bash
export HOME=/home/ubuntu DISPLAY=:1
mkdir -p ~/Documents; xdg-user-dirs-update
dbus-run-session -- bash -c 'eval "$(printf devpass | gnome-keyring-daemon --unlock --components=secrets,pkcs11,ssh 2>/dev/null)"; exec /workspace/build/linux/x64/debug/bundle/nexus_siembras'
```

- Run on `DISPLAY=:1` (the computer-use desktop) so GUI testing can see the
  GTK window. The `libEGL ... DRI3` warning is harmless (software GL).
- The encrypted DB is written to `~/Documents/nexus_siembras.sqlite` (header is
  random bytes = SQLCipher, not `SQLite format 3`); the key lives in
  gnome-keyring (`~/.local/share/keyrings/login.keyring`). Delete both to reset
  onboarding.
- `.env` (committed) holds optional Supabase creds; without valid ones the app
  still runs 100% local. To fully reset app state, also remove the keyring file.
