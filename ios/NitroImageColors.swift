import Foundation
import UIKit
import NitroModules
import React

class NitroImageColors: HybridNitroImageColorsSpec {
  private static var cache: [String: ImageColors] = [:]
  private static let cacheQueue = DispatchQueue(label: "com.margelo.nitro.nitroimagecolors.cache", attributes: .concurrent)
  
  private func hexString(from color: UIColor) -> String {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    color.getRed(&r, green: &g, blue: &b, alpha: &a)
    return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
  }

  private func adjustColor(_ color: UIColor, amount: CGFloat) -> UIColor {
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    if color.getHue(&h, saturation: &s, brightness: &b, alpha: &a) {
      return UIColor(hue: h, saturation: s, brightness: max(0, min(1, b + amount)), alpha: a)
    }
    return color
  }

  private func extractDominantColors(from image: UIImage) -> (background: UIColor, primary: UIColor, secondary: UIColor, detail: UIColor) {
     guard image.cgImage != nil else {
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
    let context = CGContext(
      data: &pixelData,
      width: width,
      height: height,
      bitsPerComponent: bitsPerComponent,
      bytesPerRow: bytesPerRow,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    
    context?.draw(resizedCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    
    var colorCounts: [String: Int] = [:]
    var totalPixels = 0
    var redSum: CGFloat = 0
    var greenSum: CGFloat = 0
    var blueSum: CGFloat = 0
    
    for y in 0..<height {
      for x in 0..<width {
        let pixelIndex = (y * width + x) * bytesPerPixel
        let red = CGFloat(pixelData[pixelIndex]) / 255.0
        let green = CGFloat(pixelData[pixelIndex + 1]) / 255.0
        let blue = CGFloat(pixelData[pixelIndex + 2]) / 255.0
        let alpha = CGFloat(pixelData[pixelIndex + 3]) / 255.0
        
        if alpha < 0.5 { continue }
        
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
    
    let avgRed = totalPixels > 0 ? redSum / CGFloat(totalPixels) : 0
    let avgGreen = totalPixels > 0 ? greenSum / CGFloat(totalPixels) : 0
    let avgBlue = totalPixels > 0 ? blueSum / CGFloat(totalPixels) : 0
    let backgroundColor = UIColor(red: avgRed, green: avgGreen, blue: avgBlue, alpha: 1.0)
    
    let sortedColors = colorCounts.sorted { $0.value > $1.value }
    
    var primaryColor = backgroundColor
    var secondaryColor = backgroundColor
    var detailColor = backgroundColor
    
    if sortedColors.count > 0 {
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
    
    detailColor = adjustColor(primaryColor, amount: 0.3)
    
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
      let resourceName = "image_\(Int(resourceId))"
      return UIImage(named: resourceName)
      
    case let .second(source):
      let uri = source.uri
      
      if uri.hasPrefix("http://") || uri.hasPrefix("https://") {
        guard let url = URL(string: uri) else { return nil }
        
        var request = URLRequest(url: url)
        if let headers = config?.headers {
          for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
          }
        }
        
        do {
          let (data, _) = try await URLSession.shared.data(for: request)
          return UIImage(data: data)
        } catch {
          return nil
        }
      } else if uri.hasPrefix("file://") {
        let path = String(uri.dropFirst(7))
        return UIImage(contentsOfFile: path)
      } else if FileManager.default.fileExists(atPath: uri) {
        return UIImage(contentsOfFile: uri)
      } else {
        return UIImage(named: uri)
      }
    }
  }

  func getColors(uri: Variant_Double_ImageSourcePropType, config: Config?) throws -> NitroModules.Promise<ImageColors> {
    return NitroModules.Promise.async {
      let fallbackHex = config?.fallback ?? "#000000"
      
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
      
      if config?.cache == true {
        let cachedResult = Self.cacheQueue.sync {
          return Self.cache[cacheKey]
        }
        if let cachedResult = cachedResult {
          return cachedResult
        }
      }
      
      guard let image = await self.loadImage(from: uri, config: config) else {
        return ImageColors(
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
      }
      
      let colors = self.extractDominantColors(from: image)
      
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
      
      if config?.cache == true {
        Self.cacheQueue.async(flags: .barrier) {
          Self.cache[cacheKey] = result
        }
      }
      
      return result
    }
  }
}
