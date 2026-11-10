# Building BriechUAS (QGC with the Briech custom build)

Pinned versions. CI uses the same ones (`.github/build-config.json`); change
both together.

| Tool | Version | Notes |
|---|---|---|
| Qt | 6.10.1 | Modules: see `qt_modules` in `.github/build-config.json`. Fleet needs **qtwebsockets**; the 3D view needs **qtquick3d** (it compiles out without it). |
| CMake | 3.25 or newer, **3.31 recommended** | CMake 4.5.0-rc1 fails on zstd 1.5.7 ("No CMAKE_ASM_COMPILER could be found"). |
| Compiler (Windows) | MSVC 2022 (Build Tools are enough) | |
| Ninja | any recent | |
| GStreamer | Windows: 1.22.12 pinned; macOS: 1.24.13 | `cmake/find-modules/FindGStreamer.cmake` wants an exact match: with another version installed, add `-DGStreamer_FIND_VERSION=<installed>` (see below). |
| Python | 3.10+ | Coordinator, simulator and tools (`ground-core/`, `sim/`, `ops/`). |

## Windows

From a shell where MSVC is set up (`vcvars64.bat` from the VS 2022 Build Tools,
`VC\Auxiliary\Build\vcvars64.bat`):

```bat
cmake -S . -B build/Debug -G Ninja ^
  -DCMAKE_BUILD_TYPE=Debug ^
  -DCMAKE_PREFIX_PATH=C:/Qt/6.10.1/msvc2022_64 ^
  -DGStreamer_FIND_VERSION=1.24.13
cmake --build build/Debug
```

- If only the VS **Build Tools** are installed, `VsDevCmd.bat` may fail to find
  `vswhere`; `vcvars64.bat` with `C:\Program Files (x86)\Microsoft Visual Studio\Installer`
  on `PATH` works.
- VS 2022 ships CMake 3.31 at
  `...\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe`; use it if
  the CMake on `PATH` is 4.x.
- `-DGStreamer_FIND_VERSION` only when the installed GStreamer is not 1.22.12.
- The first full build takes about an hour; later builds are incremental.
- Use `-DCMAKE_BUILD_TYPE=Release` and `build/Release` for a Release build.
  **Measure performance in Release**: Debug Qt is many times slower, and the
  Debug build is not representative of what operators run.

Run the app with Qt and GStreamer on `PATH`:

```bat
set PATH=C:\Qt\6.10.1\msvc2022_64\bin;C:\gstreamer\1.0\msvc_x86_64\bin;%PATH%
build\Debug\Debug\BriechUAS.exe
```

## Fleet C++ tests (no QGC needed)

```sh
cmake -S custom/test/Fleet -B build/fleet-tests -G Ninja -DCMAKE_PREFIX_PATH=<Qt>/6.10.1/<kit>
cmake --build build/fleet-tests
ctest --test-dir build/fleet-tests --output-on-failure
```

## Ground side (coordinator, broker, simulators)

See `ops/README.md` and `ground-core/README.md`. In short, from the repo root:

```sh
make -C ops setup     # virtualenv, dev CA and certificates, MQTT logins, tokens
make -C ops dev-up    # broker, coordinator and fake publisher in the background
make -C ops sim-10    # ten simulated PX4 drones (Docker, SIH)
python3 ops/scripts/qgc-fleet-settings.py   # point QGC at the local coordinator
make -C ops test      # schema checks and coordinator tests
```

## Package id

`custom/cmake/CustomOverrides.cmake` sets the package id
`com.briechuas.groundcontrol` (stock QGC uses `org.mavlink.qgroundcontrol`), so
BriechUAS and stock QGC keep separate settings. Do not change it: that would
orphan every user's saved settings.
