import Foundation
import UIKit
import CryptoKit
import NitroModules

class NitroImageColors: HybridNitroImageColorsSpec {
  private static var cache: [String: ImageColors] = [:]
  // Insertion order of `cache` keys, oldest first — used to evict the oldest
  // entry once `maxCacheSize` is exceeded.
  private static var cacheOrder: [String] = []
  private static let cacheQueue = DispatchQueue(label: "com.margelo.nitro.nitroimagecolors.cache", attributes: .concurrent)

  // Default cap on the number of entries kept in the in-memory cache.
  // Can be overridden at runtime via `setMaxCacheSize`.
  private static let defaultMaxCacheSize = 100
  private static var maxCacheSize = defaultMaxCacheSize

  // Long URIs get hashed (instead of truncated) once they exceed this length,
  // to avoid different URIs that share a prefix colliding on the same cache key.
  private static let longUriThreshold = 500

  // Images are decoded at at most this size (on the longest side) since we only
  // ever need a small thumbnail to sample colors from.
  private static let maxThumbnailPixelSize: CGFloat = 512

  private func hexString(from color: UIColor) -> String {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    color.getRed(&r, green: &g, blue: &b, alpha: &a)
    return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
  }

  private func adjustBrightness(_ color: UIColor, amount: CGFloat) -> UIColor {
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    if color.getHue(&h, saturation: &s, brightness: &b, alpha: &a) {
      return UIColor(hue: h, saturation: s, brightness: max(0, min(1, b + amount)), alpha: a)
    }
    return color
  }

  private func adjustSaturation(_ color: UIColor, amount: CGFloat) -> UIColor {
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    if color.getHue(&h, saturation: &s, brightness: &b, alpha: &a) {
      return UIColor(hue: h, saturation: max(0, min(1, s + amount)), brightness: b, alpha: a)
    }
    return color
  }

  /// Converts sRGB (0...1) components to HSL (0...1) — used to bucket pixels
  /// into vibrant/muted/dark/light swatches, similar in spirit to how Android's
  /// Palette library classifies its swatches.
  private func rgbToHsl(red: CGFloat, green: CGFloat, blue: CGFloat) -> (saturation: CGFloat, lightness: CGFloat) {
    let maxV = max(red, green, blue)
    let minV = min(red, green, blue)
    let lightness = (maxV + minV) / 2

    guard maxV != minV else {
      return (0, lightness)
    }

    let delta = maxV - minV
    let saturation = lightness > 0.5 ? delta / (2 - maxV - minV) : delta / (maxV + minV)
    return (saturation, lightness)
  }

  private struct SwatchCandidate {
    let color: UIColor
    let saturation: CGFloat
    let lightness: CGFloat
    let population: Int
  }

  /// Picks the candidate that best matches a target (lightness, saturation) pair,
  /// weighting population the same way Android's Palette `Target` scoring does.
  /// Returns `nil` when there is no reasonable (non near-black/near-white) candidate.
  private func bestSwatch(
    from candidates: [SwatchCandidate],
    targetLightness: CGFloat,
    targetSaturation: CGFloat,
    maxPopulation: Int
  ) -> UIColor? {
    guard maxPopulation > 0 else { return nil }

    let weightSaturation: CGFloat = 0.24
    let weightLuma: CGFloat = 0.52
    let weightPopulation: CGFloat = 0.24

    var best: SwatchCandidate?
    var bestScore: CGFloat = -1

    for candidate in candidates {
      // Ignore near-black/near-white candidates as representative swatches —
      // they rarely make useful "vibrant"/"muted" colors.
      if candidate.lightness < 0.03 || candidate.lightness > 0.97 { continue }

      let score =
        weightSaturation * (1 - abs(candidate.saturation - targetSaturation)) +
        weightLuma * (1 - abs(candidate.lightness - targetLightness)) +
        weightPopulation * (CGFloat(candidate.population) / CGFloat(maxPopulation))

      if score > bestScore {
        bestScore = score
        best = candidate
      }
    }

    return best?.color
  }

  private struct ExtractedPalette {
    let background: UIColor
    let primary: UIColor
    let secondary: UIColor
    let detail: UIColor
    let dominant: UIColor
    let average: UIColor
    let vibrant: UIColor?
    let darkVibrant: UIColor?
    let lightVibrant: UIColor?
    let muted: UIColor?
    let darkMuted: UIColor?
    let lightMuted: UIColor?
  }

