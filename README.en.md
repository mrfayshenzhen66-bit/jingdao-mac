# 景到 Jingdao

[简体中文](README.md) · **English**

**An unofficial modified version of the open-source [SpektraLab](https://github.com/JamesQiu2005/SpektraLab) 1.3.5** — a film and print simulator for macOS.
This is not an official SpektraLab release and is not endorsed by the upstream author. The original documentation is in [README.SpektraLab.md](README.SpektraLab.md) (English) and [README.SpektraLab.zh-CN.md](README.SpektraLab.zh-CN.md) (Chinese).

> The name comes from the *Mozi* (Canon II): “景到，在午有端” — light passing through a small aperture forms an inverted image on the other side. The icon is a pinhole camera.

## Changes since SpektraLab 1.3.5

| Version | Changes |
|---|---|
| 20.6 | More responsive dragging: shorter render scheduling delays; a new edit cancels a full-resolution render in progress |
| 20.7 | Renamed “景到 (Jingdao)”, pinhole-camera icon |
| 20.8 | Getting-started guide: empty-canvas hints and a step bar (film → paper → enlarger → fine-tune → export) |
| 20.9 | Rotate buttons, Chinese interface text, wordmark in About, optional donation window |
| 21.0 | Segmented film cache: faster previews while dragging film exposure, grain and DIR (about 4.7 → 6.0 frames/s measured on Apple M4); export quality unchanged |
| 21.1 | **HSL** in Post-Dev (red, orange, yellow, green, aqua, blue, purple, magenta × hue / saturation / luminance); Color Balance is now labelled as the colour wheels in Chinese |

Also: film/paper combination presets, remembered export recipes, a transparent PNG signature layer, panel ordering, and Chinese menus.

The interface follows the system language (English or Simplified Chinese).

## Getting it and building

This repository provides **source code only**; no installer is published. See [PERSONAL-BUILD.txt](PERSONAL-BUILD.txt) (Chinese) for the full instructions. In short:

1. An Apple silicon Mac (macOS 15 or later) with Xcode or the Command Line Tools.
2. Official SpektraLab 1.3.5 installed at `/Applications/SpektraLab.app` — the build script reads its unmodified resources.
3. From the repository root:

   ```sh
   cd modern_UI/Spektrafilm
   Tools/build-personal.sh
   ```

   The result is a locally ad-hoc signed `景到.app`.

The script checks the official 1.3.5 baseline: engine resources, the shader library and film data stay identical to the release; only three C++ files under `engine/src/pipeline` may differ. The 21.1 HSL shader lives in `Canvas/HSLKernel.swift` and is compiled at run time, so the official shader library is untouched.

## License and credits

- App and engine: GPL-3.0-or-later (see [LICENSE.txt](LICENSE.txt)).
- Film/paper profiles and LUTs: CC BY-SA 4.0, from [spektrafilm](https://github.com/andreavolpato/spektrafilm) by Andrea Volpato.
- Original author: SpektraLab, [JamesQiu2005/SpektraLab](https://github.com/JamesQiu2005/SpektraLab).
- The SpektraLab name and icon belong to upstream; Jingdao’s name and icon contain no upstream name, logo or derivative artwork.
- The donation images are not in this repository. The in-app donation window is entirely optional, unlocks nothing, and goes to the author of this modified version, not to the upstream author.

## Contact

mrfay · mrfayshenzhen66@gmail.com
