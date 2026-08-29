class LocationPoint {
  final double lat;
  final double lng;
  final DateTime recordedAt;

  LocationPoint(
      {required this.lat, required this.lng, required this.recordedAt});

  factory LocationPoint.fromMap(Map<String, dynamic> map) {
    return LocationPoint(
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      recordedAt: DateTime.parse(map['recorded_at'] as String),
    );
  }
}
