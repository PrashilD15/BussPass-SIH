import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  // Generate 30 fake coordinates slightly spaced out
  final coords = List.generate(30, (i) => '${74.0 + i*0.01},${19.0 + i*0.01}').join(';');
  final _osrmBase = 'https://router.project-osrm.org/route/v1/driving';
  final uri = Uri.parse('$_osrmBase/$coords?overview=full&geometries=polyline&steps=false');
  print('Requesting OSRM...');
  final res = await http.get(uri);
  print('OSRM Status: ${res.statusCode}');
  print('OSRM Body: ${res.body.substring(0, 100)}...');
}
