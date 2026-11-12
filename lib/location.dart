// GPS helper: reads the phone's location when the driver scans, so each boarding has a place and time.
import 'package:geolocator/geolocator.dart';
import 'data.dart';

typedef Fix = ({double lat, double lng});

/// Current position, or null when location is off, denied, or unavailable. Never throws.
Future<Fix?> currentFix() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return null;
    final x = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)));
    return (lat: x.latitude, lng: x.longitude);
  } catch (_) {
    return null;
  }
}

String fixOf(M x) => '${(x['lat'] as num).toStringAsFixed(5)}, ${(x['lng'] as num).toStringAsFixed(5)}';
String linkOf(M x) => 'https://www.google.com/maps?q=${x['lat']},${x['lng']}';
