class RegionalExpense {
  final int? id;
  final String expenseDate; // yyyy-MM-dd
  final double amount;
  final String? description;
  final String? notes;
  final String createdAt;

  const RegionalExpense({
    this.id,
    required this.expenseDate,
    required this.amount,
    this.description,
    this.notes,
    required this.createdAt,
  });

  int get year => int.parse(expenseDate.substring(0, 4));

  factory RegionalExpense.fromMap(Map<String, Object?> map) =>
      RegionalExpense(
        id: map['id'] as int?,
        expenseDate: map['expense_date'] as String,
        amount: (map['amount'] as num?)?.toDouble() ?? 0,
        description: map['description'] as String?,
        notes: map['notes'] as String?,
        createdAt: map['created_at'] as String,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'expense_date': expenseDate,
        'amount': amount,
        'description': description,
        'notes': notes,
        'created_at': createdAt,
      };
}
