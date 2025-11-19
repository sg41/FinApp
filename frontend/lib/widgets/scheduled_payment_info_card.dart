// lib/widgets/scheduled_payment_info_card.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/scheduled_payment.dart';
import '../models/turnover_data.dart';
import '../providers/scheduled_payment_provider.dart';
// VVV ДОБАВЛЯЕМ ИМПОРТ ДЛЯ НАВИГАЦИИ VVV
import '../providers/account_details_provider.dart';
// ^^^ КОНЕЦ ИМПОРТА ^^^
import '../models/account.dart';
import '../utils/formatting.dart';

class ScheduledPaymentInfoCard extends StatelessWidget {
  final ScheduledPayment payment;
  final Account debtorAccount;
  final Account creditorAccount;
  final bool isDebitView;
  final TurnoverData? turnoverForPreview;
  final bool isPreviewLoading;

  const ScheduledPaymentInfoCard({
    super.key,
    required this.payment,
    required this.debtorAccount,
    required this.creditorAccount,
    this.isDebitView = false,
    this.turnoverForPreview,
    this.isPreviewLoading = false,
  });

  /// Вычисляет и форматирует предварительную сумму платежа, если есть данные.
  String? _calculatePreviewAmount() {
    if (turnoverForPreview == null) return null;

    double amount = 0;
    bool calculationDone = false;

    switch (payment.amountType) {
      case AmountType.total_debit:
        amount = turnoverForPreview!.totalDebit;
        calculationDone = true;
        break;
      case AmountType.net_debit:
        amount =
            turnoverForPreview!.totalDebit - turnoverForPreview!.totalCredit;
        calculationDone = true;
        break;
      case AmountType.minimum_payment:
        final percentage = payment.minimumPaymentPercentage ?? 0.0;
        if (percentage > 0) {
          final debt =
              turnoverForPreview!.totalDebit - turnoverForPreview!.totalCredit;
          amount = debt * (percentage / 100);
          calculationDone = true;
        }
        break;
      case AmountType.fixed:
        break;
    }

    if (!calculationDone) return null;
    if (amount < 0) amount = 0;

    String previewText =
        '~ ${amount.toFormattedCurrency(turnoverForPreview!.currency)}';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (payment.periodEndDate != null &&
        payment.periodEndDate!.isAfter(today)) {
      previewText += ' (на ${DateFormat('dd.MM.yy').format(today)})';
    }
    return previewText;
  }

  /// Возвращает финальный текст для отображения суммы.
  String _getAmountText() {
    String baseText;
    switch (payment.amountType) {
      case AmountType.fixed:
        return '${payment.fixedAmount?.toStringAsFixed(2) ?? '0.00'} ${payment.currency ?? ''}';
      case AmountType.total_debit:
        baseText = 'Все расходы за период';
        break;
      case AmountType.net_debit:
        baseText = 'Долг за период';
        break;
      case AmountType.minimum_payment:
        baseText =
            'Мин. платеж (${payment.minimumPaymentPercentage}% от долга)';
        break;
    }

    if (payment.periodStartDate != null && payment.periodEndDate != null) {
      final formatter = DateFormat('dd.MM.yy');
      final start = formatter.format(payment.periodStartDate!);
      final end = formatter.format(payment.periodEndDate!);
      baseText += ' ($start - $end)';
    }

    if (isPreviewLoading) {
      return '$baseText\nРасчет...';
    }

    final calculatedAmount = _calculatePreviewAmount();
    if (calculatedAmount != null) {
      return '$baseText\n$calculatedAmount';
    }

    return baseText;
  }

  /// Возвращает отформатированную строку с правилами повторения.
  String _getRecurrenceText() {
    if (payment.recurrenceType == null || payment.recurrenceInterval == null) {
      return 'Одноразовый платеж';
    }

    final int interval = payment.recurrenceInterval!;
    String periodText;

    String pluralize(int count, String one, String few, String many) {
      if (count % 10 == 1 && count % 100 != 11) return one;
      if (count % 10 >= 2 &&
          count % 10 <= 4 &&
          (count % 100 < 10 || count % 100 >= 20))
        return few;
      return many;
    }

    switch (payment.recurrenceType!) {
      case RecurrenceType.days:
        periodText = pluralize(interval, 'день', 'дня', 'дней');
        break;
      case RecurrenceType.weeks:
        periodText = pluralize(interval, 'неделю', 'недели', 'недель');
        break;
      case RecurrenceType.months:
        periodText = pluralize(interval, 'месяц', 'месяца', 'месяцев');
        break;
      case RecurrenceType.years:
        periodText = pluralize(interval, 'год', 'года', 'лет');
        break;
    }
    return 'Каждые $interval $periodText';
  }

