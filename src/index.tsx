import { NitroModules } from 'react-native-nitro-modules';
import type {
  Config,
  ImageColors,
  ImageSourcePropType,
  NitroImageColors,
} from './NitroImageColors.nitro';

const NitroImageColorsHybridObject =
  NitroModules.createHybridObject<NitroImageColors>('NitroImageColors');

const defaultConfig: Config = {
  cache: true,
  fallback: '#000000',
  headers: {},
  key: '',
  // Matches the documented default (see README) — sampling every pixel is
  // significantly slower with negligible accuracy benefit.
  pixelSpacing: 5,
};

export function getColors(
  uri: number | ImageSourcePropType,
  config: Partial<Config> = {}
): Promise<ImageColors> {
  return NitroImageColorsHybridObject.getColors(uri, {
    ...defaultConfig,
    ...config,
  });
}

/**
 * Clears every entry from the native in-memory color cache.
 */
export function clearCache(): void {
  NitroImageColorsHybridObject.clearCache();
}

/**
 * Sets the maximum number of entries kept in the native in-memory cache.
 * Once exceeded, the oldest entries are evicted first. Default: 100.
 */
export function setMaxCacheSize(size: number): void {
  NitroImageColorsHybridObject.setMaxCacheSize(size);
}

export type * from './NitroImageColors.nitro';
