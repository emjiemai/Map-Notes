class Group {
  final String id;
  final String name;
  final bool isDefault;

  Group({required this.id, required this.name, required this.isDefault});

  factory Group.fromMap(Map<String, dynamic> map) {
    return Group(
      id: map['id'] as String,
      name: map['name'] as String,
      isDefault: map['is_default'] as bool? ?? false,
    );
  }
}
