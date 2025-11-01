package com.margelo.nitro.nitroimagecolors
  
import com.facebook.proguard.annotations.DoNotStrip

@DoNotStrip
class NitroImageColors : HybridNitroImageColorsSpec() {
  override fun multiply(a: Double, b: Double): Double {
    return a * b
  }
}
