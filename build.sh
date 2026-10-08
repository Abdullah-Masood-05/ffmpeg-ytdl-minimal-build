#!/usr/bin/env bash
# Reproduce the ffmpeg-ytdl-minimal-build ffmpeg + ffprobe binaries.
#
# A minimal, LGPL, statically linked FFmpeg (Windows x64, Linux x86_64,
# macOS arm64) that contains
# exactly what yt-dlp's post-processors need for a YouTube downloader:
#   - merging bestvideo+bestaudio into mp4/mkv/webm (stream copy)
#   - extracting audio to mp3 / m4a / opus / wav / flac (+ vorbis, aac)
#   - converting / embedding thumbnails (webp -> png/jpg, attached_pic)
#   - metadata / chapter embedding and the usual container fixups
#
# What this does:
#   1. Clones FFmpeg at the n7.1.1 tag (shallow)
#   2. Configures it from --disable-all, re-enabling only the pieces above
#   3. Builds ffmpeg and ffprobe (static: no DLLs on Windows, no shared libs
#      besides glibc-free static on Linux, only system libs on macOS)
#   4. Copies the results to ./dist/
#
# Requirements (MSYS2 MINGW64 shell):
#   pacman -S --needed git make diffutils \
#     mingw-w64-x86_64-gcc mingw-w64-x86_64-nasm mingw-w64-x86_64-pkgconf \
#     mingw-w64-x86_64-lame mingw-w64-x86_64-opus mingw-w64-x86_64-zlib
#
# Note: FFmpeg's configure does not like spaces in the build path. Run this
# from a directory without spaces (or pass a space-free source dir as $1).
#
# Usage:
#   ./build.sh [ffmpeg-source-dir]
set -euo pipefail

FFMPEG_TAG="n7.1.1"
UPSTREAM_URL="https://github.com/FFmpeg/FFmpeg.git"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${1:-$SCRIPT_DIR/ffmpeg-src}"
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/dist}"
DEPS_PREFIX="${DEPS_PREFIX:-$SCRIPT_DIR/deps-prefix}"
LAME_VERSION="3.100"
OPUS_VERSION="1.5.2"

case "$(uname -s)" in
  MINGW*|MSYS*) PLATFORM=windows ;;
  Linux)        PLATFORM=linux ;;
  Darwin)       PLATFORM=macos ;;
  *) echo "unsupported platform: $(uname -s)" >&2; exit 1 ;;
esac
if [ "$PLATFORM" = macos ]; then JOBS="$(sysctl -n hw.ncpu)"; else JOBS="$(nproc)"; fi
EXE=""; [ "$PLATFORM" = windows ] && EXE=".exe"
echo ">> platform: $PLATFORM"

# ── 0. Static LAME + Opus (Linux / macOS) ──────────────────────────────────
fetch() { curl -fsSL --retry 5 --retry-delay 3 -o "$2" "$1"; }
if [ "$PLATFORM" != windows ] && [ ! -f "$DEPS_PREFIX/lib/libmp3lame.a" ]; then
  echo ">> building static LAME ${LAME_VERSION} and Opus ${OPUS_VERSION}"
  HOST_ARGS=()
  # LAME 3.100's config.guess predates Apple Silicon.
  [ "$PLATFORM" = macos ] && [ "$(uname -m)" = arm64 ] &&     HOST_ARGS=(--build=aarch64-apple-darwin --host=aarch64-apple-darwin)
  work="$(mktemp -d)"
  fetch "https://downloads.sourceforge.net/project/lame/lame/${LAME_VERSION}/lame-${LAME_VERSION}.tar.gz" "$work/lame.tgz"
  fetch "https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz" "$work/opus.tgz"
  tar -xzf "$work/lame.tgz" -C "$work"
  tar -xzf "$work/opus.tgz" -C "$work"
  # lame_init_old is listed in the export file but not built; drop it.
  sed -i.bak '/lame_init_old/d' "$work/lame-${LAME_VERSION}/include/libmp3lame.sym"
  (cd "$work/lame-${LAME_VERSION}" &&     ./configure --prefix="$DEPS_PREFIX" --disable-shared --enable-static       --disable-frontend --disable-decoder --enable-nasm=no ${HOST_ARGS[@]+"${HOST_ARGS[@]}"}       CFLAGS="-O2 -fPIC ${MACOS_CFLAGS:-}" &&     make -j"$JOBS" && make install)
  (cd "$work/opus-${OPUS_VERSION}" &&     ./configure --prefix="$DEPS_PREFIX" --disable-shared --enable-static       --disable-doc --disable-extra-programs CFLAGS="-O2 -fPIC ${MACOS_CFLAGS:-}" &&     make -j"$JOBS" && make install)
  rm -rf "$work"
fi

# ── 1. Source ──────────────────────────────────────────────────────────────
if [ ! -d "$SRC_DIR/.git" ]; then
  echo ">> cloning FFmpeg ${FFMPEG_TAG}"
  git clone --depth 1 --branch "$FFMPEG_TAG" "$UPSTREAM_URL" "$SRC_DIR"
