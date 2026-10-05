# Third-party components in HotSync.app

The pre-built `HotSync.app` contains the following third-party programs and libraries.
HotSync itself, including its sync tool `Contents/Resources/hotsync-session`, is licensed
under the MIT license; `hotsync-session` uses libpisock as a dynamically linked library.

| Component | Files in the app bundle | License | Source code |
|---|---|---|---|
| pilot-link 0.15.1 (commit `1dfacd6c`) with 3 patches, library only | `Contents/Frameworks/libpisock.9.dylib` | LGPL-2.0 | https://github.com/desrod/pilot-link/tree/1dfacd6c3f7650883779ecf24b02432b7a1069b6 plus the patches in https://github.com/User7142/hotsync-macos/tree/v1.1.4/Vendor/pilot-link/patches |
| libusb-compat 0.1.9 | `Contents/Frameworks/libusb-0.1.4.dylib` | LGPL-2.1 | https://github.com/libusb/libusb-compat-0.1/releases/tag/v0.1.9 |
| libusb 1.0.29 | `Contents/Frameworks/libusb-1.0.0.dylib` | LGPL-2.1 | https://github.com/libusb/libusb/releases/tag/v1.0.29 |

libusb-compat and libusb are used unmodified. pilot-link is modified by three patches
(USB support for high-speed Palms such as the LifeDrive, timeouts for USB configuration
requests); they are in the HotSync source repository under `Vendor/pilot-link/patches`, and
`Scripts/build-pilot-link.sh` there applies them and builds the library with:

```
CPPFLAGS="-I$(brew --prefix)/include" LDFLAGS="-L$(brew --prefix)/lib" \
  ./configure --enable-libusb
```

The library references were rewritten to `@rpath` with `install_name_tool` so that the
libraries are loaded from the app bundle (see `Scripts/build.sh`). You can replace the
libraries in `Contents/Frameworks` with your own builds.

The full license texts are in this folder.
