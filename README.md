# ffmpeg-ytdl-minimal-build

A minimal, statically linked, LGPL build of FFmpeg 7.1.1 for Windows x64,
compiled from the `n7.1.1` source tree. It ships `ffmpeg.exe` and
`ffprobe.exe` with no DLL dependencies besides Windows system libraries.

It contains exactly what [yt-dlp](https://github.com/yt-dlp/yt-dlp)'s
post-processors need for a YouTube downloader desktop app, and nothing else.

## What it does

- Merge `bestvideo+bestaudio` (H.264 / VP9 / AV1 + AAC / Opus) into MP4,
  MKV or WebM by stream copy (`--merge-output-format`)
- Extract audio (`-x --audio-format`) to MP3 (LAME), M4A (native AAC or
  copy), Opus (libopus or copy), WAV (PCM s16le) and FLAC
- Convert thumbnails (`--convert-thumbnails png|jpg`, WebP/JPEG/PNG in)
- Embed thumbnails as cover art (`--embed-thumbnail`) in MP3, M4A and MP4
- The fixups and helpers yt-dlp runs automatically (`aac_adtstoasc`,
  `setts`, `ffprobe` stream detection, metadata, concat)

## What it does not do

No network protocols (yt-dlp downloads, ffmpeg only processes local files),
no video encoders, no hardware acceleration, no devices, no ffplay, no docs,
no debug symbols, no GPL components.

## Configure flags and rationale

All flags live in [`build.sh`](build.sh). The build starts from
`--disable-all` and re-enables only:

| Group | Enabled | Why |
| --- | --- | --- |
| Programs / libs | `ffmpeg`, `ffprobe`, avcodec, avformat, avutil, avfilter, swresample, swscale | yt-dlp uses ffprobe for codec / stream detection when available |
| Protocols | `file`, `pipe` | local files only (`--disable-network`) |
| Demuxers | mov, matroska, aac, mp3, ogg, flac, wav, mpegts, concat, ffmetadata, image2, image_{png,jpeg,webp}_pipe | YouTube DASH streams, re-reading outputs, thumbnails, metadata |
| Muxers | mp4, ipod, mov, matroska, webm, mp3, ogg, opus, flac, wav, adts, image2, null | merge targets, audio targets, thumbnail output |
| Decoders | aac, mp3float, opus, vorbis, flac, pcm_s16le/s24le/f32le, png, mjpeg, webp, vp9 | audio re-encoding, thumbnail conversion; vp9 so stream probing fills the mp4 `vpcC` box when merging VP9 into MP4 |
| Encoders | libmp3lame, aac, libopus, flac, pcm_s16le, png, mjpeg | the five audio formats plus PNG/JPG thumbnails |
| Parsers | aac, h264, hevc, vp8, vp9, av1, opus, vorbis, mpegaudio, flac, png, mjpeg, webp | reliable stream-copy remuxing |
| BSFs | aac_adtstoasc, h264/hevc_mp4toannexb, vp9_superframe(_split), av1_frame_merge/split, extract_extradata, setts, mjpeg2jpeg, null | auto-inserted by muxers or requested by yt-dlp |
| Filters | aresample, aformat, anull, atrim, format, null, trim, scale, copy, acopy | sample-rate / format / pixel-format conversion the CLI auto-inserts |
| External | `libmp3lame`, `libopus`, `zlib` (all static) | MP3, Opus, PNG |
| Misc | `--enable-small --disable-autodetect --disable-doc --disable-debug --disable-network`, `-static` | size, reproducibility, portability |

## Build

`build.sh` is the entire build: it clones FFmpeg at `n7.1.1`, configures,
builds, strips and copies `ffmpeg.exe` and `ffprobe.exe` to `dist/`.

From an MSYS2 **MINGW64** shell:

```
pacman -S --needed git make diffutils \
  mingw-w64-x86_64-gcc mingw-w64-x86_64-nasm mingw-w64-x86_64-pkgconf \
  mingw-w64-x86_64-lame mingw-w64-x86_64-opus mingw-w64-x86_64-zlib
./build.sh
```

FFmpeg's configure does not handle spaces in paths; build from a path
without spaces, or pass a space-free source directory as the first argument
(`OUT_DIR` overrides the output directory).

The GitHub Actions workflow runs the same script on `windows-latest`,
uploads the binaries as an artifact, and attaches them to a release when a
`v*` tag is pushed.

## License

FFmpeg is licensed under the LGPL-2.1-or-later; this build is configured
without `--enable-gpl` and without `--enable-nonfree`, so the resulting
binaries are LGPL-2.1-or-later. See [LICENSE](LICENSE). Statically linked
third-party libraries:

- LAME (libmp3lame): LGPL-2.0-or-later
- libopus: BSD 3-Clause
- zlib: zlib license

When redistributing these binaries, include the FFmpeg/LGPL license text,
the libopus BSD notice and a pointer to the corresponding source (FFmpeg
`n7.1.1` plus this repository's `build.sh`). All credit for the underlying
work belongs to the FFmpeg, LAME, Opus and zlib developers.
