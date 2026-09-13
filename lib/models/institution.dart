class Institution {
  final int? id;
  final int districtId;
  final String name;
  final String createdAt;

  const Institution({
    this.id,
    required this.districtId,
    required this.name,
    required this.createdAt,
  });

  factory Institution.fromMap(Map<String, Object?> map) => Institution(
        id: map['id'] as int?,
        districtId: map['district_id'] as int,
        name: map['name'] as String,
        createdAt: map['created_at'] as String,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'district_id': districtId,
        'name': name,
        'created_at': createdAt,
      };

  Institution copyWith({int? id, int? districtId, String? name}) =>
      Institution(
        id: id ?? this.id,
        districtId: districtId ?? this.districtId,
        name: name ?? this.name,
        createdAt: createdAt,
      );
}
