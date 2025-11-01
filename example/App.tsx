import React, { useState, useCallback, memo } from 'react';
import {
  StyleSheet,
  View,
  Text,
  Image,
  ScrollView,
  TouchableOpacity,
  Alert,
  ActivityIndicator,
  SafeAreaView,
  StatusBar,
} from 'react-native';
import { getColors, type ImageColors } from 'react-native-nitro-image-colors';

const SAMPLE_IMAGES = [
  {
    id: 1,
    name: 'Nature Landscape',
    uri: 'https://images.unsplash.com/photo-1501854140801-50d01698950b?w=400&h=300&fit=crop',
  },
  {
    id: 2,
    name: 'Urban Architecture',
    uri: 'https://images.unsplash.com/photo-1477959858617-67f85cf4f1df?w=400&h=300&fit=crop',
  },
  {
    id: 3,
    name: 'Ocean Waves',
    uri: 'https://images.unsplash.com/photo-1505142468610-359e7d316be0?w=400&h=300&fit=crop',
  },
  {
    id: 4,
    name: 'Forest Path',
    uri: 'https://images.unsplash.com/photo-1448375240586-882707db888b?w=400&h=300&fit=crop',
  },
  {
    id: 5,
    name: 'Mountain Peak',
    uri: 'https://images.unsplash.com/photo-1464822759844-dfa37c1d4d4e?w=400&h=300&fit=crop',
  },
  {
    id: 6,
    name: 'Desert Sunset',
    uri: 'https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=400&h=300&fit=crop',
  },
];

const ColorCard = memo(({ title, color }: { title: string; color: string }) => {
  const copyToClipboard = useCallback((color: string) => {
    Alert.alert('Color Copied', `${color} copied to clipboard`);
  }, []);

  const getContrastColor = (hexColor: string) => {
    const r = parseInt(hexColor.slice(1, 3), 16);
    const g = parseInt(hexColor.slice(3, 5), 16);
    const b = parseInt(hexColor.slice(5, 7), 16);
    const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
    return luminance > 0.5 ? '#000000' : '#FFFFFF';
  };

  return (
    <TouchableOpacity
      style={[styles.colorCard, { backgroundColor: color }]}
      onPress={() => copyToClipboard(color)}
    >
      <View style={styles.colorInfo}>
        <Text style={[styles.colorName, { color: getContrastColor(color) }]}>
          {title}
        </Text>
        <Text style={[styles.colorValue, { color: getContrastColor(color) }]}>
          {color}
        </Text>
      </View>
    </TouchableOpacity>
  );
});

