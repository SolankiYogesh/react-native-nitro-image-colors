# 🎨 React Native Nitro Image Colors

[![npm version](https://img.shields.io/npm/v/react-native-nitro-image-colors.svg?style=flat-square)](https://www.npmjs.com/package/react-native-nitro-image-colors)
[![npm downloads](https://img.shields.io/npm/dm/react-native-nitro-image-colors.svg?style=flat-square)](https://www.npmjs.com/package/react-native-nitro-image-colors)
[![license](https://img.shields.io/npm/l/react-native-nitro-image-colors.svg?style=flat-square)](https://github.com/SolankiYogesh/react-native-nitro-image-colors/blob/main/LICENSE)
[![platforms](https://img.shields.io/badge/platforms-Android%20%7C%20iOS-brightgreen.svg?style=flat-square)](https://github.com/SolankiYogesh/react-native-nitro-image-colors)

A high-performance React Native library for extracting prominent colors from images. Built with [Nitro Modules](https://nitro.margelo.com/) for optimal performance on both iOS and Android.

## ✨ Features

- **🚀 High Performance**: Native implementation using Kotlin and Swift
- **🎯 Accurate Color Extraction**: Advanced algorithms for precise color detection
- **📱 Cross-Platform**: Consistent API across iOS and Android
- **🔄 Smart Caching**: Built-in caching to avoid reprocessing
- **🎨 Rich Color Palette**: Extract multiple color variants (dominant, vibrant, muted, etc.)
- **⚡ Lightweight**: Minimal bundle size impact
- **🔧 TypeScript Support**: Full TypeScript definitions included

## 📸 Demo

Extract beautiful color palettes from your images with just a few lines of code!

## 🚀 Installation

```bash
npm install react-native-nitro-image-colors react-native-nitro-modules
```

Or using Yarn:

```bash
yarn add react-native-nitro-image-colors react-native-nitro-modules
```

> **Note**: `react-native-nitro-modules` is required as this library relies on [Nitro Modules](https://nitro.margelo.com/).

### iOS Configuration

For iOS, you need to install the native dependencies:

```bash
cd ios && pod install
```

### Android Configuration

No additional configuration required for Android.

## 📖 Usage

### Basic Usage

```typescript
import { getColors } from 'react-native-nitro-image-colors';

// Extract colors from a remote image
const colors = await getColors({
  uri: 'https://example.com/image.jpg',
});

console.log(colors);
// Output:
// {
//   platform: 'ios',
//   background: '#3A506B',
//   primary: '#1C2541',
//   secondary: '#5BC0BE',
//   detail: '#0B132B'
// }
```

### Advanced Configuration

```typescript
import { getColors, type Config } from 'react-native-nitro-image-colors';

const config: Config = {
  fallback: '#000000', // Color used if extraction fails
  pixelSpacing: 5, // Pixel sampling rate (Android only)
  cache: true, // Enable caching
  headers: {
    // HTTP headers for remote images
    Authorization: 'Bearer token',
  },
  key: 'custom-cache-key', // Custom cache key
};

const colors = await getColors(
  { uri: 'https://example.com/image.jpg' },
  config
);
```

### React Component Example

```typescript
import React, { useState, useEffect } from 'react';
import { View, Text, Image } from 'react-native';
import { getColors, type ImageColors } from 'react-native-nitro-image-colors';

const ColorExtractor = ({ imageUri }: { imageUri: string }) => {
  const [colors, setColors] = useState<ImageColors | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const extractColors = async () => {
      setLoading(true);
      try {
        const extractedColors = await getColors({ uri: imageUri });
        setColors(extractedColors);
      } catch (error) {
        console.error('Failed to extract colors:', error);
      } finally {
        setLoading(false);
      }
    };

    extractColors();
  }, [imageUri]);

  if (loading) {
    return <Text>Extracting colors...</Text>;
  }

  if (!colors) {
    return <Text>No colors extracted</Text>;
  }

  return (
    <View>
      <Image source={{ uri: imageUri }} style={{ width: 200, height: 200 }} />
      <View style={{ flexDirection: 'row', flexWrap: 'wrap' }}>
        {Object.entries(colors)
          .filter(([key, value]) => key !== 'platform' && typeof value === 'string')
          .map(([key, color]) => (
            <View
              key={key}
              style={{
                backgroundColor: color,
                width: 50,
                height: 50,
                margin: 4,
                borderRadius: 8,
                justifyContent: 'center',
                alignItems: 'center'
              }}
            >
              <Text style={{ fontSize: 8, color: 'white', fontWeight: 'bold' }}>
                {key}
              </Text>
            </View>
          ))}
      </View>
    </View>
  );
};
```

## 🎨 API Reference

### `getColors(uri, config?)`

Extracts prominent colors from an image.

#### Parameters

- `uri`: `number | ImageSourcePropType` - Image URI or resource ID
- `config?`: `Config` - Optional configuration object

#### Returns

`Promise<ImageColors>` - Object containing extracted colors

### Configuration Options

| Option         | Type                     | Default     | Description                        |
| -------------- | ------------------------ | ----------- | ---------------------------------- |
| `fallback`     | `string`                 | `'#000000'` | Fallback color if extraction fails |
| `pixelSpacing` | `number`                 | `5`         | Pixel sampling rate (Android only) |
| `headers`      | `Record<string, string>` | `{}`        | HTTP headers for remote images     |
| `cache`        | `boolean`                | `true`      | Enable in-memory caching           |
| `key`          | `string`                 | Image URI   | Custom cache key                   |

### ImageColors Response

The returned object contains platform-specific color properties:

#### iOS Colors

- `background`: Primary background color
- `primary`: Main primary color
- `secondary`: Secondary accent color
- `detail`: Detail/text color

#### Android Colors

- `dominant`: Most frequent color
- `average`: Average color of the image
- `vibrant`: Vibrant color variant
- `darkVibrant`: Dark vibrant variant
- `lightVibrant`: Light vibrant variant
- `darkMuted`: Dark muted variant
- `lightMuted`: Light muted variant
- `muted`: Muted color variant

#### Common Property

- `platform`: `'ios' | 'android'` - Platform where colors were extracted

## 🔧 TypeScript Support

Full TypeScript definitions are included:

```typescript
import {
  getColors,
  type ImageColors,
  type Config,
} from 'react-native-nitro-image-colors';
```

## 🚨 Error Handling

```typescript
try {
  const colors = await getColors({ uri: 'https://example.com/image.jpg' });
  // Use colors...
} catch (error) {
  if (error instanceof Error) {
    console.error('Color extraction failed:', error.message);
  }
  // Use fallback colors or show error message
}
```

## 🎯 Best Practices

### 1. Cache Wisely

```typescript
// Use caching for better performance
const config: Config = {
  cache: true,
  key: 'unique-image-key', // Required for long URIs
};
```

### 2. Handle Network Images

```typescript
// Add headers for authenticated images
const config: Config = {
  headers: {
    Authorization: 'Bearer your-token',
  },
};
```

### 3. Optimize Performance

```typescript
// Adjust pixel spacing for balance between accuracy and performance
const config: Config = {
  pixelSpacing: 10, // Higher values = faster but less accurate
};
```

## 📱 Example App

Check out the [example app](./example/) for a complete implementation:

```bash
cd example
yarn install
yarn ios # or yarn android
```

## 🔍 Troubleshooting

### Common Issues

1. **Colors not extracted**
   - Check image URI is accessible
   - Verify network permissions for remote images
   - Try with a different image format

2. **Performance issues**
   - Increase `pixelSpacing` value
   - Enable caching with `cache: true`
   - Use local images when possible

3. **TypeScript errors**
   - Ensure you have TypeScript installed
   - Check import statements

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Workflow

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built with [Nitro Modules](https://nitro.margelo.com/)
- Inspired by color extraction algorithms from both platforms
- Thanks to all contributors who help improve this library

---

<div align="center">

Made with ❤️ by [Yogesh Solanki](https://github.com/SolankiYogesh)

</div>