  private func extractColorsFromImage(_ image: UIImage) -> ExtractedPalette {
    // `image` is already a small thumbnail (see `createThumbnail`), so this
    // resize is cheap — it just standardizes the working size for the pixel loop.
    let targetSize = CGSize(width: 150, height: 150)
    let resizedImage = resizeImage(image, to: targetSize)
    guard let resizedCGImage = resizedImage.cgImage ?? image.cgImage else {
      let black = UIColor.black
      return ExtractedPalette(
        background: black, primary: black, secondary: black, detail: black,
        dominant: black, average: black,
        vibrant: nil, darkVibrant: nil, lightVibrant: nil,
        muted: nil, darkMuted: nil, lightMuted: nil
      )
    }

    let width = resizedCGImage.width
    let height = resizedCGImage.height
    let bytesPerPixel = 4
    let bytesPerRow = bytesPerPixel * width
    let bitsPerComponent = 8

    var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
      data: &pixelData,
      width: width,
      height: height,
      bitsPerComponent: bitsPerComponent,
      bytesPerRow: bytesPerRow,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      let black = UIColor.black
      return ExtractedPalette(
        background: black, primary: black, secondary: black, detail: black,
        dominant: black, average: black,
        vibrant: nil, darkVibrant: nil, lightVibrant: nil,
        muted: nil, darkMuted: nil, lightMuted: nil
      )
    }

    context.draw(resizedCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    // Bucket key -> (rgb sums, population) so we can recover a representative
    // color for each quantized bucket further down.
    var colorCounts: [String: (red: CGFloat, green: CGFloat, blue: CGFloat, count: Int)] = [:]
    var totalPixels = 0
    var redSum: CGFloat = 0
    var greenSum: CGFloat = 0
    var blueSum: CGFloat = 0

    let pixelSpacing = 1

    for y in stride(from: 0, to: height, by: pixelSpacing) {
      for x in stride(from: 0, to: width, by: pixelSpacing) {
        let pixelIndex = (y * width + x) * bytesPerPixel
        let red = CGFloat(pixelData[pixelIndex]) / 255.0
        let green = CGFloat(pixelData[pixelIndex + 1]) / 255.0
        let blue = CGFloat(pixelData[pixelIndex + 2]) / 255.0
        let alpha = CGFloat(pixelData[pixelIndex + 3]) / 255.0

        if alpha < 0.5 { continue }

        // Quantize colors to reduce noise
        let quantizedRed = Int(red * 8) * 32
        let quantizedGreen = Int(green * 8) * 32
        let quantizedBlue = Int(blue * 8) * 32

        let colorKey = "\(quantizedRed),\(quantizedGreen),\(quantizedBlue)"
        var bucket = colorCounts[colorKey] ?? (0, 0, 0, 0)
        bucket.red += red
        bucket.green += green
        bucket.blue += blue
        bucket.count += 1
        colorCounts[colorKey] = bucket

        redSum += red
        greenSum += green
        blueSum += blue
        totalPixels += 1
      }
    }

    // Calculate average color (background)
    let avgRed = totalPixels > 0 ? redSum / CGFloat(totalPixels) : 0
    let avgGreen = totalPixels > 0 ? greenSum / CGFloat(totalPixels) : 0
    let avgBlue = totalPixels > 0 ? blueSum / CGFloat(totalPixels) : 0
    let backgroundColor = UIColor(red: avgRed, green: avgGreen, blue: avgBlue, alpha: 1.0)

    // Build one representative (averaged) candidate color per quantized bucket.
    let candidates: [SwatchCandidate] = colorCounts.values.map { bucket in
      let r = bucket.red / CGFloat(bucket.count)
      let g = bucket.green / CGFloat(bucket.count)
      let b = bucket.blue / CGFloat(bucket.count)
      let (saturation, lightness) = rgbToHsl(red: r, green: g, blue: b)
      return SwatchCandidate(
        color: UIColor(red: r, green: g, blue: b, alpha: 1.0),
        saturation: saturation,
        lightness: lightness,
        population: bucket.count
      )
    }

    let maxPopulation = candidates.map { $0.population }.max() ?? 0
    let sortedByPopulation = candidates.sorted { $0.population > $1.population }

    // "Dominant" == most populous bucket; "primary"/"secondary" mirror the
    // previous iOS-only algorithm using the same sorted buckets.
    let dominantColor = sortedByPopulation.first?.color ?? backgroundColor
    var primaryColor = backgroundColor
    var secondaryColor = backgroundColor

    if sortedByPopulation.count > 0 {
      primaryColor = sortedByPopulation[0].color
    }
    if sortedByPopulation.count > 1 {
      secondaryColor = sortedByPopulation[1].color
    }

    // Detail color is a darker version of primary
    let detailColor = adjustBrightness(primaryColor, amount: -0.3)

    // Vibrant/muted swatches, bucketed by target lightness/saturation the same
    // way Android's Palette library scores its targets.
    let vibrant = bestSwatch(from: candidates, targetLightness: 0.5, targetSaturation: 1.0, maxPopulation: maxPopulation)
    let lightVibrant = bestSwatch(from: candidates, targetLightness: 0.74, targetSaturation: 1.0, maxPopulation: maxPopulation)
    let darkVibrant = bestSwatch(from: candidates, targetLightness: 0.26, targetSaturation: 1.0, maxPopulation: maxPopulation)
    let muted = bestSwatch(from: candidates, targetLightness: 0.5, targetSaturation: 0.3, maxPopulation: maxPopulation)
    let lightMuted = bestSwatch(from: candidates, targetLightness: 0.74, targetSaturation: 0.3, maxPopulation: maxPopulation)
    let darkMuted = bestSwatch(from: candidates, targetLightness: 0.26, targetSaturation: 0.3, maxPopulation: maxPopulation)

    return ExtractedPalette(
      background: backgroundColor,
      primary: primaryColor,
      secondary: secondaryColor,
      detail: detailColor,
      dominant: dominantColor,
      average: backgroundColor,
      vibrant: vibrant,
      darkVibrant: darkVibrant,
      lightVibrant: lightVibrant,
      muted: muted,
      darkMuted: darkMuted,
      lightMuted: lightMuted
    )
  }