export default function App() {
  const [selectedImage, setSelectedImage] = useState(SAMPLE_IMAGES[0]);
  const [extractedColors, setExtractedColors] = useState<ImageColors | null>(
    null
  );
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const extractColors = useCallback(async (imageUri: string) => {
    setIsLoading(true);
    setError(null);
    try {
      const colors = await getColors(
        { uri: imageUri },
        {
          fallback: '#000000',
          pixelSpacing: 5,
          cache: true,
          headers: {},
          key: imageUri,
        }
      );
      setExtractedColors(colors);
    } catch (err) {
      const errorMessage =
        err instanceof Error ? err.message : 'Failed to extract colors';
      setError(errorMessage);
      Alert.alert('Error', errorMessage);
    } finally {
      setIsLoading(false);
    }
  }, []);

  const handleImageSelect = useCallback(
    (image: (typeof SAMPLE_IMAGES)[0]) => {
      setSelectedImage(image);
      extractColors(image.uri);
    },
    [extractColors]
  );

  React.useEffect(() => {
    if (SAMPLE_IMAGES[0]) {
      extractColors(SAMPLE_IMAGES[0].uri);
    }
  }, [extractColors]);

  const renderImage = useCallback(
    (uri: string) => (
      <Image
        source={{ uri: uri }}
        style={styles.galleryImage}
        resizeMode="cover"
      />
    ),
    []
  );

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="dark-content" backgroundColor="#ffffff" />
      <View style={styles.header}>
        <Text style={styles.title}>Nitro Image Colors</Text>
        <Text style={styles.subtitle}>
          Extract beautiful colors from your images
        </Text>
      </View>
      <ScrollView style={styles.content}>
        <View style={styles.imageSection}>
          <Text style={styles.sectionTitle}>Selected Image</Text>
          <View style={styles.imageContainer}>
            <Image
              source={{ uri: selectedImage?.uri }}
              style={styles.selectedImage}
              resizeMode="cover"
            />
            <View style={styles.imageOverlay}>
              <Text style={styles.imageName}>{selectedImage?.name}</Text>
            </View>
          </View>
        </View>
        <View style={styles.controlsSection}>
          <TouchableOpacity
            style={styles.extractButton}
            onPress={() => selectedImage && extractColors(selectedImage.uri)}
            disabled={isLoading || !selectedImage}
          >
            {isLoading ? (
              <ActivityIndicator color="#ffffff" />
            ) : (
              <Text style={styles.extractButtonText}>
                {extractedColors ? 'Re-extract Colors' : 'Extract Colors'}
              </Text>
            )}
          </TouchableOpacity>
        </View>
        {error && (
          <View style={styles.errorContainer}>
            <Text style={styles.errorText}>Error: {error}</Text>
          </View>
        )}
        {extractedColors && (
          <View style={styles.colorsSection}>
            <Text style={styles.sectionTitle}>Extracted Colors</Text>
            <Text style={styles.platformInfo}>
              Platform: {extractedColors.platform}
            </Text>
            <View style={styles.colorsGrid}>
              {Object.entries(extractedColors)
                .filter(
                  ([key, value]) =>
                    key !== 'platform' && typeof value === 'string'
                )
                .map(([key, color]) => (
                  <ColorCard
                    key={key}
                    title={formatColorName(key)}
                    color={color}
                  />
                ))}
            </View>
          </View>
        )}
        <View style={styles.gallerySection}>
          <Text style={styles.sectionTitle}>Sample Images</Text>
          <ScrollView horizontal showsHorizontalScrollIndicator={false}>
            <View style={styles.gallery}>
              {SAMPLE_IMAGES.map((image) => (
                <TouchableOpacity
                  key={image.id}
                  style={[
                    styles.galleryItem,
                    selectedImage?.id === image.id &&
                      styles.galleryItemSelected,
                  ]}
                  onPress={() => handleImageSelect(image)}
                >
                  {renderImage(image.uri)}
                  <Text style={styles.galleryText}>{image.name}</Text>
                </TouchableOpacity>
              ))}
            </View>
          </ScrollView>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const formatColorName = (key: string) => {
  return key
    .replace(/([A-Z])/g, ' $1')
    .replace(/^./, (str) => str.toUpperCase())
    .trim();
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f8f9fa',
  },
  header: {
    padding: 20,
    paddingTop: 10,
    backgroundColor: '#ffffff',
    borderBottomWidth: 1,
    borderBottomColor: '#e9ecef',
  },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    color: '#212529',
    textAlign: 'center',
    marginBottom: 4,
  },
  subtitle: {
    fontSize: 16,
    color: '#6c757d',
    textAlign: 'center',
  },
  content: {
    flex: 1,
  },
  imageSection: {
    padding: 20,
  },
  sectionTitle: {
    fontSize: 20,
    fontWeight: '600',
    color: '#212529',
    marginBottom: 16,
  },
  imageContainer: {
    borderRadius: 12,
    overflow: 'hidden',
    backgroundColor: '#ffffff',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 8,
    elevation: 4,
  },
  selectedImage: {
    width: '100%',
    height: 200,
  },
  imageOverlay: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    backgroundColor: 'rgba(0, 0, 0, 0.7)',
    padding: 12,
  },
  imageName: {
    color: '#ffffff',
    fontSize: 16,
    fontWeight: '600',
  },
  controlsSection: {
    padding: 20,
    paddingTop: 0,
  },
  extractButton: {
    backgroundColor: '#007bff',
    padding: 16,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#007bff',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
    elevation: 4,
  },
  extractButtonText: {
    color: '#ffffff',
    fontSize: 18,
    fontWeight: '600',
  },
  errorContainer: {
    backgroundColor: '#f8d7da',
    padding: 16,
    margin: 20,
    marginTop: 0,
    borderRadius: 8,
    borderLeftWidth: 4,
    borderLeftColor: '#dc3545',
  },
  errorText: {
    color: '#721c24',
    fontSize: 14,
  },
  colorsSection: {
    padding: 20,
  },
  platformInfo: {
    fontSize: 14,
    color: '#6c757d',
    marginBottom: 16,
    fontStyle: 'italic',
  },
  colorsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 12,
  },
  colorCard: {
    width: '48%',
    height: 80,
    borderRadius: 12,
    padding: 12,
    justifyContent: 'flex-end',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 2,
  },
  colorInfo: {
    backgroundColor: 'rgba(0, 0, 0, 0.1)',
    padding: 8,
    borderRadius: 6,
  },
  colorName: {
    fontSize: 12,
    fontWeight: '600',
    marginBottom: 2,
  },
  colorValue: {
    fontSize: 10,
    fontWeight: '500',
  },
  gallerySection: {
    padding: 20,
  },
  gallery: {
    flexDirection: 'row',
    gap: 12,
  },
  galleryItem: {
    width: 120,
    borderRadius: 12,
    overflow: 'hidden',
    backgroundColor: '#ffffff',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 2,
  },
  galleryItemSelected: {
    shadowColor: '#007bff',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
    elevation: 4,
    borderWidth: 2,
    borderColor: '#007bff',
  },
  galleryImage: {
    width: '100%',
    height: 80,
  },
  galleryText: {
    padding: 8,
    fontSize: 12,
    fontWeight: '500',
    color: '#212529',
    textAlign: 'center',
  },
});
