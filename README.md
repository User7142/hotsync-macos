# HotSync for macOS

A native macOS menu bar app for Palm OS HotSync &ndash; a replacement for the original
HotSync on Windows 98/XP: put the Palm into the cradle, press HotSync, done.

Background and pilot-link build for Apple Silicon: [palm2000.com](https://palm2000.com/articles/43)

## Features

- **Menu bar app** (SwiftUI) &ndash; always ready, no Dock icon
- **Install queue** &ndash; `.prc`/`.pdb` files via drag & drop, double-click in the Finder, or the install folder
- **Automatic waiting** &ndash; as soon as files are queued, `pilot-xfer` starts and waits for the Palm
- **Progress** &ndash; live status with a progress bar during the transfer
- **Notifications** &ndash; macOS notification after a successful sync
- **Several devices** &ndash; each Palm gets its own profile (HotSync user name and ID) and its own folder; for a new device, the user name is transferred on the first HotSync
- **German and English** user interface

## Usage

### Installing files

- **Double-click** a `.prc`/`.pdb` file in the Finder. It is copied into the install folder of the active device and `pilot-xfer` starts.
- **Drag & drop** files onto the HotSync window in the menu bar.
- **Install folder:** copy files into `~/HotSync/<device>/Install/`; the app picks them up automatically.

### Syncing

1. Add files (see above)
2. The menu bar icon changes to an antenna (`pilot-xfer` is waiting)
3. **Press the HotSync button on the Palm**
4. The transfer runs, the progress bar shows the status
5. After a successful sync, the files are moved to `~/HotSync/<device>/Installed/`

### Folders

```
~/HotSync/
└── <device>/
    ├── Install/      ← put .prc/.pdb files here
    └── Installed/    ← moved here after the sync
```

## Building

Requirements: macOS 14+, Swift command line tools, and `pilot-xfer` / `pilot-install-user`
from [pilot-link](https://github.com/desrod/pilot-link) in `~/.local/bin/`.

pilot-link on Apple Silicon (tested with pilot-link 0.15.1):

```bash
brew install libusb libusb-compat autoconf automake libtool popt readline pkg-config
git clone https://github.com/desrod/pilot-link.git && cd pilot-link
sh ./autogen.sh
CPPFLAGS="-I$(brew --prefix)/include" LDFLAGS="-L$(brew --prefix)/lib" \
  ./configure --prefix=$HOME/.local --enable-libusb --enable-conduits
make && make install
```

`--enable-conduits` builds the command line tools (off by default), `--enable-libusb` the USB support.

```bash
# Optional: regenerate the icon (Resources/AppIcon.icns is already included)
swift Scripts/generate-icon.swift .

# Build and create the app bundle
./Scripts/build.sh

# Start
open HotSync.app
```

The build script:
1. compiles with `swift build -c release`
2. creates the `.app` bundle with `Info.plist`
3. copies `pilot-xfer` and its libraries (libpisock, libusb, libpopt) into the bundle
4. signs the app ad hoc (no Apple developer account needed)

### Double-click handler

Once, after the first start:
1. Right-click a `.prc` file → "Open With" → "Other…"
2. Select `HotSync.app`
3. Enable "Always Open With"

## Technology

- Swift / SwiftUI (`MenuBarExtra`)
- `pilot-xfer` as a subprocess (embedded in the bundle, via libusb)
- FSEvents (file watcher)
- UserNotifications

## Known issues

This is a hobby project that does its job for me, but it has rough edges:

- **Detecting the end of a sync is a heuristic.** `pilot-xfer` does not always exit after a
  successful transfer. The app watches its output for "total" and then kills the process
  (SIGKILL). If the output format changes, detection breaks.
- **A timeout counts as success.** If `pilot-xfer` runs into the timeout, the file is still
  marked as installed and moved to `Installed/`. Check the Palm if in doubt.
- **Thread safety.** `SyncEngine` and `PalmIdentity` are `@unchecked Sendable` and share state
  between a background queue and the main thread without locks or actors.
- **UI refresh via timer.** The main view refreshes every 0.5 s instead of purely reactively.
- **No real two-way sync.** The app only installs files. Addresses, dates and memos are not
  synced like with the original Palm Desktop, and the "Backups" folder is not used yet.
- `USBMonitor.swift` is currently unused.
- The Palm only appears on the USB bus while a HotSync is running, so `pilot-xfer` has to be
  started first &ndash; the app does this automatically when files are queued.
- The app is only signed ad hoc and meant for personal use.

Pull requests are welcome.

## License

MIT, see [LICENSE](LICENSE). pilot-link, which is copied into the app bundle at build
time, is licensed under the GPL/LGPL.
