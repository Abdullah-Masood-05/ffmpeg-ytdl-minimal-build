#!/usr/bin/env bash
# Build recipe for the ffmpeg-minimal-build static ffmpeg.exe.
#
# Expected environment: MSYS2/MinGW64 (or any cross-toolchain providing
# x86_64-w64-mingw32-gcc). Run from inside the FFmpeg source tree at the
# n7.1.1 tag, then `make -j$(nproc)`.
set -euo pipefail

./configure \
  --disable-all \
  --enable-cross-compile \
  --arch=x86_64 \
  --target-os=mingw32 \
  --enable-ffmpeg \
  --enable-avdevice \
  --enable-avcodec \
  --enable-avformat \
  --enable-avutil \
  --enable-avfilter \
  --enable-swscale \
  --enable-indev=dshow \
  --enable-decoder=mjpeg,rawvideo \
  --enable-encoder=rawvideo \
  --enable-muxer=rawvideo \
  --enable-demuxer=rawvideo \
  --enable-protocol=pipe \
  --enable-parser=mjpeg \
  --enable-filter=scale \
  --disable-iconv \
  --disable-zlib \
  --disable-schannel \
  --enable-small \
  --disable-doc \
  --disable-ffplay \
  --disable-ffprobe \
  --disable-network \
  --disable-debug \
  --pkg-config=pkg-config \
  --extra-ldflags=-static