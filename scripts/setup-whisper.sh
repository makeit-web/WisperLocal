#!/bin/bash
# Fetch + build whisper.cpp (static, Metal) pinned to v1.9.1, and stage the
# headers the CWhisper SwiftPM module needs. Run from anywhere; operates on the
# repo root. Idempotent. Prerequisite for `swift build`.
set -e
cd "$(dirname "$0")/.." || exit 1

TAG=v1.9.1
REPO=https://github.com/ggml-org/whisper.cpp

if [ ! -d whisper.cpp ]; then
  echo "Cloning whisper.cpp $TAG ..."
  git clone --depth 1 --branch "$TAG" "$REPO" whisper.cpp
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
