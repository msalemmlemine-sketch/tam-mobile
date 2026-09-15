class PaymentMethod {
  final String key;
  final String label;
  const PaymentMethod(this.key, this.label);

  static const cash = PaymentMethod('cash', 'نقدًا');
  static const masrifi = PaymentMethod('masrifi', 'مصرفي');
  static const bankily = PaymentMethod('bankily', 'بنكيلي');
  static const sedad = PaymentMethod('sedad', 'السداد');
  static const bimBank = PaymentMethod('bim_bank', 'BIM Bank');
  static const clik = PaymentMethod('clik', 'Clik');
  static const amanti = PaymentMethod('amanti', 'أمانتي');

  static const all = <PaymentMethod>[cash, masrifi, bankily, sedad, bimBank, clik, amanti];

  static bool isCash(String key) => key == cash.key;
  static bool isElectronic(String key) => !isCash(key);

  static String labelOf(String key) => all.firstWhere(
        (m) => m.key == key,
        orElse: () => PaymentMethod(key, key),
      ).label;
}
