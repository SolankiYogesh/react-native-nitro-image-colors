import { NitroModules } from 'react-native-nitro-modules';
import type { NitroImageColors } from './NitroImageColors.nitro';

const NitroImageColorsHybridObject =
  NitroModules.createHybridObject<NitroImageColors>('NitroImageColors');

export function multiply(a: number, b: number): number {
  return NitroImageColorsHybridObject.multiply(a, b);
}