  /// Показывает диалог подтверждения и удаляет автопополнение.
  Future<void> _deletePayment(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final provider = Provider.of<ScheduledPaymentProvider>(
      context,
      listen: false,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удаление'),
        content: Text(
          isDebitView
              ? 'Вы уверены, что хотите удалить это автосписание?'
              : 'Вы уверены, что хотите удалить это автопополнение?',
        ),
        actions: [
          TextButton(
            onPressed: () => navigator.pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => navigator.pop(true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await provider.deletePayment(payment.id);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            isDebitView ? 'Автосписание удалено' : 'Автопополнение удалено',
          ),
        ),
      );
    }
  }

  // VVV НОВЫЙ МЕТОД ДЛЯ ПЕРЕХОДА К СЧЕТУ VVV
  void _navigateToAccount(BuildContext context, Account account) {
    // 1. Устанавливаем выбранный счет в провайдере деталей
    Provider.of<AccountDetailsProvider>(
      context,
      listen: false,
    ).setCurrentAccount(account);

    // 2. Переходим на экран деталей
    // Используем pushNamed, чтобы можно было вернуться назад кнопкой Back
    Navigator.of(context).pushNamed('/account-details');
  }
  // ^^^ КОНЕЦ НОВОГО МЕТОДА ^^^

  @override
  Widget build(BuildContext context) {
    final String titleText = isDebitView ? 'Автосписание' : 'Автопополнение';
    final Color cardColor = isDebitView
        ? Colors.red.shade50
        : Colors.amber.shade50;

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$titleText #${payment.id}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.black54),
                  onPressed: () {
                    Navigator.of(context).pushNamed(
                      '/scheduled-payment',
                      arguments: {
                        'creditorAccount': creditorAccount,
                        'existingPayment': payment,
                      },
                    );
                  },
                  tooltip: 'Изменить',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _deletePayment(context),
                  tooltip: 'Удалить',
                ),
              ],
            ),
            const Divider(),
            // VVV ПЕРЕДАЕМ CONTEXT В МЕТОД VVV
            _buildInfoRowWithWidget(
              isDebitView ? 'На счет:' : 'Со счета:',
              _buildAccountDetails(
                context,
                isDebitView ? creditorAccount : debtorAccount,
              ),
            ),
            // ^^^ КОНЕЦ ИЗМЕНЕНИЯ ^^^
            _buildInfoRow('Сумма:', _getAmountText()),
            const SizedBox(height: 8),
            _buildInfoRow(
              'Следующий платеж:',
              DateFormat('dd MMMM yyyy').format(payment.nextPaymentDate),
            ),
            _buildInfoRow('Повторение:', _getRecurrenceText()),
          ],
        ),
      ),
    );
  }

  /// Вспомогательный виджет для отображения полной информации о счете.
  // VVV ИЗМЕНЕННЫЙ МЕТОД: ДОБАВЛЕН INKWELL И CONTEXT VVV
  Widget _buildAccountDetails(BuildContext context, Account account) {
    final balance = account.availableBalance;
    final balanceText = balance != null
        ? (num.tryParse(balance.amount) ?? 0.0).toFormattedCurrency(
            balance.currency,
          )
        : 'Баланс н/д';

    // Оборачиваем в Material и InkWell для кликабельности
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => _navigateToAccount(context, account),
        child: Padding(
          padding: const EdgeInsets.only(
            left: 8.0,
            top: 4.0,
            bottom: 4.0,
          ), // Добавили отступ для тапа
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    account.nickname,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      decoration:
                          TextDecoration.underline, // Подчеркнем, как ссылку
                      decorationStyle: TextDecorationStyle.dotted, // Пунктиром
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 10,
                    color: Colors.grey,
                  ), // Маленькая стрелочка
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${account.bankName.toUpperCase()} | ${account.bankClientId}\n$balanceText',
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[700],
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  // ^^^ КОНЕЦ ИЗМЕНЕНИЙ ^^^

  /// Вспомогательный виджет для простой строки "Метка: Значение".
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1.0),
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// Вспомогательный виджет для строки "Метка: Сложный виджет".
  Widget _buildInfoRowWithWidget(String label, Widget valueWidget) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8.0), // Чуть опустим метку
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          const SizedBox(width: 16),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }
}
