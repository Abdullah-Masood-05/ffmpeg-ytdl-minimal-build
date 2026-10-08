#!/usr/bin/env bash
# Smoke test a built ffmpeg/ffprobe pair: the encoders yt-dlp relies on are
# present and real conversions to every supported audio format work.
#
# Usage: ./smoke_test.sh path/to/ffmpeg path/to/ffprobe
set -euo pipefail

FFMPEG="$1"
FFPROBE="$2"

"$FFMPEG" -hide_banner -version | head -n 1
"$FFPROBE" -hide_banner -version | head -n 1

encoders="$("$FFMPEG" -hide_banner -encoders)"
for enc in libmp3lame aac libopus flac pcm_s16le png mjpeg; do
  grep -qw "$enc" <<<"$encoders" || { echo "missing encoder: $enc" >&2; exit 1; }
done
"$FFMPEG" -hide_banner -bsfs | grep -q '^setts'

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# One second of stereo 48 kHz 16-bit noise as a WAV file. The header is
# written by hand because the build (deliberately) has no raw PCM demuxer.
{
  printf 'RIFF\x24\xee\x02\x00WAVE'
  printf 'fmt \x10\x00\x00\x00\x01\x00\x02\x00\x80\xbb\x00\x00\x00\xee\x02\x00\x04\x00\x10\x00'
  printf 'data\x00\xee\x02\x00'
  head -c 192000 /dev/urandom
} > "$work/in.wav"
"$FFPROBE" -v error -show_entries stream=codec_name,sample_rate,channels -of csv=p=0 "$work/in.wav"

for out in out.mp3 out.m4a out.opus out.flac; do
  "$FFMPEG" -hide_banner -loglevel error -y -i "$work/in.wav" "$work/$out"
  dur="$("$FFPROBE" -v error -show_entries format=duration -of csv=p=0 "$work/$out")"
  echo "$out: duration=$dur"
done

# Remux (stream copy) into mp4/mkv/webm, as yt-dlp does when merging.
"$FFMPEG" -hide_banner -loglevel error -y -i "$work/out.m4a" -c copy "$work/remux.mp4"
"$FFMPEG" -hide_banner -loglevel error -y -i "$work/out.opus" -c copy "$work/remux.mkv"
"$FFMPEG" -hide_banner -loglevel error -y -i "$work/out.opus" -c copy "$work/remux.webm"
echo "smoke test passed"
