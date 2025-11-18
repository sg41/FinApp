// lib/models/scheduled_payment.dart

import 'package:flutter/foundation.dart';

enum AmountType { fixed, total_debit, net_debit, minimum_payment }

// vvv НОВЫЙ ENUM vvv
enum RecurrenceType { days, weeks, months, years }
// ^^^ КОНЕЦ ^^^

class ScheduledPayment {
  final int id;
  final int userId;
  final int debtorAccountId;
  final int creditorAccountId;

  // --- vvv БЛОК ИЗМЕНЕНИЙ vvv ---
  final DateTime nextPaymentDate;
  final DateTime? periodStartDate;
  final DateTime? periodEndDate;
  final RecurrenceType? recurrenceType;
  final int? recurrenceInterval;
  // --- ^^^ КОНЕЦ БЛОКА ИЗМЕНЕНИЙ ^^^ ---

  final AmountType amountType;
  final double? fixedAmount;
  final double? minimumPaymentPercentage;
  final String? currency;
  final bool isActive;

  ScheduledPayment({
    required this.id,
    required this.userId,
    required this.debtorAccountId,
    required this.creditorAccountId,
    // --- vvv ОБНОВЛЕНИЕ КОНСТРУКТОРА vvv ---
    required this.nextPaymentDate,
    this.periodStartDate,
    this.periodEndDate,
    this.recurrenceType,
    this.recurrenceInterval,
    // --- ^^^ КОНЕЦ ОБНОВЛЕНИЯ ^^^ ---
    required this.amountType,
    this.fixedAmount,
    this.minimumPaymentPercentage,
    this.currency,
    required this.isActive,
  });

  factory ScheduledPayment.fromJson(Map<String, dynamic> json) {
    // Вспомогательная функция для безопасного парсинга Enum
    T? _parseEnum<T>(List<T> enumValues, String? value) {
      if (value == null) return null;
      try {
        return enumValues.firstWhere((e) => describeEnum(e!) == value);
      } catch (e) {
        return null;
      }
    }

    return ScheduledPayment(
      id: json['id'],
      userId: json['user_id'],
      debtorAccountId: json['debtor_account_id'],
      creditorAccountId: json['creditor_account_id'],

      // --- vvv ПАРСИНГ НОВЫХ ПОЛЕЙ vvv ---
      nextPaymentDate: DateTime.parse(json['next_payment_date']),
      periodStartDate: json['period_start_date'] != null
          ? DateTime.parse(json['period_start_date'])
          : null,
      periodEndDate: json['period_end_date'] != null
          ? DateTime.parse(json['period_end_date'])
          : null,
      recurrenceType: _parseEnum(
        RecurrenceType.values,
        json['recurrence_type'],
      ),
      recurrenceInterval: json['recurrence_interval'],

      // --- ^^^ КОНЕЦ ПАРСИНГА ^^^ ---
      amountType:
          _parseEnum(AmountType.values, json['amount_type']) ??
          AmountType.fixed,
      fixedAmount: json['fixed_amount'] != null
          ? double.tryParse(json['fixed_amount'].toString())
          : null,
      minimumPaymentPercentage: json['minimum_payment_percentage'] != null
          ? double.tryParse(json['minimum_payment_percentage'].toString())
          : null,
      currency: json['currency'],
      isActive: json['is_active'],
    );
  }
}
