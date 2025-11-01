import { NitroModules } from 'react-native-nitro-modules';
import type {
  Config,
  ImageColors,
  ImageSourcePropType,
  NitroImageColors,
} from './NitroImageColors.nitro';

const NitroImageColorsHybridObject =
  NitroModules.createHybridObject<NitroImageColors>('NitroImageColors');

export function getColors(
  uri: number | ImageSourcePropType,
  config?: Config
): Promise<ImageColors> {
  return NitroImageColorsHybridObject.getColors(uri, config);
}
export type * from './NitroImageColors.nitro';
