# Doomball design

Where the game is going and why. Each step is a GitHub issue of milestone v1.1.0; a change to this plan starts as a pull request that changes this file.

## The look

A pinball table seen from a fixed camera above its near end, in the 640x480 layout of the classic Windows pinball games: the table on the left (420x480), a status panel on the right (220x480). The art is in the spirit of early-90s software-rendered shooters: an 8-bit palette, textures that are 64 pixels on a side, light that falls off with distance in visible bands, and chunky sprites for monsters.

All art is original. The shareware `doom1.wad` (kept out of git) may be looked at for style, but its license forbids derivative works: no pixel, palette entry, sound or name is taken from it.

## Rendering: prerendered 2.5D

Real-time 3-D waits for rgl (randyos-org/rstd#817). Until then:

- **Camera.** One fixed perspective camera; `camera.zig` maps table coordinates (x across, y along the table toward the player, z up) to the screen and back.
- **Prerender.** At startup, every pixel of the view is ray cast once against the static table: the playfield plane and extruded shapes (walls, posts, bumpers, guides). Each hit is textured and lit, and stored as a color and a depth.
- **States.** A part with a few looks (a bumper lit or not, a key target lit or not, the gate open or closed) is ray cast once per state into a patch covering only its pixels, applied each frame over the background.
- **Each frame.** The background and its patches are copied, then the moving parts are drawn over them, depth-tested: balls (chrome spheres), flippers (ray cast in their small screen boxes) and demons (billboard sprites, scaled with distance, lit by the colormaps).

## Palette and light

`palette.zig`: 16 ramps of 16 shades each (gray, brown, blue, blood red, orange, yellow, toxic green, moss, steel blue, violet, bone, rust, flesh, teal, deep red, fullbright). A texel is a palette index; 32 light levels map each index to a darker shade of its own ramp, so shading bands as in 8-bit renderers. Light is a sector level, minus distance falloff, plus nearby light sources (the glowing pit, lit bumpers).

`textures.zig`: procedural 64x64 textures, deterministic: riveted tech panels, cracked hellstone, toxic sludge, rusted grating, marble with an inlaid sigil, blood-streaked metal.

## The table

One description in `table.zig` serves the physics and the renderer, so what is drawn is what the ball hits. 400 units across and 800 along, a ball of radius 8:

- a plunger lane on the right, three top rollover lanes, three bumpers, two slingshots, inlanes and outlanes, two flippers;
- the demon pit in the middle, where monsters roam;
- three key targets (red, blue, yellow), and a gate in front of a lock;
- a mission target.

The physics stays 2-D on the table plane, with substeps, up to three balls and ball-to-ball collisions. It reports events (bumper hit, rollover, target, demon hit, lock, drain) that the rules act on.

## Rules

- **Ranks:** Private, Corporal, Sergeant, Lieutenant, Captain, Major, Colonel, General. Completing a mission raises the rank and scores a bonus that grows with it.
- **Missions**, started by the mission target, each with a time limit: purge the pit (slay demons), bumper barrage, run the lanes, find the keys, hold the line (survive without draining).
- **Demons:** a horned brute and a bone crawler, original pixel art with walk, pain and death frames. They wander the pit; the ball knocks them back and slays them in a few hits; a slain one returns later.
- **Keys and multiball:** the three key targets light when hit; with all three the gate opens; a ball in the lock starts a three-ball multiball with a short ball save.

## Status panel

A metal frame with recessed displays: the score in large digits, the ball, the rank, the mission and its progress, the keys held, demons slain, and a few lines of messages. Its font is a 5x7 bitmap font of our own.

## Sound

Synthesized in the game core, no samples: square and saw tones, noise, sweeps and envelopes for each event, mixed into 16-bit mono PCM. The Win32 backend plays it through winmm's `waveOut`; the headless backend discards it.

## Files

`table.zig` (layout), `physics.zig`, `game.zig` (rules and the main state), `missions.zig`, `demons.zig`, `camera.zig`, `palette.zig`, `textures.zig`, `raycast.zig` (shape intersections), `prerender.zig`, `frame.zig` (each frame's composition), `sprites.zig`, `font.zig`, `panel.zig`, `audio.zig`; the platform backends stay thin.
