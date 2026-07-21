package com.margelo.nitro.nitroimagecolors

import android.annotation.SuppressLint
import android.content.res.Resources
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
import java.security.MessageDigest
import java.util.Collections
import androidx.core.graphics.get

@DoNotStrip
class NitroImageColors : HybridNitroImageColorsSpec() {

  companion object {
    // Default cap on the number of entries kept in the in-memory cache.
    // Can be overridden at runtime via `setMaxCacheSize`.
    private const val DEFAULT_MAX_CACHE_SIZE = 100

    // Long URIs get hashed (instead of truncated) once they exceed this length,
    // to avoid different URIs that share a prefix colliding on the same cache key.
    private const val LONG_URI_THRESHOLD = 500

    // Images are decoded at at most this size (on the longest side) since we only
    // ever need a small thumbnail to sample colors from.
    private const val MAX_DECODE_DIMENSION = 512

    @Volatile
    private var maxCacheSize = DEFAULT_MAX_CACHE_SIZE

    // LRU cache: least-recently-used entry is evicted once `maxCacheSize` is exceeded.
    // LinkedHashMap itself isn't thread-safe, so all access goes through the
    // synchronized wrapper below.
    private val cache: MutableMap<String, ImageColors> = Collections.synchronizedMap(
      object : LinkedHashMap<String, ImageColors>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, ImageColors>?): Boolean {
          return size > maxCacheSize
        }
      }
    )
  }

  override fun clearCache() {
    cache.clear()
  }

  override fun setMaxCacheSize(size: Double) {
    maxCacheSize = maxOf(1, size.toInt())
    // Shrinking the limit should evict immediately rather than waiting for the next write.
    synchronized(cache) {
      while (cache.size > maxCacheSize) {
        val oldestKey = cache.keys.firstOrNull() ?: break
        cache.remove(oldestKey)
      }
    }
  }

  private fun colorToHex(color: Int): String {
    return String.format("#%06X", 0xFFFFFF and color)
  }

  /**
   * Hashes a string with SHA-256. Used to build a collision-resistant automatic
   * cache key for long URIs instead of truncating them (which can collide when two
   * different URIs share a common prefix).
   */
  private fun sha256Hex(input: String): String {
    val bytes = MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8))
    return bytes.joinToString("") { "%02x".format(it) }
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

  /**
   * Computes the `inSampleSize` needed to decode an image whose bounds are
   * `options.outWidth`x`options.outHeight` down to roughly `reqWidth`x`reqHeight`.
   */
  private fun calculateInSampleSize(options: BitmapFactory.Options, reqWidth: Int, reqHeight: Int): Int {
    val height = options.outHeight
    val width = options.outWidth
    var inSampleSize = 1

    if (height > reqHeight || width > reqWidth) {
      val halfHeight = height / 2
      val halfWidth = width / 2

      while ((halfHeight / inSampleSize) >= reqHeight && (halfWidth / inSampleSize) >= reqWidth) {
        inSampleSize *= 2
      }
    }

    return inSampleSize
  }

  /**
   * Decodes a downsampled bitmap from an in-memory byte array using a
   * bounds-only pass to compute `inSampleSize` before the real decode, so the
   * full-resolution image is never held in memory.
   */
  private fun decodeSampledBitmapFromByteArray(data: ByteArray): Bitmap? {
    val boundsOptions = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(data, 0, data.size, boundsOptions)
    if (boundsOptions.outWidth <= 0 || boundsOptions.outHeight <= 0) return null

    val decodeOptions = BitmapFactory.Options().apply {
      inSampleSize = calculateInSampleSize(boundsOptions, MAX_DECODE_DIMENSION, MAX_DECODE_DIMENSION)
    }
    return BitmapFactory.decodeByteArray(data, 0, data.size, decodeOptions)
  }

  private fun decodeSampledBitmapFromFile(path: String): Bitmap? {
    val boundsOptions = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(path, boundsOptions)
    if (boundsOptions.outWidth <= 0 || boundsOptions.outHeight <= 0) return null

    val decodeOptions = BitmapFactory.Options().apply {
      inSampleSize = calculateInSampleSize(boundsOptions, MAX_DECODE_DIMENSION, MAX_DECODE_DIMENSION)
    }
    return BitmapFactory.decodeFile(path, decodeOptions)
  }

  private fun decodeSampledBitmapFromResource(resources: Resources, resId: Int): Bitmap? {
    val boundsOptions = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeResource(resources, resId, boundsOptions)
    if (boundsOptions.outWidth <= 0 || boundsOptions.outHeight <= 0) return null

    val decodeOptions = BitmapFactory.Options().apply {
      inSampleSize = calculateInSampleSize(boundsOptions, MAX_DECODE_DIMENSION, MAX_DECODE_DIMENSION)
    }
    return BitmapFactory.decodeResource(resources, resId, decodeOptions)
  }

  /**
   * Decodes a downsampled bitmap from a stream source that can be opened more
   * than once (e.g. assets), since a bounds-only pass must consume its own stream
   * before the real decode runs on a fresh one.
   */
  private fun decodeSampledBitmapFromStream(openStream: () -> InputStream?): Bitmap? {
    val boundsStream = openStream() ?: return null
    val boundsOptions = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    try {
      BitmapFactory.decodeStream(boundsStream, null, boundsOptions)
    } finally {
      boundsStream.close()
    }
    if (boundsOptions.outWidth <= 0 || boundsOptions.outHeight <= 0) return null

    val decodeStream = openStream() ?: return null
    val decodeOptions = BitmapFactory.Options().apply {
      inSampleSize = calculateInSampleSize(boundsOptions, MAX_DECODE_DIMENSION, MAX_DECODE_DIMENSION)
    }
    return try {
      BitmapFactory.decodeStream(decodeStream, null, decodeOptions)
    } finally {
      decodeStream.close()
    }
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

            try {
              // Add custom headers if provided
              config?.headers?.forEach { (key, value) ->
                connection.setRequestProperty(key, value)
              }

              connection.doInput = true
              connection.connect()

              // Buffer the response so we can do a bounds-only pass before the
              // real (downsampled) decode; a network stream can't be read twice.
              val bytes = connection.inputStream.use { it.readBytes() }
              decodeSampledBitmapFromByteArray(bytes)
            } finally {
              // Always release the connection, even if `connect()` or reading
              // the stream throws.
              connection.disconnect()
            }
          }

          uri.startsWith("file://") -> {
            // Local file URL
            val path = uri.substring(7) // Remove "file://"
            decodeSampledBitmapFromFile(path)
          }

          uri.startsWith("/") -> {
            // Absolute file path
            decodeSampledBitmapFromFile(uri)
          }

          else -> {
            // Try as asset or resource
            try {
              NitroModules.applicationContext?.let { ctx ->
                decodeSampledBitmapFromStream { ctx.assets.open(uri) }
              }
            } catch (_: Exception) {
              NitroModules.applicationContext?.let { ctx ->
                val resourceId = ctx.resources.getIdentifier(
                  uri.substringBeforeLast('.'),
                  "drawable",
                  ctx.packageName
                )
                if (resourceId != 0) {
                  decodeSampledBitmapFromResource(ctx.resources, resourceId)
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

  private suspend fun extractColorsFromBitmap(bitmap: Bitmap, config: Config?): ImageColors {
    // Pixel loops + Palette.generate() are CPU-bound, so keep them off the
    // IO dispatcher used for loading and run them on the CPU-bound one instead.
    return withContext(Dispatchers.Default) {
      val pixelSpacing = maxOf(1, config?.pixelSpacing?.toInt() ?: 1)

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

      ImageColors(
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
  }

  private fun fallbackResult(fallbackHex: String): ImageColors {
    return ImageColors(
      background = null,
      primary = null,
      secondary = null,
      detail = null,
      dominant = fallbackHex,
      average = fallbackHex,
      vibrant = fallbackHex,
      darkVibrant = fallbackHex,
      lightVibrant = fallbackHex,
      darkMuted = fallbackHex,
      lightMuted = fallbackHex,
      muted = fallbackHex,
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
          val customKey = config?.key
          when {
            !customKey.isNullOrEmpty() -> customKey
            uri.value.uri.length > LONG_URI_THRESHOLD -> "sha256_${sha256Hex(uri.value.uri)}"
            else -> uri.value.uri
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
          NitroModules.applicationContext?.let { ctx ->
            val resourceId = uri.value.toInt()
            decodeSampledBitmapFromResource(ctx.resources, resourceId)
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
        fallbackResult(fallbackHex)
      }

      // Only cache successful extractions: caching fallback/error results would
      // otherwise permanently "poison" that cache key until app restart.
      if (config?.cache == true && bitmap != null) {
        cache[cacheKey] = result
      }

      result
    }
  }
}
