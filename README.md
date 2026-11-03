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
- **Backups with every HotSync** &ndash; after the installs, the Palm's RAM databases (applications, data, settings) are fetched into `~/HotSync/<device>/Backup/`: all of them the first time, afterwards only the ones that changed, so later backups take seconds. A progress bar shows "12 of 257 databases". A backup cut short (cancel on the Palm, cable pulled) keeps the previous state of every database it did not get to. Per tab, **"HotSync: Install + Back Up"** or **"Install Only"** (say, for a slow serial tab), or set for all tabs at once
- **Restore** &ndash; "Backup → Restore at the next HotSync" puts the whole backup back onto the Palm. For a Palm that lost its memory (empty batteries, a dead backup capacitor, a hard reset): put it into the cradle, press HotSync, choose **Take Over a Known Device** and the device in the dialog, keep "Restore the backup" ticked &ndash; one HotSync brings back its name and ID, applications, data and settings
- **ROM dump** &ndash; "Backup → Read the ROM at the next HotSync" saves the Palm's ROM image as `~/HotSync/<device>/ROM/PalmOS-<version>.rom`, with a progress bar (an m515's 4 MB take under 3 minutes) &ndash; for emulators such as POSE or CloudpilotEmu. Palm OS 1 to 4 only: Palm OS 5 dropped the remote calls of the HotSync protocol this needs (they crash the Palm), so HotSync checks the version first and does not try
- **New Palms are asked about** &ndash; a Palm HotSync does not know yet brings up a dialog while it waits in the cradle: add it as a **new device** with its own tab and queue, under its own name or a new one, or **take over a known device** picked from a list (with its backup). Name and ID are written to that very Palm in the same HotSync, which then goes on to install its queue
- **The window follows the HotSync** &ndash; when a Palm connects, the window switches to its tab
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
6. With "Install + Back Up", the backup follows: changed databases go to `~/HotSync/<device>/Backup/`

### Backup and restore

- The backup holds the latest state of every database in the Palm's RAM, one `.prc`/`.pdb` per
  database. A database deleted on the Palm stays in the backup. Databases in ROM are not backed
  up; a few that pilot-xfer also leaves out are skipped (`Unsaved Preferences`, PACE caches, and
  some that reset Palm OS 5 devices when read).
- **Restore** goes before the queue in the same HotSync, data before the applications that use
  it. `Net Prefs` cannot be replaced during a HotSync (the Palm keeps it open for the connection)
  &ndash; the Palm keeps its own. The Palm may ask for a soft reset afterwards.
- Deleting a device moves its folder, with its backup, to the Trash.

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
    ├── Installed/    ← moved here after the sync
    ├── Backup/       ← the Palm's databases, updated with every HotSync
    └── ROM/          ← the ROM image, when read (Palm OS 1–4)
```

## Building

Unit tests (file checks, session protocol, Palm recognition, chains): `./Scripts/test.sh`

Requirements: macOS 14+, Swift and C command line tools, and from Homebrew:

```bash
brew install autoconf automake libtool pkg-config popt
```

pilot-link does not need to be installed: the build script builds its library `libpisock` itself
(`Scripts/build-pilot-link.sh`, into `.build/pilot-link`) from the commit pinned in
`Vendor/pilot-link/COMMIT`, plus any patches in `Vendor/pilot-link/patches` for fixes that are not
upstream yet, and only rebuilds it when one of them changes. The pinned commit is the upstream
`main` with the USB fixes from [pilot-link PR #49](https://github.com/desrod/pilot-link/pull/49)
(high-speed Palms such as the LifeDrive, Sony CLIE devices, no hanging listener, recovery from a
stalled USB pipe), so no patches are needed at the moment. The tagged 0.15.0/0.15.1 sources do not
find any USB device on macOS &ndash; this was fixed upstream in commit `c32f9eed`.

libusb and libusb-compat are built the same way (`Scripts/build-libusb.sh`, into `.build/libusb`;
`Vendor/libusb`, `Vendor/libusb-compat`), and libpisock is built against them, not against
Homebrew's: libusb 1.0.30 with libusb commit `94a5224e` on top ("darwin: avoid hotplug shutdown
deadlock", in `Vendor/libusb/patches`). Without it, a sync tool that exits right after a Palm was
unplugged can hang in `libusb_exit` for good &ndash; 1.0.30 and earlier have that deadlock on macOS.

```bash
# Optional: regenerate the icon (Resources/AppIcon.icns is already included)
swift Scripts/generate-icon.swift .

# Build and create the app bundle: universal (Apple Silicon and Intel) by default,
# --arm64 or --x86_64 for one architecture (faster)
./Scripts/build.sh

# Optional, for developers who rebuild often: a stable self-signed signing identity,
# so macOS keeps the Calendar/Contacts/Reminders grants across builds (see below)
./Scripts/make-signing-identity.sh

# Start
open HotSync.app
```

`Scripts/make-signing-identity.sh` is opt-in and worth a sentence: it creates a self-signed
code-signing certificate ("HotSync Development"), adds it to your **login keychain as a trusted
code-signing root**, and lets `/usr/bin/security` use the key without a prompt so `build.sh` can
sign unattended. Without it the app is signed ad hoc, which makes every build a new app to macOS
and loses the Calendar, Contacts and Reminders grants each time. Delete the certificate in
Keychain Access to undo it.

The build script:
1. compiles with `swift build -c release` for the chosen architectures (`--universal`, the default, `--arm64` or `--x86_64`; the embedded libraries are built the same way)
2. creates the `.app` bundle with `Info.plist`
3. builds libusb, libusb-compat and libpisock (see above), compiles `Tools/hotsync-session/hotsync-session.c` against libpisock, copies it and all its
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
- **No real two-way sync.** The app installs files and backs up and restores whole databases.
  Addresses, dates and memos are not synced with macOS Contacts or Calendar like with the
  original Palm Desktop.
- The Palm only appears on the USB bus while a HotSync is running, so a USB cradle itself is
  invisible: for USB, the app can only show which Palm reported last, not when the cradle was
  plugged in.
- The app is only signed ad hoc and not notarized (see [Download](#download)).

Pull requests are welcome.

## License

MIT, see [LICENSE](LICENSE). pilot-link, whose library is copied into the app bundle at build
time, is licensed under the GPL/LGPL.
