/// Centralized API keys for map & directions services.
///
/// The Android Maps SDK is unlocked via the key in
/// `android/app/src/main/AndroidManifest.xml`
/// (`com.google.android.geo.API_KEY`). The SAME key is reused client-side for
/// the Google Maps Directions API so road-snapped polylines can be rendered.
class ApiKeys {
  ApiKeys._();

  /// Google Maps / Directions API key (matches the Android manifest key).
  static const String googleMapsApiKey =
      'AIzaSyByNMkmAuzr0qWn-HWlOqRg2iJTb80666Y';

  /// Default transport mode for directions lookups.
  static const String directionsMode = 'driving';
}
