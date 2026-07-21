// The factory can't reference outer-scope variables (jest hoists `jest.mock`
// above everything, including `const`/`let`/`var` declarations, so any such
// reference would hit a TDZ error or see an unassigned variable). Instead the
// mock fns are created inside the factory and retrieved afterwards via
// `jest.requireMock`.
jest.mock('react-native-nitro-modules', () => {
  const getColors = jest.fn();
  const clearCache = jest.fn();
  const setMaxCacheSize = jest.fn();
  const createHybridObject = jest.fn(() => ({
    getColors,
    clearCache,
    setMaxCacheSize,
  }));
  return {
    NitroModules: { createHybridObject },
    __mockFns: { getColors, clearCache, setMaxCacheSize, createHybridObject },
  };
});

// Imported after the mock so `NitroModules.createHybridObject` is already
// mocked when `src/index.tsx` calls it at module-load time.
import { getColors, clearCache, setMaxCacheSize } from '../index';

const { __mockFns } = jest.requireMock('react-native-nitro-modules') as {
  __mockFns: {
    getColors: jest.Mock;
    clearCache: jest.Mock;
    setMaxCacheSize: jest.Mock;
    createHybridObject: jest.Mock;
  };
};
const {
  getColors: mockGetColors,
  clearCache: mockClearCache,
  setMaxCacheSize: mockSetMaxCacheSize,
  createHybridObject: mockCreateHybridObject,
} = __mockFns;

const DEFAULT_CONFIG = {
  cache: true,
  fallback: '#000000',
  headers: {},
  key: '',
  pixelSpacing: 5,
};

describe('createHybridObject', () => {
  it('creates the "NitroImageColors" hybrid object exactly once at module load', () => {
    expect(mockCreateHybridObject).toHaveBeenCalledWith('NitroImageColors');
  });
});

describe('getColors config merging/defaults', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGetColors.mockResolvedValue({ platform: 'ios' });
  });

  it('uses documented defaults when no config is passed', async () => {
    await getColors({ uri: 'https://example.com/a.png' });

    expect(mockGetColors).toHaveBeenCalledTimes(1);
    expect(mockGetColors).toHaveBeenCalledWith(
      { uri: 'https://example.com/a.png' },
      DEFAULT_CONFIG
    );
  });

  it('defaults pixelSpacing to 5 (matches README, not 1)', async () => {
    await getColors({ uri: 'a' });
    const [, config] = mockGetColors.mock.calls[0]!;
    expect(config.pixelSpacing).toBe(5);
  });

  it('merges a partial config over the defaults without dropping unspecified fields', async () => {
    await getColors({ uri: 'https://example.com/a.png' }, { fallback: '#fff' });

    expect(mockGetColors).toHaveBeenCalledWith(
      { uri: 'https://example.com/a.png' },
      { ...DEFAULT_CONFIG, fallback: '#fff' }
    );
  });

  it('lets every default field be overridden individually', async () => {
    await getColors(
      { uri: 'https://example.com/a.png' },
      {
        cache: false,
        fallback: '#123456',
        headers: { Authorization: 'Bearer token' },
        key: 'custom-key',
        pixelSpacing: 20,
      }
    );

    expect(mockGetColors).toHaveBeenCalledWith(
      { uri: 'https://example.com/a.png' },
      {
        cache: false,
        fallback: '#123456',
        headers: { Authorization: 'Bearer token' },
        key: 'custom-key',
        pixelSpacing: 20,
      }
    );
  });

  it('accepts a numeric resource id as the uri', async () => {
    await getColors(42);
    expect(mockGetColors).toHaveBeenCalledWith(42, DEFAULT_CONFIG);
  });

  it('does not mutate the shared default config object across calls', async () => {
    await getColors({ uri: 'a' }, { pixelSpacing: 100 });
    await getColors({ uri: 'b' });

    const firstCallConfig = mockGetColors.mock.calls[0]![1];
    const secondCallConfig = mockGetColors.mock.calls[1]![1];

    expect(firstCallConfig.pixelSpacing).toBe(100);
    expect(secondCallConfig.pixelSpacing).toBe(5);
  });

  it('resolves with whatever the native module returns', async () => {
    mockGetColors.mockResolvedValueOnce({
      platform: 'android',
      dominant: '#abcdef',
    });

    await expect(getColors({ uri: 'x' })).resolves.toEqual({
      platform: 'android',
      dominant: '#abcdef',
    });
  });

  it('propagates rejections from the native module', async () => {
    mockGetColors.mockRejectedValueOnce(new Error('boom'));
    await expect(getColors({ uri: 'x' })).rejects.toThrow('boom');
  });
});

describe('clearCache', () => {
  beforeEach(() => jest.clearAllMocks());

  it('delegates directly to the native clearCache implementation', () => {
    clearCache();
    expect(mockClearCache).toHaveBeenCalledTimes(1);
    expect(mockClearCache).toHaveBeenCalledWith();
  });
});

describe('setMaxCacheSize', () => {
  beforeEach(() => jest.clearAllMocks());

  it('delegates to the native setMaxCacheSize implementation with the given size', () => {
    setMaxCacheSize(50);
    expect(mockSetMaxCacheSize).toHaveBeenCalledTimes(1);
    expect(mockSetMaxCacheSize).toHaveBeenCalledWith(50);
  });
});
