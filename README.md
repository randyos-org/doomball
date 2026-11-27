# doomball

Doom-themed pinball, written in Zig (requires Zig 0.17.1). Shoot the
ball past demon bumpers and keep it out of the drain.

## Build & run

```
zig build run                      # native; Windows opens a Win32 window
zig build -Dtarget=x86_64-windows  # cross-compile a Windows exe
zig build test                     # unit tests
```

Every push to `main`, including a merged pull request, runs the Windows release
workflow. It tests the game, builds an optimized Windows executable with Zig
0.17.1, and publishes `doomball-windows-x86_64.exe` to a GitHub Release. Its
tag is `v` followed by the `.version` in `build.zig.zon` (initially `v1.0.0`)
and points to the tested commit.

Bump `.version` to the next `MAJOR.MINOR.PATCH` before merging a new release.
If that tag already points to a different commit, the workflow builds and
tests but does not publish or move the tag. A rerun for the tagged commit can
retry publishing. Pushing a `v*` tag also runs the workflow; the tag must
match the version in the tagged commit's `build.zig.zon`.

Controls: `Space` hold/release = plunger, `Left`/`Z`/`Shift` and
`Right`/`/`/`Shift` = flippers, `Enter`/`Space` = restart after game over, `Esc` = quit.

## Portability

Like doomgeneric, the game core (`src/game.zig`, `src/render.zig`) is fully
platform independent: it renders into a 240x360 `0x00RRGGBB` framebuffer and
reads a small `Input` struct. A port only implements the `Platform` struct in
`src/platform.zig` (init, shutdown, ticks, sleep, poll input, present):

- `src/platform_win32.zig` – Windows (Win32 + GDI, no dependencies)
- `src/platform_headless.zig` – scripted input, writes `doomball.ppm`
  (default on non-Windows; `zig build run -Dframes=<n>`)

Select a backend with `-Dbackend=win32|headless`, and add new ones in `build.zig`/`src/main.zig`.

## License

MIT, see [LICENSE](LICENSE).