fi
cd "$SRC_DIR"
git checkout --force "$FFMPEG_TAG" >/dev/null 2>&1 || true

# ── 2. Configure ───────────────────────────────────────────────────────────
# Containers yt-dlp reads from YouTube (and most other sites) and writes to.
DEMUXERS="mov,matroska,aac,mp3,ogg,flac,wav,mpegts,concat,ffmetadata,image2,image_png_pipe,image_jpeg_pipe,image_webp_pipe"
# mp4/ipod(m4a)/mov, matroska/webm, audio outputs, adts (aac), image2 (thumbs)
MUXERS="mp4,ipod,mov,matroska,webm,mp3,ogg,opus,flac,wav,adts,image2,null"
# Audio decoders: everything a source audio track may be, so it can be
# re-encoded. Image decoders: thumbnail conversion (webp needs vp8 internally).
# vp9: never used to transcode, but stream-info probing needs it to learn the
# pixel format / bit depth of VP9 tracks from webm. Without it the mp4 muxer
# writes an empty vpcC box and the merged VP9 .mp4 cannot be read back.
DECODERS="aac,mp3float,opus,vorbis,flac,pcm_s16le,pcm_s24le,pcm_f32le,png,mjpeg,webp,vp9"
# libmp3lame -> mp3, aac (native) -> m4a, libopus -> opus, flac, pcm -> wav,
# png/mjpeg -> thumbnail conversion.
ENCODERS="libmp3lame,aac,libopus,flac,pcm_s16le,png,mjpeg"
# Parsers make stream-copy remuxing reliable (keyframes, extradata, timing).
PARSERS="aac,h264,hevc,vp8,vp9,av1,opus,vorbis,mpegaudio,flac,png,mjpeg,webp"
# Bitstream filters the mp4/mkv muxers insert automatically or yt-dlp asks for.
BSFS="aac_adtstoasc,h264_mp4toannexb,hevc_mp4toannexb,vp9_superframe,vp9_superframe_split,av1_frame_merge,av1_frame_split,extract_extradata,setts,mjpeg2jpeg,null"
# Filters ffmpeg's CLI auto-inserts for audio/pixel-format conversion.
FILTERS="aresample,aformat,anull,atrim,format,null,trim,scale,copy,acopy"

case "$PLATFORM" in
  windows)
    PLATFORM_ARGS=(--enable-cross-compile --arch=x86_64 --target-os=mingw32
                   --extra-ldflags="-static -static-libgcc")
    ;;
  linux)
    export PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig"
    PLATFORM_ARGS=(--arch=x86_64 --target-os=linux
                   --extra-cflags="-I$DEPS_PREFIX/include"
                   --extra-ldflags="-L$DEPS_PREFIX/lib -static"
                   --extra-libs="-lm")
    ;;
  macos)
    export PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig"
    PLATFORM_ARGS=(--arch="$(uname -m)" --target-os=darwin
                   --extra-cflags="-I$DEPS_PREFIX/include ${MACOS_CFLAGS:-}"
                   --extra-ldflags="-L$DEPS_PREFIX/lib ${MACOS_CFLAGS:-}"
                   --extra-libs="-lm")
    ;;
esac

echo ">> configuring minimal build"
./configure \
  --disable-all \
  "${PLATFORM_ARGS[@]}" \
  --enable-ffmpeg \
  --enable-ffprobe \
  --enable-avcodec \
  --enable-avformat \
  --enable-avutil \
  --enable-avfilter \
  --enable-swresample \
  --enable-swscale \
  --enable-protocol=file,pipe \
  --enable-demuxer="$DEMUXERS" \
  --enable-muxer="$MUXERS" \
  --enable-decoder="$DECODERS" \
  --enable-encoder="$ENCODERS" \
  --enable-parser="$PARSERS" \
  --enable-bsf="$BSFS" \
  --enable-filter="$FILTERS" \
  --enable-libmp3lame \
  --enable-libopus \
  --enable-zlib \
  --disable-autodetect \
  --enable-small \
  --disable-doc \
  --disable-ffplay \
  --disable-network \
  --disable-debug \
  --pkg-config=pkg-config \
  --pkg-config-flags=--static

# ── 3. Build ───────────────────────────────────────────────────────────────
echo ">> building (this takes a while)"
make -j"$JOBS" "ffmpeg$EXE" "ffprobe$EXE"
strip "ffmpeg$EXE" "ffprobe$EXE"

# ── 4. Extract ─────────────────────────────────────────────────────────────
mkdir -p "$OUT_DIR"
cp "ffmpeg$EXE" "ffprobe$EXE" "$OUT_DIR/"
echo ">> done:"
ls -l "$OUT_DIR/ffmpeg$EXE" "$OUT_DIR/ffprobe$EXE"
echo ">> runtime library dependencies:"
case "$PLATFORM" in
  windows) objdump -p "$OUT_DIR/ffmpeg.exe" | grep "DLL Name" || true ;;
  linux)   file "$OUT_DIR/ffmpeg"; ldd "$OUT_DIR/ffmpeg" || true ;;
  macos)   otool -L "$OUT_DIR/ffmpeg" ;;
esac