  private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage {
    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
    image.draw(in: CGRect(origin: .zero, size: size))
    let resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
    UIGraphicsEndImageContext()
    return resizedImage
  }

  /// Generates a small thumbnail directly from a `CGImageSource`, without ever
  /// decoding the source image at full resolution — avoids the memory spike a
  /// full decode + resize would cause on large photos.
  private func thumbnail(from source: CGImageSource) -> UIImage? {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: Self.maxThumbnailPixelSize,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceCreateThumbnailWithTransform: true
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      return nil
    }
    return UIImage(cgImage: cgImage)
  }

  private func createThumbnail(from data: Data) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return thumbnail(from: source)
  }

  private func createThumbnail(atPath path: String) -> UIImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return thumbnail(from: source)
  }

  private func loadImage(from uri: Variant_Double_ImageSourcePropType, config: Config?) async -> UIImage? {
    switch uri {
    case let .first(resourceId):
      // Handle resource ID - try different naming patterns
      let resourceName = "image_\(Int(resourceId))"
      if let image = UIImage(named: resourceName) {
        return image
      }
      // Try direct resource ID
      return UIImage(named: String(Int(resourceId)))

    case let .second(source):
      let uriString = source.uri

      if uriString.hasPrefix("http://") || uriString.hasPrefix("https://") {
        // Remote URL
        guard let url = URL(string: uriString) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30.0

        // Add custom headers
        if let headers = config?.headers {
          for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
          }
        }

        do {
          let (data, response) = try await URLSession.shared.data(for: request)

          // Check response status
          if let httpResponse = response as? HTTPURLResponse,
             httpResponse.statusCode >= 400 {
            return nil
          }

          // Decode straight to a small thumbnail instead of fully decoding the
          // (potentially huge) source image first.
          return createThumbnail(from: data)
        } catch {
          return nil
        }
      } else if uriString.hasPrefix("file://") {
        // Local file URL
        let path = String(uriString.dropFirst(7))
        return createThumbnail(atPath: path)
      } else if uriString.hasPrefix("/") {
        // Absolute file path
        return createThumbnail(atPath: uriString)
      } else {
        // Try as bundle resource
        return UIImage(named: uriString)
      }
    }
  }

  private static func cacheGet(_ key: String) -> ImageColors? {
    return cacheQueue.sync { cache[key] }
  }

  private static func cacheSet(_ key: String, _ value: ImageColors) {
    cacheQueue.async(flags: .barrier) {
      if cache[key] == nil {
        cacheOrder.append(key)
      }
      cache[key] = value

      // Evict the oldest entries once we're over the configured limit.
      while cache.count > maxCacheSize, !cacheOrder.isEmpty {
        let oldestKey = cacheOrder.removeFirst()
        cache.removeValue(forKey: oldestKey)
      }
    }
  }

  func clearCache() throws {
    Self.cacheQueue.async(flags: .barrier) {
      Self.cache.removeAll()
      Self.cacheOrder.removeAll()
    }
  }

  func setMaxCacheSize(size: Double) throws {
    let clamped = max(1, Int(size))
    Self.cacheQueue.async(flags: .barrier) {
      Self.maxCacheSize = clamped
      while Self.cache.count > Self.maxCacheSize, !Self.cacheOrder.isEmpty {
        let oldestKey = Self.cacheOrder.removeFirst()
        Self.cache.removeValue(forKey: oldestKey)
      }
    }
  }

  /// Hashes a string with SHA-256 (hex-encoded). Used to build a collision-resistant
  /// automatic cache key for long URIs instead of truncating them (which can collide
  /// when two different URIs share a common prefix).
  private func sha256Hex(_ input: String) -> String {
    let digest = SHA256.hash(data: Data(input.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  func getColors(uri: Variant_Double_ImageSourcePropType, config: Config?) throws -> NitroModules.Promise<ImageColors> {
    return NitroModules.Promise.async {
      let fallbackHex = config?.fallback ?? "#000000"

      // Generate cache key
      let cacheKey: String
      if let customKey = config?.key, !customKey.isEmpty {
        cacheKey = customKey
      } else {
        switch uri {
        case let .first(resourceId):
          cacheKey = "resource_\(resourceId)"
        case let .second(source):
          if source.uri.count > Self.longUriThreshold {
            cacheKey = "sha256_\(self.sha256Hex(source.uri))"
          } else {
            cacheKey = source.uri
          }
        }
      }

      // Check cache if enabled
      if config?.cache == true, let cachedResult = Self.cacheGet(cacheKey) {
        return cachedResult
      }

      // Load image
      guard let image = await self.loadImage(from: uri, config: config) else {
        // Fallback fills the same fields success does, so consumers see a
        // consistent shape regardless of success/failure. Not cached: a
        // transient failure (e.g. network blip) must not permanently poison
        // this cache key.
        return ImageColors(
          background: fallbackHex,
          primary: fallbackHex,
          secondary: fallbackHex,
          detail: fallbackHex,
          dominant: fallbackHex,
          average: fallbackHex,
          vibrant: fallbackHex,
          darkVibrant: fallbackHex,
          lightVibrant: fallbackHex,
          darkMuted: fallbackHex,
          lightMuted: fallbackHex,
          muted: fallbackHex,
          platform: "ios"
        )
      }

      // Extract colors
      let palette = self.extractColorsFromImage(image)

      let result = ImageColors(
        background: self.hexString(from: palette.background),
        primary: self.hexString(from: palette.primary),
        secondary: self.hexString(from: palette.secondary),
        detail: self.hexString(from: palette.detail),
        dominant: self.hexString(from: palette.dominant),
        average: self.hexString(from: palette.average),
        vibrant: palette.vibrant.map { self.hexString(from: $0) },
        darkVibrant: palette.darkVibrant.map { self.hexString(from: $0) },
        lightVibrant: palette.lightVibrant.map { self.hexString(from: $0) },
        darkMuted: palette.darkMuted.map { self.hexString(from: $0) },
        lightMuted: palette.lightMuted.map { self.hexString(from: $0) },
        muted: palette.muted.map { self.hexString(from: $0) },
        platform: "ios"
      )

      // Cache result if enabled
      if config?.cache == true {
        Self.cacheSet(cacheKey, result)
      }

      return result
    }
  }
}
