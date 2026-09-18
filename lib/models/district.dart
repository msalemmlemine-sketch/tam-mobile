class District {
  final int? id;
  final String name;
  final int sortOrder;
  final String createdAt;

  const District({
    this.id,
    required this.name,
    this.sortOrder = 0,
    required this.createdAt,
  });

  factory District.fromMap(Map<String, Object?> map) => District(
        id: map['id'] as int?,
        name: map['name'] as String,
        sortOrder: (map['sort_order'] as int?) ?? 0,
        createdAt: map['created_at'] as String,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'sort_order': sortOrder,
        'created_at': createdAt,
      };

  District copyWith({int? id, String? name, int? sortOrder}) => District(
        id: id ?? this.id,
        name: name ?? this.name,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
      );
}
