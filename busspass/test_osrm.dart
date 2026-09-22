import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final coords = '74.738,19.09;74.735,19.12;74.20,19.57'; // example Ahmednagar to Sangamner
  final _osrmBase = 'https://router.project-osrm.org/route/v1/driving';
  final uri = Uri.parse('$_osrmBase/$coords?overview=full&geometries=polyline&steps=false');
  print('Requesting: $uri');
  final res = await http.get(uri);
  print('Status: ${res.statusCode}');
  print('Body: ${res.body.substring(0, 100)}...');
}
