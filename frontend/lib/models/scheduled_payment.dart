// lib/models/scheduled_payment.dart

import 'package:flutter/foundation.dart';

// Enum для типов сумм
enum AmountType {
  fixed,
  total_debit,
  net_debit,
  minimum_payment,
} // <-- НОВОЕ ЗНАЧЕНИЕ

class ScheduledPayment {
  final int id;
  final int userId;
  final int debtorAccountId;
  final int creditorAccountId;
  final int paymentDayOfMonth;
  final int statementDayOfMonth;
  final AmountType amountType;
  final double? fixedAmount;
  // vvv НОВОЕ ПОЛЕ vvv
  final double? minimumPaymentPercentage;
  // ^^^ КОНЕЦ НОВОГО ПОЛЯ ^^^
  final String? currency;
  final bool isActive;

  ScheduledPayment({
    required this.id,
    required this.userId,
    required this.debtorAccountId,
    required this.creditorAccountId,
    required this.paymentDayOfMonth,
    required this.statementDayOfMonth,
    required this.amountType,
    this.fixedAmount,
    // vvv ОБНОВЛЕНИЕ КОНСТРУКТОРА vvv
    this.minimumPaymentPercentage,
    // ^^^ КОНЕЦ ОБНОВЛЕНИЯ ^^^
    this.currency,
    required this.isActive,
  });

  // Фабричный конструктор для создания экземпляра из JSON
  factory ScheduledPayment.fromJson(Map<String, dynamic> json) {
    return ScheduledPayment(
      id: json['id'],
      userId: json['user_id'],
      debtorAccountId: json['debtor_account_id'],
      creditorAccountId: json['creditor_account_id'],
      paymentDayOfMonth: json['payment_day_of_month'],
      statementDayOfMonth: json['statement_day_of_month'],
      amountType: AmountType.values.firstWhere(
        (e) => describeEnum(e) == json['amount_type'],
        orElse: () => AmountType.fixed,
      ),
      fixedAmount: json['fixed_amount'] != null
          ? double.tryParse(json['fixed_amount'].toString())
          : null,
      // vvv ПАРСИНГ НОВОГО ПОЛЯ vvv
      minimumPaymentPercentage: json['minimum_payment_percentage'] != null
          ? double.tryParse(json['minimum_payment_percentage'].toString())
          : null,
      // ^^^ КОНЕЦ ПАРСИНГА ^^^
      currency: json['currency'],
      isActive: json['is_active'],
    );
  }
}
