#!/bin/bash
# Fetch + build whisper.cpp (static, Metal) pinned to v1.9.1, and stage the
# headers the CWhisper SwiftPM module needs. Run from anywhere; operates on the
# repo root. Idempotent. Prerequisite for `swift build`.
set -e
cd "$(dirname "$0")/.." || exit 1

TAG=v1.9.1
# The commit v1.9.1 pointed to when pinned (2026-07-08). Tags are mutable refs —
# a compromised upstream could force-move one; a commit hash cannot lie. This
# code is compiled into the binary that receives all microphone audio.
COMMIT=f049fff95a089aa9969deb009cdd4892b3e74916
REPO=https://github.com/ggml-org/whisper.cpp

if [ ! -d whisper.cpp ]; then
  echo "Cloning whisper.cpp $TAG ..."
  git clone --depth 1 --branch "$TAG" "$REPO" whisper.cpp
fi

# Enforce the pin on EVERY run — a fresh clone catches a force-moved tag, and a
# pre-existing checkout (earlier experiment, dirty tree) must not silently
# masquerade as the pin.
GOT="$(git -C whisper.cpp rev-parse HEAD)"
if [ "$GOT" != "$COMMIT" ]; then
  echo "!! whisper.cpp is at commit $GOT" >&2
  echo "   expected $TAG = $COMMIT" >&2
  echo "   Stale checkout or a moved upstream tag. Delete whisper.cpp/ and re-run." >&2
  exit 1
fi
# The commit alone isn't enough: locally modified tracked sources at the right
# commit would still build into the mic-handling binary. (Build output lives in
# untracked build-static/, so this only trips on real source edits.)
if ! git -C whisper.cpp diff --quiet || ! git -C whisper.cpp diff --cached --quiet; then
  echo "!! whisper.cpp checkout has local modifications — refusing to build." >&2
  echo "   Inspect with: git -C whisper.cpp status; then restore or delete the checkout." >&2
  exit 1
fi

echo "Building whisper.cpp static libraries (Metal, no Core ML) ..."
cmake -S whisper.cpp -B whisper.cpp/build-static \
  -DBUILD_SHARED_LIBS=OFF -DWHISPER_COREML=0 -DCMAKE_BUILD_TYPE=Release \
  -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF
cmake --build whisper.cpp/build-static -j --config Release

echo "Staging headers for the CWhisper module ..."
cp whisper.cpp/include/whisper.h src/CWhisper/include/
cp whisper.cpp/ggml/include/*.h src/CWhisper/include/

echo "Done. whisper.cpp $TAG (static, Metal) is built. Next: swift build"
