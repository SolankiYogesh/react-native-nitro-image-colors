#include <jni.h>
#include "nitroimagecolorsOnLoad.hpp"

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
  return margelo::nitro::nitroimagecolors::initialize(vm);
}
