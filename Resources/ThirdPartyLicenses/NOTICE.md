# Third-party components in HotSync.app

The pre-built `HotSync.app` contains the following third-party programs and libraries.
HotSync itself, including its sync tool `Contents/Resources/hotsync-session`, is licensed
under the MIT license; `hotsync-session` uses libpisock as a dynamically linked library.

| Component | Files in the app bundle | License | Source code |
|---|---|---|---|
| pilot-link 0.15.1 (commit `f9e34e6a`), library only | `Contents/Frameworks/libpisock.9.dylib` | LGPL-2.0 | https://github.com/desrod/pilot-link/tree/f9e34e6a339bcd83c926ba564cb306a5c2c48495 |
| libusb-compat 0.1.9 | `Contents/Frameworks/libusb-0.1.4.dylib` | LGPL-2.1 | https://github.com/libusb/libusb-compat-0.1/releases/tag/v0.1.9 |
| libusb 1.0.30 with 1 patch | `Contents/Frameworks/libusb-1.0.0.dylib` | LGPL-2.1 | https://github.com/libusb/libusb/releases/tag/v1.0.30 plus https://github.com/libusb/libusb/commit/94a5224ea1a7515c38c618694e8794e058c16412 (also in https://github.com/User7142/hotsync-macos/tree/v1.1.9/Vendor/libusb/patches) |

pilot-link and libusb-compat are used unmodified. libusb is 1.0.30 with one upstream fix
applied, libusb commit 94a5224e "darwin: avoid hotplug shutdown deadlock" (not in a libusb
release yet). All three are built from source by `Scripts/build-libusb.sh` and
`Scripts/build-pilot-link.sh` in the HotSync source repository; pilot-link with:

```
./configure --enable-libusb   # against the libusb/libusb-compat built before
```

The library references were rewritten to `@rpath` with `install_name_tool` so that the
libraries are loaded from the app bundle (see `Scripts/build.sh`). You can replace the
libraries in `Contents/Frameworks` with your own builds.

The full license texts are in this folder.
