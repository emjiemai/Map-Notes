import 'package:flutter/material.dart';

import '../models/place.dart';

/// Icon/color/label for each place category — shared by the map pins, the
/// filter chips, the category picker on Add Pin, and the detail badge.
class CategoryStyle {
  final IconData icon;
  final Color color;
  final String label;

  const CategoryStyle(
      {required this.icon, required this.color, required this.label});
}

const _styles = {
  PlaceCategory.hotel:
      CategoryStyle(icon: Icons.hotel, color: Colors.blue, label: 'Hotel'),
  PlaceCategory.medical: CategoryStyle(
      icon: Icons.local_hospital, color: Colors.red, label: 'Medical'),
  PlaceCategory.restaurant: CategoryStyle(
      icon: Icons.restaurant, color: Colors.orange, label: 'Restaurant'),
  PlaceCategory.other: CategoryStyle(
      icon: Icons.location_on, color: Colors.blueGrey, label: 'Other'),
};

CategoryStyle styleFor(PlaceCategory category) => _styles[category]!;
