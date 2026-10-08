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

# One second of stereo 48 kHz noise as raw PCM, wrapped in WAV.
head -c 192000 /dev/urandom > "$work/in.raw"
"$FFMPEG" -hide_banner -loglevel error -f s16le -ar 48000 -ac 2 -i "$work/in.raw" "$work/in.wav"

for out in out.mp3 out.m4a out.opus out.flac out.mkv; do
  "$FFMPEG" -hide_banner -loglevel error -y -i "$work/in.wav" "$work/$out"
  dur="$("$FFPROBE" -v error -show_entries format=duration -of csv=p=0 "$work/$out")"
  echo "$out: duration=$dur"
done

# Remux (stream copy) the m4a into mp4, as yt-dlp does when merging.
"$FFMPEG" -hide_banner -loglevel error -y -i "$work/out.m4a" -c copy "$work/remux.mp4"
echo "smoke test passed"
