import Foundation
import UIKit
import NitroModules

class NitroImageColors: HybridNitroImageColorsSpec {
  private static var cache: [String: ImageColors] = [:]
  private static let cacheQueue = DispatchQueue(label: "com.margelo.nitro.nitroimagecolors.cache", attributes: .concurrent)
  
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

  private func extractColorsFromImage(_ image: UIImage) -> (background: UIColor, primary: UIColor, secondary: UIColor, detail: UIColor) {
    guard let cgImage = image.cgImage else {
      return (UIColor.black, UIColor.black, UIColor.black, UIColor.black)
    }
    
    let targetSize = CGSize(width: 150, height: 150)
    let resizedImage = resizeImage(image, to: targetSize)
    guard let resizedCGImage = resizedImage.cgImage else {
      return (UIColor.black, UIColor.black, UIColor.black, UIColor.black)
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
      return (UIColor.black, UIColor.black, UIColor.black, UIColor.black)
    }
    
    context.draw(resizedCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    
    var colorCounts: [String: Int] = [:]
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
        colorCounts[colorKey, default: 0] += 1
        
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
    
    // Find dominant colors
    let sortedColors = colorCounts.sorted { $0.value > $1.value }
    
    var primaryColor = backgroundColor
    var secondaryColor = backgroundColor
    
    if !sortedColors.isEmpty {
      let primaryComponents = sortedColors[0].key.split(separator: ",")
      if primaryComponents.count == 3 {
        primaryColor = UIColor(
          red: CGFloat(Int(primaryComponents[0]) ?? 0) / 255.0,
          green: CGFloat(Int(primaryComponents[1]) ?? 0) / 255.0,
          blue: CGFloat(Int(primaryComponents[2]) ?? 0) / 255.0,
          alpha: 1.0
        )
      }
    }
    
    if sortedColors.count > 1 {
      let secondaryComponents = sortedColors[1].key.split(separator: ",")
      if secondaryComponents.count == 3 {
        secondaryColor = UIColor(
          red: CGFloat(Int(secondaryComponents[0]) ?? 0) / 255.0,
          green: CGFloat(Int(secondaryComponents[1]) ?? 0) / 255.0,
          blue: CGFloat(Int(secondaryComponents[2]) ?? 0) / 255.0,
          alpha: 1.0
        )
      }
    }
    
    // Detail color is a darker version of primary
    let detailColor = adjustBrightness(primaryColor, amount: -0.3)
    
    return (backgroundColor, primaryColor, secondaryColor, detailColor)
  }
  
  private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage {
    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
    image.draw(in: CGRect(origin: .zero, size: size))
    let resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
    UIGraphicsEndImageContext()
    return resizedImage
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
          
          return UIImage(data: data)
        } catch {
          return nil
        }
      } else if uriString.hasPrefix("file://") {
        // Local file URL
        let path = String(uriString.dropFirst(7))
        return UIImage(contentsOfFile: path)
      } else if uriString.hasPrefix("/") {
        // Absolute file path
        return UIImage(contentsOfFile: uriString)
      } else {
        // Try as bundle resource
        return UIImage(named: uriString)
      }
    }
  }

  func getColors(uri: Variant_Double_ImageSourcePropType, config: Config?) throws -> NitroModules.Promise<ImageColors> {
    return NitroModules.Promise.async {
      let fallbackHex = config?.fallback ?? "#000000"
      
      // Generate cache key
      let cacheKey: String
      if let customKey = config?.key {
        cacheKey = customKey
      } else {
        switch uri {
        case let .first(resourceId):
          cacheKey = "resource_\(resourceId)"
        case let .second(source):
          cacheKey = source.uri.count > 500 ? String(source.uri.prefix(500)) : source.uri
        }
      }
      
      // Check cache if enabled
      if config?.cache == true {
        let cachedResult = Self.cacheQueue.sync {
          return Self.cache[cacheKey]
        }
        if let cachedResult = cachedResult {
          return cachedResult
        }
      }
      
      // Load image
      guard let image = await self.loadImage(from: uri, config: config) else {
        let fallbackResult = ImageColors(
          background: fallbackHex,
          primary: fallbackHex,
          secondary: fallbackHex,
          detail: fallbackHex,
          dominant: nil,
          average: nil,
          vibrant: nil,
          darkVibrant: nil,
          lightVibrant: nil,
          darkMuted: nil,
          lightMuted: nil,
          muted: nil,
          platform: "ios"
        )
        
        // Cache fallback result if caching is enabled
        if config?.cache == true {
          Self.cacheQueue.async(flags: .barrier) {
            Self.cache[cacheKey] = fallbackResult
          }
        }
        
        return fallbackResult
      }
      
      // Extract colors
      let colors = self.extractColorsFromImage(image)
      
      let result = ImageColors(
        background: self.hexString(from: colors.background),
        primary: self.hexString(from: colors.primary),
        secondary: self.hexString(from: colors.secondary),
        detail: self.hexString(from: colors.detail),
        dominant: nil,
        average: nil,
        vibrant: nil,
        darkVibrant: nil,
        lightVibrant: nil,
        darkMuted: nil,
        lightMuted: nil,
        muted: nil,
        platform: "ios"
      )
      
      // Cache result if enabled
      if config?.cache == true {
        Self.cacheQueue.async(flags: .barrier) {
          Self.cache[cacheKey] = result
        }
      }
      
      return result
    }
  }
}
