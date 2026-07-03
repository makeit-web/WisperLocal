/* Compilation unit so SwiftPM treats CWhisper as a buildable C target.
   The public interface is whisper.h (see include/module.modulemap); the actual
   symbols come from the statically linked whisper.cpp libraries. */
#include "whisper.h"
