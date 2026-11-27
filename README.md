# Doomball

Doom-themed pinball, written in Zig (requires Zig 0.17.1). Shoot the ball past demon bumpers and keep it out of the drain.

## Build & run

```sh
zig build run                      # native; Windows opens a Win32 window
zig build -Dtarget=x86_64-windows  # cross-compile a Windows exe
zig build test                     # unit tests
```

Controls: `Space` hold/release = plunger, `Left`/`Z`/`Shift` and `Right`/`/`/`Shift` = flippers, `Enter`/`Space` = restart after game over, `Esc` = quit.

## Releases

Releases are on the [releases page](https://github.com/randyos-org/doomball/releases): `doomball-vVERSION-x86_64-windows.exe` and `doomball-vVERSION-aarch64-windows.exe`, built for each architecture's baseline CPU, and a `SHA256SUMS` file of them. The v1.0.0 EXE was built for the CPU of the machine that built it and stops with an illegal instruction on many others; use v1.0.1 or later.

Work goes on a branch from `dev` and reaches `dev` through a pull request; `main` only takes releases, through the standing pull request from `dev` to `main`. CI (`.github/workflows/ci.yml`) runs for that pull request, for pushes to `main` and by hand (`gh workflow run CI --ref BRANCH`), not for `dev`. When `main` gets a version (`build.zig.zon`) that has no tag and something a release ships has changed since the last tag, CI tags it, publishes the release and begins the next patch version on `dev`. Never tag or publish by hand.

## Portability

Like doomgeneric, the game core (the rules in `src/game.zig`, the physics in `src/physics.zig`, the renderer in `src/frame.zig` and `src/prerender.zig`, the panel in `src/panel.zig`) is fully platform independent: it renders into a 640x480 `0x00RRGGBB` framebuffer (the table view and a status panel) and reads a small `Input` struct. A port only implements the `Platform` struct in `src/platform.zig` (init, shutdown, ticks, sleep, poll input, present):

- `src/platform_win32.zig`: Windows (Win32 + GDI, no dependencies)
- `src/platform_headless.zig`: scripted input, writes `doomball.ppm` (default on non-Windows; `zig build run -Dframes=<n>`, or `-Dbackend=headless` on Windows)

Select a backend with `-Dbackend=win32|headless`, and add new ones in `build.zig`/`src/main.zig`.

## License

MIT, see [LICENSE](LICENSE).
