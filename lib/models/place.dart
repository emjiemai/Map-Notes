enum PlaceCategory { retail, horeca, distributor, other }

PlaceCategory categoryFromString(String value) {
  return PlaceCategory.values.firstWhere(
    (c) => c.name == value,
    orElse: () => PlaceCategory.other,
  );
}

class Place {
  final String id;
  final String name;
  final String? address;
  final double lat;
  final double lng;
  final PlaceCategory category;
  final DateTime createdAt;

  Place({
    required this.id,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.category,
    required this.createdAt,
  });

  factory Place.fromMap(Map<String, dynamic> map) {
    return Place(
      id: map['id'] as String,
      name: map['name'] as String,
      address: map['address'] as String?,
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      category: categoryFromString(map['category'] as String? ?? 'other'),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
