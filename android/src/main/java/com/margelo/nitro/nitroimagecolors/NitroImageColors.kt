package com.margelo.nitro.nitroimagecolors

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import androidx.palette.graphics.Palette
import com.facebook.proguard.annotations.DoNotStrip
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.Promise
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import androidx.core.graphics.get

@DoNotStrip
class NitroImageColors : HybridNitroImageColorsSpec() {

  companion object {
    private val cache = ConcurrentHashMap<String, ImageColors>()
  }

  private fun colorToHex(color: Int): String {
    return String.format("#%06X", 0xFFFFFF and color)
  }

  private fun calculateAverageColor(bitmap: Bitmap, pixelSpacing: Int = 1): Int {
    var redSum = 0L
    var greenSum = 0L
    var blueSum = 0L
    var pixelCount = 0

    val width = bitmap.width
    val height = bitmap.height

    for (y in 0 until height step pixelSpacing) {
      for (x in 0 until width step pixelSpacing) {
        val pixel = bitmap[x, y]
        val alpha = Color.alpha(pixel)

        // Skip transparent pixels
        if (alpha < 128) continue

        redSum += Color.red(pixel)
        greenSum += Color.green(pixel)
        blueSum += Color.blue(pixel)
        pixelCount++
      }
    }

    return if (pixelCount > 0) {
      Color.rgb(
        (redSum / pixelCount).toInt(),
        (greenSum / pixelCount).toInt(),
        (blueSum / pixelCount).toInt()
      )
    } else {
      Color.BLACK
    }
  }

  private fun findDominantColor(bitmap: Bitmap): Int {
    val colorCounts = mutableMapOf<Int, Int>()
    val width = bitmap.width
    val height = bitmap.height

    // Sample pixels for performance
    val sampleRate = maxOf(1, (width * height) / 10000)

    for (y in 0 until height step sampleRate) {
      for (x in 0 until width step sampleRate) {
        val pixel = bitmap[x, y]
        val alpha = Color.alpha(pixel)

        // Skip transparent pixels
        if (alpha < 128) continue

        // Quantize color to reduce noise
        val quantizedColor = Color.rgb(
          (Color.red(pixel) / 32) * 32,
          (Color.green(pixel) / 32) * 32,
          (Color.blue(pixel) / 32) * 32
        )

        colorCounts[quantizedColor] = colorCounts.getOrDefault(quantizedColor, 0) + 1
      }
    }

    return colorCounts.maxByOrNull { it.value }?.key ?: Color.BLACK
  }

  @SuppressLint("DiscouragedApi")
  private suspend fun loadBitmapFromUri(uri: String, config: Config?): Bitmap? {
    return withContext(Dispatchers.IO) {
      try {
        when {
          uri.startsWith("http://") || uri.startsWith("https://") -> {
            // Remote URL
            val url = URL(uri)
            val connection = url.openConnection() as HttpURLConnection

            // Add custom headers if provided
            config?.headers?.forEach { (key, value) ->
              connection.setRequestProperty(key, value)
            }

            connection.doInput = true
            connection.connect()

            val inputStream: InputStream = connection.inputStream
            val bitmap = BitmapFactory.decodeStream(inputStream)
            inputStream.close()
            connection.disconnect()
            bitmap
          }

          uri.startsWith("file://") -> {
            // Local file URL
            val path = uri.substring(7) // Remove "file://"
            BitmapFactory.decodeFile(path)
          }

          uri.startsWith("/") -> {
            // Absolute file path
            BitmapFactory.decodeFile(uri)
          }

          else -> {
            // Try as asset or resource
            try {
              NitroModules.applicationContext.let { ctx ->

                val inputStream = ctx?.assets?.open(uri)
                val bitmap = BitmapFactory.decodeStream(inputStream)
                inputStream?.close()
                bitmap
              }

            } catch (_: Exception) {
              NitroModules.applicationContext?.let { ctx ->
                val resourceId = ctx.resources.getIdentifier(
                  uri.substringBeforeLast('.'),
                  "drawable",
                  ctx.packageName
                )
                if (resourceId != 0) {
                  BitmapFactory.decodeResource(ctx.resources, resourceId)
                } else {
                  null
                }
              }
            }
          }
        }
      } catch (_: Exception) {
        null
      }
    }
  }

  private fun extractColorsFromBitmap(bitmap: Bitmap, config: Config?): ImageColors {
    val pixelSpacing = config?.pixelSpacing?.toInt() ?: 1

    // Calculate colors
    val averageColor = calculateAverageColor(bitmap, pixelSpacing)
    val dominantColor = findDominantColor(bitmap)

    // Use Palette library for advanced color extraction
    val palette = Palette.from(bitmap).generate()

    val vibrantSwatch = palette.vibrantSwatch
    val darkVibrantSwatch = palette.darkVibrantSwatch
    val lightVibrantSwatch = palette.lightVibrantSwatch
    val mutedSwatch = palette.mutedSwatch
    val darkMutedSwatch = palette.darkMutedSwatch
    val lightMutedSwatch = palette.lightMutedSwatch

    return ImageColors(
      background = null,
      primary = null,
      secondary = null,
      detail = null,
      dominant = colorToHex(dominantColor),
      average = colorToHex(averageColor),
      vibrant = vibrantSwatch?.let { colorToHex(it.rgb) },
      darkVibrant = darkVibrantSwatch?.let { colorToHex(it.rgb) },
      lightVibrant = lightVibrantSwatch?.let { colorToHex(it.rgb) },
      darkMuted = darkMutedSwatch?.let { colorToHex(it.rgb) },
      lightMuted = lightMutedSwatch?.let { colorToHex(it.rgb) },
      muted = mutedSwatch?.let { colorToHex(it.rgb) },
      platform = "android"
    )
  }

  override fun getColors(
    uri: Variant_Double_ImageSourcePropType,
    config: Config?
  ): Promise<ImageColors> {
    return Promise.async {
      val fallbackHex = config?.fallback ?: "#000000"

      // Generate cache key
      val cacheKey = when (uri) {
        is Variant_Double_ImageSourcePropType.First -> "resource_${uri.value}"
        is Variant_Double_ImageSourcePropType.Second -> {
          config?.key ?: if (uri.value.uri.length > 500) {
            uri.value.uri.take(500)
          } else {
            uri.value.uri
          }
        }
      }

      // Check cache if enabled
      if (config?.cache == true) {
        cache[cacheKey]?.let { return@async it }
      }

      // Load bitmap
      val bitmap = when (uri) {
        is Variant_Double_ImageSourcePropType.First -> {
          NitroModules.applicationContext.let { ctx->
            val resourceId = uri.value.toInt()
            BitmapFactory.decodeResource(ctx?.resources, resourceId)
          }

        }
        is Variant_Double_ImageSourcePropType.Second -> {
          loadBitmapFromUri(uri.value.uri, config)
        }
      }

      val result = if (bitmap != null) {
        extractColorsFromBitmap(bitmap, config)
      } else {
        // Return fallback colors
        ImageColors(
          background = null,
          primary = null,
          secondary = null,
          detail = null,
          dominant = fallbackHex,
          average = fallbackHex,
          vibrant = fallbackHex,
          darkVibrant = null,
          lightVibrant = null,
          darkMuted = null,
          lightMuted = null,
          muted = null,
          platform = "android"
        )
      }

      // Cache result if enabled
      if (config?.cache == true) {
        cache[cacheKey] = result
      }

      result
    }
  }
}
