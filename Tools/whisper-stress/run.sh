#!/usr/bin/env bash
# Re-checks the ggml crash that used to kill Nivi mid-dictation.
#
# It drives whisper the way one recording does: streaming passes with timestamps
# and a growing audio_ctx, then a final pass with no timestamps and the full
# context, all on a single whisper context, forty times over. Before
# vendor/patches/0001-ggml-alloc-guard-stale-buffer-id.patch it died with SIGSEGV
# partway through. It should now print SURVIVED.
#
# Not part of `make test`: it needs a downloaded model and takes a few minutes.
#
#     bash Tools/whisper-stress/run.sh
#     bash Tools/whisper-stress/run.sh ~/Library/Application\ Support/Nivi/models/whisper-small-en.bin
set -euo pipefail
cd "$(dirname "$0")/../.."

MODEL="${1:-$HOME/Library/Application Support/Nivi/models/ivrit-large-v3-turbo.bin}"
if [ ! -f "$MODEL" ]; then
    echo "No model at: $MODEL"
    echo "Install one from Preferences > Dictation Models, or pass a path."
    exit 1
fi
if [ ! -f vendor/lib/libggml.a ]; then
    echo "vendor/lib is empty. Run: make vendor"
    exit 1
fi

OUT="$(mktemp -d)/whisper-stress"
clang -O2 -o "$OUT" Tools/whisper-stress/main.c \
    -ISources/CWhisper/include -Lvendor/lib \
    -lwhisper -lggml -lc++ \
    -framework Metal -framework MetalKit -framework Accelerate -framework Foundation

echo "Running against: $MODEL"
LOG="$OUT.log"
set +e
"$OUT" "$MODEL" > "$OUT.out" 2> "$LOG"
set -e

# The crash lives in the GPU scheduler path. A run that quietly fell back to the CPU
# proves nothing about it, and an earlier version of this script passed that way.
if ! grep -q "using Metal backend" "$LOG" || grep -q "ggml_metal_init: error" "$LOG"; then
    echo "WHISPER GRAPH STRESS INVALID: whisper did not run on Metal."
    grep -m3 "ggml_metal_init: error\|failed to allocate" "$LOG" || true
    exit 1
fi
if tail -1 "$OUT.out" | grep -q SURVIVED; then
    echo "WHISPER GRAPH STRESS PASSED (on Metal)"
else
    echo "WHISPER GRAPH STRESS FAILED: the allocator crash is back."
    echo "Check that vendor/patches applied: make vendor"
    exit 1
fi
