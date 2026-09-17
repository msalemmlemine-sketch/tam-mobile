class Member {
  final int? id;
  final int districtId;
  final int institutionId;
  final String name;
  final String? guide; // الدليل المالي
  final String? cardNo;
  final String? phone;
  final String? notes;
  final String membershipStatus; // active | inactive | suspended
  final String? statusDate;
  final bool isArchived;
  final String createdAt;
  final String updatedAt;

  const Member({
    this.id,
    required this.districtId,
    required this.institutionId,
    required this.name,
    this.guide,
    this.cardNo,
    this.phone,
    this.notes,
    this.membershipStatus = 'active',
    this.statusDate,
    this.isArchived = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Member.fromMap(Map<String, Object?> map) => Member(
        id: map['id'] as int?,
        districtId: map['district_id'] as int,
        institutionId: map['institution_id'] as int,
        name: map['name'] as String,
        guide: map['guide'] as String?,
        cardNo: map['card_no'] as String?,
        phone: map['phone'] as String?,
        notes: map['notes'] as String?,
        membershipStatus: (map['membership_status'] as String?) ?? 'active',
        statusDate: map['status_date'] as String?,
        isArchived: ((map['is_archived'] as int?) ?? 0) == 1,
        createdAt: map['created_at'] as String,
        updatedAt: map['updated_at'] as String,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'district_id': districtId,
        'institution_id': institutionId,
        'name': name,
        'guide': guide,
        'card_no': cardNo,
        'phone': phone,
        'notes': notes,
        'membership_status': membershipStatus,
        'status_date': statusDate,
        'is_archived': isArchived ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  Member copyWith({
    int? districtId,
    int? institutionId,
    String? name,
    String? guide,
    String? cardNo,
    String? phone,
    String? notes,
    String? membershipStatus,
    String? statusDate,
    bool? isArchived,
    required String updatedAt,
  }) =>
      Member(
        id: id,
        districtId: districtId ?? this.districtId,
        institutionId: institutionId ?? this.institutionId,
        name: name ?? this.name,
        guide: guide ?? this.guide,
        cardNo: cardNo ?? this.cardNo,
        phone: phone ?? this.phone,
        notes: notes ?? this.notes,
        membershipStatus: membershipStatus ?? this.membershipStatus,
        statusDate: statusDate ?? this.statusDate,
        isArchived: isArchived ?? this.isArchived,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
