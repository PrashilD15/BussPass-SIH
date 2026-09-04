class BusImageHelper {
  static const Map<String, String> _imageMap = {
    'Shivneri':
        'https://firebasestorage.googleapis.com/v0/b/busspass-58583.firebasestorage.app/o/bus_images%2FMSRTC_Shivneri.jpeg?alt=media&token=42609d6c-0169-4a3b-b29c-4be22cb493d7',
    'Shivshahi':
        'https://firebasestorage.googleapis.com/v0/b/busspass-58583.firebasestorage.app/o/bus_images%2FMSRTC_Shivshahi.jpg?alt=media&token=88c40bd8-f684-457a-bfa1-b88547daf1c0',
    'Lalpari':
        'https://firebasestorage.googleapis.com/v0/b/busspass-58583.firebasestorage.app/o/bus_images%2FMSRTC_Ordinary_Lalpari.jpeg?alt=media&token=0e6baa57-a61f-41ef-b68c-923a433fc321',
    'Ordinary':
        'https://firebasestorage.googleapis.com/v0/b/busspass-58583.firebasestorage.app/o/bus_images%2FMSRTC_Ordinary_Lalpari.jpeg?alt=media&token=0e6baa57-a61f-41ef-b68c-923a433fc321',
    'E-Shiva-E':
        'https://firebasestorage.googleapis.com/v0/b/busspass-58583.firebasestorage.app/o/bus_images%2FMSRTC_E-Shiva-E.jpeg?alt=media&token=e7d6266f-c931-4cf6-a408-15099bd8a6e1',
    'E-Shivneri':
        'https://firebasestorage.googleapis.com/v0/b/busspass-58583.firebasestorage.app/o/bus_images%2FMSRTC_E-Shiva-E.jpeg?alt=media&token=e7d6266f-c931-4cf6-a408-15099bd8a6e1',
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
