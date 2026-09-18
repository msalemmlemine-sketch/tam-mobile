class SubscriptionPayment {
  final int? id;
  final int? memberId;
  final String? memberName;
  final String? financialGuide;
  final String? cardNo;
  final int paymentYear;
  final int? paymentMonth;
  final String? paymentDate;
  final double subscriptionAmount;
  final double cardFee;
  final double totalAmount;
  final String? source;
  final String? sourceName;
  final String paymentMethod;
  final String? paymentReference;
  final String? matchedBy;
  final bool directToExecutive;
  final String? importBatchId;
  final String? rowHash;
  final String? notes;
  final String createdAt;

  const SubscriptionPayment({
    this.id,
    this.memberId,
    this.memberName,
    this.financialGuide,
    this.cardNo,
    required this.paymentYear,
    this.paymentMonth,
    this.paymentDate,
    this.subscriptionAmount = 0,
    this.cardFee = 0,
    this.totalAmount = 0,
    this.source,
    this.sourceName,
    this.paymentMethod = 'cash',
    this.paymentReference,
    this.matchedBy,
    this.directToExecutive = false,
    this.importBatchId,
    this.rowHash,
    this.notes,
    required this.createdAt,
  });

  factory SubscriptionPayment.fromMap(Map<String, Object?> map) =>
      SubscriptionPayment(
        id: map['id'] as int?,
        memberId: map['member_id'] as int?,
        memberName: map['member_name'] as String?,
        financialGuide: map['financial_guide'] as String?,
        cardNo: map['card_no'] as String?,
        paymentYear: map['payment_year'] as int,
        paymentMonth: map['payment_month'] as int?,
        paymentDate: map['payment_date'] as String?,
        subscriptionAmount:
            (map['subscription_amount'] as num?)?.toDouble() ?? 0,
        cardFee: (map['card_fee'] as num?)?.toDouble() ?? 0,
        totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
        source: map['source'] as String?,
        sourceName: map['source_name'] as String?,
        paymentMethod: (map['payment_method'] as String?) ?? 'cash',
        paymentReference: map['payment_reference'] as String?,
        matchedBy: map['matched_by'] as String?,
        directToExecutive: ((map['direct_to_executive'] as int?) ?? 0) == 1,
        importBatchId: map['import_batch_id'] as String?,
        rowHash: map['row_hash'] as String?,
        notes: map['notes'] as String?,
        createdAt: map['created_at'] as String,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'member_id': memberId,
        'member_name': memberName,
        'financial_guide': financialGuide,
        'card_no': cardNo,
        'payment_year': paymentYear,
        'payment_month': paymentMonth,
        'payment_date': paymentDate,
        'subscription_amount': subscriptionAmount,
        'card_fee': cardFee,
        'total_amount': totalAmount,
        'source': source,
        'source_name': sourceName,
        'payment_method': paymentMethod,
        'payment_reference': paymentReference,
        'matched_by': matchedBy,
        'direct_to_executive': directToExecutive ? 1 : 0,
        'import_batch_id': importBatchId,
        'row_hash': rowHash,
        'notes': notes,
        'created_at': createdAt,
      };
}
