# HotSync for macOS

A native macOS menu bar app for Palm OS HotSync &ndash; a replacement for the original
HotSync on Windows 98/XP: put the Palm into the cradle, press HotSync, done.

Background and pilot-link build for Apple Silicon: [palm2000.com](https://palm2000.com/articles/43)

## Download

A ready-to-use build for **Apple Silicon Macs (macOS 14 or newer)** is available on the
[Releases page](https://github.com/User7142/hotsync-macos/releases/latest):
`HotSync-<version>-macos-arm64.zip`. `pilot-xfer` and all the libraries it needs are
included &ndash; no Homebrew, no pilot-link installation required.

1. Unzip and move `HotSync.app` to `/Applications`.
2. The app is not notarized by Apple, so macOS blocks it on the first start. Open it once,
   then go to **System Settings → Privacy & Security** and click **Open Anyway**.
   Alternatively, in the Terminal:
   ```bash
   xattr -dr com.apple.quarantine /Applications/HotSync.app
   ```

The licenses of the included pilot-link, libusb and popt are in
`HotSync.app/Contents/Resources/ThirdPartyLicenses/`.

## Features

- **Menu bar app** (SwiftUI) &ndash; always ready, no Dock icon
- **Install queue** &ndash; `.prc`/`.pdb` files via drag & drop, double-click in the Finder, or the install folder
- **Automatic waiting** &ndash; as soon as files are queued, `pilot-xfer` starts and waits for the Palm
- **One HotSync for everything** &ndash; all queued files are transferred in a single `pilot-xfer` session
- **Verified installs** &ndash; a file only counts as installed when `pilot-xfer` confirmed its transfer; anything else stays queued for the next HotSync
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
5. Files whose transfer `pilot-xfer` confirmed are moved to `~/HotSync/<device>/Installed/`;
   files that were not transferred (timeout, error, cancel on the Palm) stay in `Install/`
   and are offered again on the next HotSync

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

pilot-link on Apple Silicon, from the current `master` branch (tested with commit
`1dfacd6c`). The tagged 0.15.0/0.15.1 sources do not find any USB device on macOS &ndash; this
was fixed upstream in commit `c32f9eed` ("libusb: fix device discovery on macOS and the BSDs"):

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
3. copies `pilot-xfer`, `pilot-install-user` and all their non-system libraries (libpisock,
   libusb-compat, libusb, popt &ndash; found recursively) into the bundle and rewrites the
   references to `@rpath`, so the app does not depend on Homebrew; the build fails if any
   reference outside the bundle is left
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

- **Install results are read from the `pilot-xfer` output.** A file counts as installed when
  its `Installing '…'` line is followed by `… KiB total.`; `pilot-xfer` does not always exit
  after a successful transfer, so the app then ends it (SIGKILL). If the output format of
  pilot-link changes, files are no longer confirmed &ndash; they stay queued instead of being
  reported as installed.
- **Thread safety.** `PalmIdentity` is `@unchecked Sendable` and shares state between a
  background queue and the main thread without locks or actors.
- **UI refresh via timer.** The main view refreshes every 0.5 s instead of purely reactively.
- **No real two-way sync.** The app only installs files. Addresses, dates and memos are not
  synced like with the original Palm Desktop, and the "Backups" folder is not used yet.
- `USBMonitor.swift` is currently unused.
- The Palm only appears on the USB bus while a HotSync is running, so `pilot-xfer` has to be
  started first &ndash; the app does this automatically when files are queued.
- The app is only signed ad hoc and not notarized (see [Download](#download)).

Pull requests are welcome.

## License

MIT, see [LICENSE](LICENSE). pilot-link, which is copied into the app bundle at build
time, is licensed under the GPL/LGPL.
