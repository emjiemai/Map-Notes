import 'package:flutter/material.dart';

import '../models/place.dart';

/// Icon/color/label for each place category — shared by the map pins, the
/// filter chips, the category picker on Add Pin, and the detail badge.
class CategoryStyle {
  final IconData icon;
  final Color color;
  final String label;

  const CategoryStyle({required this.icon, required this.color, required this.label});
}

const _styles = {
  PlaceCategory.retail: CategoryStyle(icon: Icons.storefront, color: Colors.blue, label: 'Retail'),
  PlaceCategory.horeca: CategoryStyle(icon: Icons.local_cafe, color: Colors.orange, label: 'HoReCa'),
  PlaceCategory.distributor: CategoryStyle(icon: Icons.local_shipping, color: Colors.purple, label: 'Distributor'),
  PlaceCategory.other: CategoryStyle(icon: Icons.location_on, color: Colors.blueGrey, label: 'Other'),
};

CategoryStyle styleFor(PlaceCategory category) => _styles[category]!;
