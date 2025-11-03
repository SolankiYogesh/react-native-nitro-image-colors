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
  pixelSpacing: 1,
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
export type * from './NitroImageColors.nitro';
