import type { HybridObject } from 'react-native-nitro-modules';

export type ImageSourcePropType = {
  uri: string;
};

/**
 * Options for extracting colors from an image.
 */
export interface Config {
  /**
   * Color used if extraction fails.
   * Must be a valid hex (e.g. `#000000`).
   * Default: `#000000`
   */
  fallback: string;

  /**
   * Number of pixels to skip while reading image data (Android only).
   * Lower values give better accuracy but are slower.
   */
  pixelSpacing: number;

  /**
   * Extra HTTP headers when downloading an image (mobile only).
   */
  headers: Record<string, string>;

  /**
   * Enable in-memory caching to avoid reprocessing the same image.
   */
  cache: boolean;

  /**
   * Custom cache key.
   * If not set, the image URI is used.
   * Required if URI length > 500 characters.
   */
  key: string;
}

/**
 * Extracted colors from an image.
 * Some fields are platform-specific.
 */
export interface ImageColors {
  // iOS
  background?: string;
  primary?: string;
  secondary?: string;
  detail?: string;

  // Android
  dominant?: string;
  average?: string;
  vibrant?: string;
  darkVibrant?: string;
  lightVibrant?: string;
  darkMuted?: string;
  lightMuted?: string;
  muted?: string;

  /** The platform where colors were extracted. android | ios */
  platform: string;
}

/**
 * Nitro native module for image color extraction.
 */
export interface NitroImageColors
  extends HybridObject<{ ios: 'swift'; android: 'kotlin' }> {
  /**
   * Extracts main colors from an image.
   *
   * @param uri - Image URI or resource ID.
   * @param config - Optional settings.
   * @returns A Promise with extracted color data.
   */
  getColors(
    uri: number | ImageSourcePropType,
    config?: Config
  ): Promise<ImageColors>;
}
