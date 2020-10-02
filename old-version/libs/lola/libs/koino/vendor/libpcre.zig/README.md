# libpcre.zig

![Build status](https://github.com/kivikakk/libpcre.zig/workflows/Zig/badge.svg)

To build, add to your `build.zig`:

```zig
const linkPcre = @import("vendor/libpcre.zig/build.zig").linkPcre;
try linkPcre(exe);
exe.addPackagePath("libpcre", "vendor/libpcre.zig/src/main.zig");
```

Supported operating systems:

* Linux: `apt install pkg-config libpcre3-dev`
* macOS: `brew install pkg-config pcre`
* Windows: install [vcpkg](https://github.com/microsoft/vcpkg#quick-start-windows), `vcpkg integrate install`, `vcpkg install pcre --triplet x64-windows-static`
