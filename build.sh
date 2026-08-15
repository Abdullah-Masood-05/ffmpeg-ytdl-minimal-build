#!/usr/bin/env bash
# Reproduce the ffmpeg-minimal-build static ffmpeg.exe end to end.
#
# What this does:
#   1. Clones FFmpeg at the n7.1.1 tag (shallow)
#   2. Configures it with only the DirectShow capture pieces enabled
#   3. Builds ffmpeg.exe (static, single binary)
#   4. Copies the result to ./dist/ffmpeg.exe
#
# Requirements:
#   - MSYS2/MinGW64 shell (built with gcc 16.1.0, MSYS2 project, here)
#   - make, git, pkg-config on PATH
#
# Usage:
#   ./build.sh
#
# The output is a single ~1.6 MB static exe. No DLLs, no ffprobe, no ffplay.
set -euo pipefail

FFMPEG_TAG="n7.1.1"
UPSTREAM_URL="https://github.com/FFmpeg/FFmpeg.git"
SRC_DIR="${1:-./ffmpeg-src}"
OUT_DIR="./dist"

# ── 1. Source ──────────────────────────────────────────────────────────────
if [ ! -d "$SRC_DIR/.git" ]; then
  echo ">> cloning FFmpeg ${FFMPEG_TAG}"
  git clone --depth 1 --branch "$FFMPEG_TAG" "$UPSTREAM_URL" "$SRC_DIR"
fi
cd "$SRC_DIR"
git checkout --force "$FFMPEG_TAG" >/dev/null 2>&1 || true

# ── 2. Configure ───────────────────────────────────────────────────────────
# The entire custom build is this flag set: start from --disable-all and
# re-enable only what DirectShow webcam capture needs.
echo ">> configuring minimal build"
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

# ── 3. Build ───────────────────────────────────────────────────────────────
echo ">> building (this takes a while)"
make -j"$(nproc)" ffmpeg

# ── 4. Extract ─────────────────────────────────────────────────────────────
mkdir -p "../$OUT_DIR"
cp ffmpeg.exe "../$OUT_DIR/ffmpeg.exe"
echo ">> done: ../$OUT_DIR/ffmpeg.exe ($(du -h "../$OUT_DIR/ffmpeg.exe" | cut -f1))"