![terminaldoom](https://github.com/user-attachments/assets/c39a2764-4147-464e-9517-64f352cebbc0)

Terminal Doom enables Doom-based games to play smoothly in modern terminals with original graphics and sound. It also works
over fast ssh connections.

Demo with sound:

[![Demo]](https://github.com/user-attachments/assets/8ca127d7-23f6-45cd-82e9-49c51c4cdc42)

## Building
There are no system dependencies, so just clone and build with Zig v0.13:

`zig build -Doptimize=ReleaseFast`

Run with `zig-out/bin/terminal-doom`

Terminal Doom uses the [libvaxis Zig library](https://github.com/rockorager/libvaxis) to render and handle keyboard and mouse events.
If you ever want to make a TUI app, I highly recommend this library. 

### Sound support
Sound is enabled by default. Add the `-Dsound=false` if you want to compile without sound support (like when running on a remote server via ssh)

All sound effects are included, and a few music tracks. You can download and add additional music tracks (mp3) yourself.
Terminal Doom will automatically pick them up from the `sound` directory. See the sound section for naming.

### Where does it run?
Tested on macOS and Linux. Compiles on Windows as well, but no terminal there seems to run it (WezTerm likely gets closest in ssh local mode)

Currently works best in Ghostty and Kitty as these have solid implementations of the required specs. WezTerm should
work if you use 'f' instead of ctrl keys for firing the gun.

## Playing
You can play keyboard-only (recommended) or in combination with a mouse. You can disable/enable mouse at any time by pressing `m`. This is useful when playing with keyboard on a laptop to avoid spurious input from the trackpad.

When using a mouse, make sure you adjust sensitivity in the Options menu if it's too fast or slow. Also try adjusting sensitivity on your mouse if it has buttons for this. Once sensitivity is right, playing with a mouse/keyboard combo is pretty efficient.

Keep in mind that mouse support in terminals comes with limitations, as apps are not able to capture the mouse.

| Action                    | Keys/Mouse Actions                  |
|---------------------------|-------------------------------------|
| Menu                      | ESC to open/close, Enter to select  |
| Walk / rotate             | Arrow keys or mouse. `j`, `l` also rotates.|
| Walk / strafe             | `wasd`                              | 
| Fire                      | `f`, `i`, control keys, mouse click |
| Use/open                  | Spacebar, right mouse click         |
| Strafe left/right         | Alt+arrow keys, `a`, `d`            |
| Quit                      | `Ctrl+c`                            |
| Disable/enable mouse      | `m`                                 |
| Disable/enable scaling    | `u`                                 |

Most other Doom keys should work as well, such as Tab for map and F5 for adjusting detail level.

## How it works

## Rendering
While the Kitty graphics protocol is primarily intended to display images, modern terminals and
computers are *fast*, with high memory bandwidth, SIMD support, and discrete GPUs. There's plenty
of juice available to run this classic game smoothly over a text protocol.

Here's how it works: on every frame, doomgeneric calls `DG_DrawFrame`. Our job is now to turn
the pixel data into a base64 encoded payload. This payload is then split into 4K chunks,
each chunk wrapped by the Kitty protocol envelope. Actually, some terminals work without
chunking, which is even faster, but that's not spec compliant and e.g. Kitty itself fails
without chunking (thanks to rockorager for pointing this out)

With the encoded message ready, we now:

1. Set synchronized output (mode 2026)
2. Clear the screen
3. Display the frame by sending the Kitty graphics message
4. Reset synchronized output to flush updates to screen
5. Handle any keyboard input

With the latest version, all of this is outsourced to libvaxis.

This sequence repeats for every frame. While this is enough to run Doom smoothly in a modern terminal, there are many optimizations that can be done, including SIMDifying pixel encoding.

## Sound
The history of Doom has many interesting facets, and its sound library is no different. You can read about it [here](https://doomwiki.org/wiki/Origins_of_Doom_sounds)

Terminal Doom's sound support originally worked by calling out to SDL2, but that had a couple of problems. First of all, the implementation
from doomgeneric was complicated and large. Second, depending on SDL2 made building harder on some systems.

This is the solution I came up with:

1. Ditch all the complex midi sequencing and mixing logic.
2. Make the wav and mp3 files part of the project
3. Outsource playback to *miniaudio*

While large, miniaudio is a single header file, it's portable, and has a straightforward API.

### Adding additional music tracks
Terminal Doom ships with a few tracks, such as for the intro and the first level.
You can add additional mp3's to the `sound` directory. For Terminal Doom to pick these up, they must be named
according to the Doom convention:

```
d_e1m1.mp3
d_e1m2.mp3
d_e1m3.mp3
d_e1m4.mp3
d_e1m5.mp3
d_e1m6.mp3
d_e1m7.mp3
d_e1m8.mp3
d_e1m9.mp3
d_inter.mp3
d_intro.mp3
d_victor.mp3
```

The actual content of these can obviously be anything you want, not just the orginal music.

## Supported games
`doom1.wad` is included in the repository and other wad files are available on various online sites.

These should all work:

```
doom2.wad
plutonia.wad
tnt.wad
doom.wad
doom1.wad
chex.wad
hacx.wad
freedm.wad
freedoom2.wad
freedoom1.wad
```

## Credits
* The engine is based on the amazing [doomgeneric](https://github.com/ozkl/doomgeneric) project
* Rendering and input is handled by [libvaxis](https://github.com/rockorager/libvaxis), a TUI library written in Zig
* Sound is handled by [miniaudio](https://miniaud.io/), a single-file sound playback library
* Build system (and the main input/rendering loop) is all [Zig](https://ziglang.org/)
* Testing and debugging in Ghostty's terminal inspector (currently closed beta), [Kitty](https://sw.kovidgoyal.net/kitty/graphics-protocol/), and [WezTerm](https://wezfurlong.org/wezterm/index.html)

## LICENSE
As Terminal Doom is based on the doomgeneric project, the project as a whole is licensed under GPL2.

The Zig-based renderer/handler, build file, and miniaudio bridge are licensed under MIT.
