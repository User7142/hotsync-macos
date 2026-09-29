# Third-party components in HotSync.app

The pre-built `HotSync.app` contains the following third-party programs and libraries.
HotSync itself is licensed under the MIT license and runs `pilot-xfer` and
`pilot-install-user` as separate programs.

| Component | Files in the app bundle | License | Source code |
|---|---|---|---|
| pilot-link 0.15.1 (commit `1dfacd6c`) | `Contents/Resources/pilot-xfer`, `Contents/Resources/pilot-install-user`, `Contents/Frameworks/libpisock.9.dylib` | GPL-2.0 (tools), LGPL-2.0 (libpisock) | https://github.com/desrod/pilot-link/tree/1dfacd6c3f7650883779ecf24b02432b7a1069b6 |
| libusb-compat 0.1.9 | `Contents/Frameworks/libusb-0.1.4.dylib` | LGPL-2.1 | https://github.com/libusb/libusb-compat-0.1/releases/tag/v0.1.9 |
| libusb 1.0.29 | `Contents/Frameworks/libusb-1.0.0.dylib` | LGPL-2.1 | https://github.com/libusb/libusb/releases/tag/v1.0.29 |
| popt 1.19 | `Contents/Frameworks/libpopt.0.dylib` | MIT | https://github.com/rpm-software-management/popt/releases/tag/popt-1.19-release |

The components are used unmodified. pilot-link was built with:

```
CPPFLAGS="-I$(brew --prefix)/include" LDFLAGS="-L$(brew --prefix)/lib" \
  ./configure --enable-libusb --enable-conduits
```

The library references were rewritten to `@rpath` with `install_name_tool` so that the
libraries are loaded from the app bundle (see `Scripts/build.sh`). You can replace the
libraries in `Contents/Frameworks` with your own builds.

The full license texts are in this folder.
