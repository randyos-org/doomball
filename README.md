# doomball

Doom-themed pinball, written in Zig (developed against Zig 0.13.0). Shoot the
ball past demon bumpers and keep it out of the drain.

## Build & run

```
zig build run                      # native; Windows opens a Win32 window
zig build -Dtarget=x86_64-windows  # cross-compile a Windows exe
zig build test                     # unit tests
```

Controls: `Space` hold/release = plunger, `Left`/`Z`/`Shift` and
`Right`/`/`/`Shift` = flippers, `Enter`/`Space` = restart after game over, `Esc` = quit.

## Portability

Like doomgeneric, the game core (`src/game.zig`, `src/render.zig`) is fully
platform independent: it renders into a 240x360 `0x00RRGGBB` framebuffer and
reads a small `Input` struct. A port only implements the `Platform` struct in
`src/platform.zig` (init, shutdown, ticks, sleep, poll input, present):

- `src/platform_win32.zig` – Windows (Win32 + GDI, no dependencies)
- `src/platform_headless.zig` – scripted input, writes `doomball.ppm`
  (default on non-Windows; `zig build run -- <frames>`)

Select a backend with `-Dbackend=win32|headless`, and add new ones in `build.zig`/`src/main.zig`.

## License

MIT, see [LICENSE](LICENSE).
