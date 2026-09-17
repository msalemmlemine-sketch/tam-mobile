class Institution {
  final int? id;
  final int districtId;
  final String name;
  final int totalStaff;
  final int sipesMembers;
  final int snesMembers;
  final int otherUnionMembers;
  final int nonUnionStaff;
  final String createdAt;

  const Institution({
    this.id,
    required this.districtId,
    required this.name,
    this.totalStaff = 0,
    this.sipesMembers = 0,
    this.snesMembers = 0,
    this.otherUnionMembers = 0,
    this.nonUnionStaff = 0,
    required this.createdAt,
  });

  factory Institution.fromMap(Map<String, Object?> map) => Institution(
        id: map['id'] as int?,
        districtId: map['district_id'] as int,
        name: map['name'] as String,
        totalStaff: (map['total_staff'] as int?) ?? 0,
        sipesMembers: (map['sipes_members'] as int?) ?? 0,
        snesMembers: (map['snes_members'] as int?) ?? 0,
        otherUnionMembers: (map['other_union_members'] as int?) ?? 0,
        nonUnionStaff: (map['non_union_staff'] as int?) ?? 0,
        createdAt: map['created_at'] as String,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'district_id': districtId,
        'name': name,
        'total_staff': totalStaff,
        'sipes_members': sipesMembers,
        'snes_members': snesMembers,
        'other_union_members': otherUnionMembers,
        'non_union_staff': nonUnionStaff,
        'created_at': createdAt,
      };

  Institution copyWith({
    int? id,
    int? districtId,
    String? name,
    int? totalStaff,
    int? sipesMembers,
    int? snesMembers,
    int? otherUnionMembers,
    int? nonUnionStaff,
  }) =>
      Institution(
        id: id ?? this.id,
        districtId: districtId ?? this.districtId,
        name: name ?? this.name,
        totalStaff: totalStaff ?? this.totalStaff,
        sipesMembers: sipesMembers ?? this.sipesMembers,
        snesMembers: snesMembers ?? this.snesMembers,
        otherUnionMembers: otherUnionMembers ?? this.otherUnionMembers,
        nonUnionStaff: nonUnionStaff ?? this.nonUnionStaff,
        createdAt: createdAt,
      );
}

class InstitutionAnalytics {
  final Institution institution;
  final String districtName;
  final int tamMembers;

  const InstitutionAnalytics({
    required this.institution,
    required this.districtName,
    required this.tamMembers,
  });

  int get classifiedStaff =>
      tamMembers +
      institution.sipesMembers +
      institution.snesMembers +
      institution.otherUnionMembers +
      institution.nonUnionStaff;

  int get unclassifiedStaff => institution.totalStaff - classifiedStaff;

  double? get tamPercentage =>
      institution.totalStaff > 0 ? tamMembers * 100 / institution.totalStaff : null;

  double? get sipesPercentage => institution.totalStaff > 0
      ? institution.sipesMembers * 100 / institution.totalStaff
      : null;

  double? get snesPercentage => institution.totalStaff > 0
      ? institution.snesMembers * 100 / institution.totalStaff
      : null;

  double? get otherUnionPercentage =>
      institution.totalStaff > 0
          ? institution.otherUnionMembers * 100 / institution.totalStaff
          : null;

  double? get nonUnionPercentage =>
      institution.totalStaff > 0
          ? institution.nonUnionStaff * 100 / institution.totalStaff
          : null;
}
