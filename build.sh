#!/usr/bin/env bash
# Reproduce the ffmpeg-ytdl-minimal-build static ffmpeg.exe + ffprobe.exe.
#
# A minimal, LGPL, statically linked FFmpeg for Windows x64 that contains
# exactly what yt-dlp's post-processors need for a YouTube downloader:
#   - merging bestvideo+bestaudio into mp4/mkv/webm (stream copy)
#   - extracting audio to mp3 / m4a / opus / wav / flac (+ vorbis, aac)
#   - converting / embedding thumbnails (webp -> png/jpg, attached_pic)
#   - metadata / chapter embedding and the usual container fixups
#
# What this does:
#   1. Clones FFmpeg at the n7.1.1 tag (shallow)
#   2. Configures it from --disable-all, re-enabling only the pieces above
#   3. Builds ffmpeg.exe and ffprobe.exe (static, no DLLs)
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

echo ">> configuring minimal build"
./configure \
  --disable-all \
  --enable-cross-compile \
  --arch=x86_64 \
  --target-os=mingw32 \
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
  --pkg-config-flags=--static \
  --extra-ldflags="-static -static-libgcc"

# ── 3. Build ───────────────────────────────────────────────────────────────
echo ">> building (this takes a while)"
make -j"$(nproc)" ffmpeg.exe ffprobe.exe
strip ffmpeg.exe ffprobe.exe

# ── 4. Extract ─────────────────────────────────────────────────────────────
mkdir -p "$OUT_DIR"
cp ffmpeg.exe ffprobe.exe "$OUT_DIR/"
echo ">> done:"
ls -l "$OUT_DIR"/ffmpeg.exe "$OUT_DIR"/ffprobe.exe
echo ">> runtime DLL imports (should be Windows system DLLs only):"
objdump -p "$OUT_DIR/ffmpeg.exe" | grep "DLL Name" || true
