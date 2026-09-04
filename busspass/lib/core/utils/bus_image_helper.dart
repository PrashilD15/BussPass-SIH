class BusImageHelper {
  static const Map<String, String> _imageMap = {
    'Shivneri':
        'https://storage.googleapis.com/busspass-58583.firebasestorage.app/bus_images%2FMSRTC_Shivneri.jpeg',
    'Shivshahi':
        'https://storage.googleapis.com/busspass-58583.firebasestorage.app/bus_images%2FMSRTC_Shivshahi.jpg',
    'Lalpari':
        'https://storage.googleapis.com/busspass-58583.firebasestorage.app/bus_images%2FMSRTC_Ordinary_Lalpari.jpeg',
    'Ordinary':
        'https://storage.googleapis.com/busspass-58583.firebasestorage.app/bus_images%2FMSRTC_Ordinary_Lalpari.jpeg',
    'E-Shiva-E':
        'https://storage.googleapis.com/busspass-58583.firebasestorage.app/bus_images%2FMSRTC_E-Shiva-E.jpeg',
    'E-Shivneri':
        'https://storage.googleapis.com/busspass-58583.firebasestorage.app/bus_images%2FMSRTC_E-Shiva-E.jpeg',
    'Hirkani':
        'https://storage.googleapis.com/busspass-58583.firebasestorage.app/bus_images%2Fmsrtc_Hirkani.jpeg',
  };

  /// Returns the storage URL for the bus image based on the bus type name.
  /// If no match is found, returns null so a fallback icon can be used.
  static String? getImageUrl(String busType) {
    for (final entry in _imageMap.entries) {
      if (busType.toLowerCase().contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    // Also check common Marathi terms if needed, or fallback based on keyword matches
    if (busType.toLowerCase().contains('ac') && busType.toLowerCase().contains('sleeper')) {
      return _imageMap['Shivshahi'];
    }
    
    // Fallback to ordinary if it doesn't match anything but contains standard
    if (busType.toLowerCase().contains('ordinary')) {
      return _imageMap['Ordinary'];
    }
    return null;
  }
}
