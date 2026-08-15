# ffmpeg-minimal-build

A minimal static build of FFmpeg 7.1.1 for Windows x64, compiled from the
`n7.1.1` source tree. Single 1.6 MB `ffmpeg.exe`, statically linked, no DLLs.

It does one job: open a Windows webcam through DirectShow and hand the caller
raw frames. That is the entire feature set. The build strips out everything
else, which is why the binary is so small.

## What it does

- DirectShow capture input (`--enable-indev=dshow`)
- MJPEG and rawvideo decoding, rawvideo encoding and muxing
- The `scale` filter for resizing
- Pipe protocol for streaming frames out of ffmpeg

## What it does not do

No network protocols, no ffplay, no ffprobe, no zlib, no iconv, no debug
symbols, no docs. The `--disable-all` base plus re-enabling only the pieces
above keeps the binary portable and the attack surface tiny.

## Why it exists

DeepScreen uses this in its desktop app to read camera frames for the native
Rust proctoring pipeline. The main application repo is private, so this
repository exists to publish the binary and the exact build recipe that
produced it. The public project where it is used:

https://github.com/Abdullah-Masood-05/deepscreen-viewer

## Build recipe

Clone FFmpeg at the `n7.1.1` tag, then run the configure command in
`build.sh` (an MSYS2/MinGW64 environment is expected) and `make`. The script
holds the exact flags this binary was built with, so the result is
reproducible.

```
./build.sh
make -j$(nproc)
```

## Downloads

Grab `ffmpeg-7.1.1-win64-custom.exe` from the [releases](../../releases)
page. The checksum is listed in each release.

## License

The FFmpeg source and this build are licensed under LGPL-2.1-or-later. See
[LICENSE](LICENSE). All credit for the underlying work belongs to the FFmpeg
developers; this repository only repackages a build of their software for a
specific use case.