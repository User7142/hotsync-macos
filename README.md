# HotSync for macOS

A native macOS menu bar app for Palm OS HotSync &ndash; a replacement for the original
HotSync on Windows 98/XP: put the Palm into the cradle, press HotSync, done.

Background and pilot-link build for Apple Silicon: [palm2000.com](https://palm2000.com/articles/43)

## Download

A ready-to-use build for **Apple Silicon Macs (macOS 14 or newer)** is available on the
[Releases page](https://github.com/User7142/hotsync-macos/releases/latest):
`HotSync-<version>-macos-arm64.zip`. The sync tool and all the libraries it needs are
included &ndash; no Homebrew, no pilot-link installation required.

1. Unzip and move `HotSync.app` to `/Applications`.
2. The app is not notarized by Apple, so macOS blocks it on the first start. Open it once,
   then go to **System Settings → Privacy & Security** and click **Open Anyway**.
   Alternatively, in the Terminal:
   ```bash
   xattr -dr com.apple.quarantine /Applications/HotSync.app
   ```

The licenses of the included pilot-link library (libpisock) and libusb are in
`HotSync.app/Contents/Resources/ThirdPartyLicenses/`.

## Features

- **Menu bar app** (SwiftUI) &ndash; always ready, no Dock icon
- **Install queue** &ndash; `.prc`/`.pdb`/`.pqa` files via drag & drop, double-click in the Finder, or the install folder; the queue always shows the folder's content, whichever way a file got there
- **Checked before the HotSync** &ndash; every file's Palm database header is read: database name, **version** (of an application: its `tver` resource), type/creator and size are shown, and files HotSync cannot install (wrong format, truncated, …) are marked red and never sent
- **Reasons, not just "failed"** &ndash; a file the Palm refused stays in the queue with the reason (e.g. protected or in use on the Palm, not enough memory) and is tried again with the next HotSync
- **New Palms are asked about** &ndash; a Palm HotSync does not know yet brings up a dialog while it waits in the cradle: add it as a new device with its own tab and queue, under its own name or a new one. A Palm without a user name (new or after a hard reset) gets its name there. Name and ID are written to that very Palm in the same HotSync, which then goes on to install its queue
- **Remove from the queue** &ndash; every file has a trash button (moves it to the Trash)
- **Move to another Palm** &ndash; drag queued files onto the tab of another device or use "Move to" in the context menu; select several with shift-click (range) and command-click, as in the Finder
- **Tabs: a Palm on a port** &ndash; as many as you like: "m515 · USB", "IIIx · cu.usbserial-A1". The same Palm can have a USB and a serial tab; the queue belongs to the Palm
- **USB and serial cradles** &ndash; a USB-to-serial adapter shows up as soon as it is plugged in, with the time ("cable connected at 10:12"), so you can tell which port you just connected; USB shows which Palm reported last and when
- **The right files for the right Palm** &ndash; every Palm is recognised by its HotSync user ID before anything is installed. A Palm that does not belong to the tab gets nothing; the app shows who connected and lets you assign it to a profile or create a new one. A Palm without a user (new or hard reset) takes the identity of the profile it is synced with
- **Several ports at once** &ndash; USB and every serial adapter work independently; on one port, one tab at a time
- **Listen automatically or on demand** &ndash; a tab can wait for its Palm all the time (the port hands every Palm to the tab it belongs to), or sync only with "Sync Now"
- **Chains** &ndash; "when A is done, then B, then C": tabs that sync one after another. A failed step (no Palm within 5 minutes, wrong Palm, file refused) pauses the chain: retry, skip or cancel
- **One HotSync for everything** &ndash; all queued files of a Palm are transferred in a single session
- **Verified installs** &ndash; a file only counts as installed when the Palm confirmed it; anything else stays queued for the next HotSync
- **Progress** &ndash; live status with a progress bar during the transfer, a log per tab, and an entry in the HotSync log on the Palm
- **Notifications** &ndash; macOS notification after a successful sync and when a chain is done
- **German and English** user interface

## Usage

### Installing files

- **Double-click** a `.prc`/`.pdb` file in the Finder. It is copied into the install folder of the Palm of the selected tab.
- **Drag & drop** files onto the HotSync window: they go to the Palm of the selected tab. Dropped on a tab, they go to that tab's Palm.
- **Install folder:** copy files into `~/HotSync/<device>/Install/`; the app picks them up automatically.

### Syncing

1. Add files (see above)
2. A tab that listens automatically is ready at once (antenna in the tab and the menu bar);
   otherwise click **Sync Now** in the tab
3. **Press the HotSync button on the Palm**
4. HotSync checks who connected, then the transfer runs and the progress bar shows the status
5. Files the Palm confirmed are moved to `~/HotSync/<device>/Installed/`; files that were not
   transferred (error, cancel on the Palm, connection lost) stay in `Install/` and are offered
   again on the next HotSync

### Tabs, ports and chains

- **New tab** (`+` next to the tabs): choose the Palm and the port. A serial adapter you just
  plugged in is preselected and shows when it was connected. For serial ports, choose the
  baud rate (57600 works with every cradle from the Palm III on).
- **A Palm the app does not know** (or one that belongs to another tab) gets nothing installed.
  The tab shows its name and user ID with **Assign this Palm** (the profile now means this Palm;
  press HotSync again) and **New profile for this Palm**.
- **Chains** (button in the window): list tabs in order and run them. Each step waits up to five
  minutes for its Palm; while a step runs, press HotSync on that Palm.

### Moving from 1.0

On the first start, every existing device gets a USB tab that listens automatically &ndash;
everything works as before. Profiles that were created without reading the Palm carry a made-up
user ID; when such a Palm connects, assign it once.

### Folders

```
~/HotSync/
└── <device>/
    ├── Install/      ← put .prc/.pdb files here
    └── Installed/    ← moved here after the sync
```

## Building

Unit tests (file checks, session protocol, Palm recognition, chains): `./Scripts/test.sh`

Requirements: macOS 14+, Swift and C command line tools, and from Homebrew:

```bash
brew install libusb libusb-compat autoconf automake libtool pkg-config
```

pilot-link does not need to be installed: the build script builds its library `libpisock` itself
(`Scripts/build-pilot-link.sh`, into `.build/pilot-link`) from the commit pinned in
`Vendor/pilot-link/COMMIT` plus the patches in `Vendor/pilot-link/patches`, and only rebuilds it
when one of them changes. The tagged 0.15.0/0.15.1 sources do not find any USB device on macOS
&ndash; this was fixed upstream in commit `c32f9eed`. The patches on top:

- `0001` accepts high-speed (512-byte) bulk endpoints &ndash; without it a LifeDrive is never seen
- `0002` gives the device a second to answer each USB configuration request instead of waiting
  forever &ndash; a device that does not answer used to block the listener for good
- `0003` keeps a failed connection-info request failed for Tapwave-flagged devices
  (0x0830:0x0061: Zire 31/72, Z22, LifeDrive) instead of going on with guessed USB pipes
- `0004` gives the Sony CLIE configuration requests a buffer for their answer &ndash; without it
  the sync tool crashed on every HotSync of a CLIE such as the NR70V
- `0005` takes the bulk endpoints of a device that does not support the connection-info request
  (it stalls it) instead of skipping it forever &ndash; without it a CLIE N770C never syncs

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
3. builds libpisock from pilot-link plus patches (see above), compiles `Tools/hotsync-session/hotsync-session.c` against libpisock, copies it and all its
   non-system libraries (libpisock, libusb-compat, libusb &ndash; found recursively) into the
   bundle and rewrites the references to `@rpath`, so the app does not depend on Homebrew; the
   build fails if any reference outside the bundle is left
4. signs the app ad hoc (no Apple developer account needed)

### Double-click handler

Once, after the first start:
1. Right-click a `.prc` file → "Open With" → "Other…"
2. Select `HotSync.app`
3. Enable "Always Open With"
4. The same for a `.pdb` file

## Technology

- Swift / SwiftUI (`MenuBarExtra`)
- `hotsync-session`: a small C tool on libpisock (pilot-link), one process per port. It accepts the
  connection, reports the Palm's user name and ID, and then installs what the app tells it to
  &ndash; that is how a file can never end up on the wrong Palm. Events go to the app as one JSON
  object per line, instructions come back on stdin
- IOKit (serial adapters coming and going)
- FSEvents (file watcher)
- UserNotifications

## Known issues

This is a hobby project that does its job for me, but it has rough edges:

- **One Palm per port at a time.** pilot-link takes the first Palm it finds on any USB bus and
  cannot address a particular one, so two USB Palms cannot sync at the same time. Use a chain to
  sync them one after another; USB and serial ports do run at the same time.
- **No real two-way sync.** The app only installs files. Addresses, dates and memos are not
  synced like with the original Palm Desktop, and the "Backups" folder is not used yet.
- The Palm only appears on the USB bus while a HotSync is running, so a USB cradle itself is
  invisible: for USB, the app can only show which Palm reported last, not when the cradle was
  plugged in.
- The app is only signed ad hoc and not notarized (see [Download](#download)).

Pull requests are welcome.

## License

MIT, see [LICENSE](LICENSE). pilot-link, whose library is built with the patches in
`Vendor/pilot-link/patches` and copied into the app bundle at build time, is licensed under the
GPL/LGPL.
