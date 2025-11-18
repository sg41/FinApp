// lib/widgets/scheduled_payment_info_card.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/scheduled_payment.dart';
import '../models/turnover_data.dart';
import '../providers/scheduled_payment_provider.dart';
import '../models/account.dart';
import '../utils/formatting.dart';

class ScheduledPaymentInfoCard extends StatelessWidget {
  final ScheduledPayment payment;
  final Account creditorAccount;
  final TurnoverData? turnoverForPreview;
  final bool isPreviewLoading;

  const ScheduledPaymentInfoCard({
    super.key,
    required this.payment,
    required this.creditorAccount,
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

  // --- ГЛАВНОЕ ИЗМЕНЕНИЕ: Обновленный метод для получения текста суммы ---
  /// Возвращает финальный текст для отображения суммы.
  String _getAmountText() {
    // 1. Получаем базовый описательный текст
    String baseText;
    switch (payment.amountType) {
      case AmountType.fixed:
        // Для фиксированной суммы расчеты не нужны, возвращаем сразу
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

    // 2. Добавляем информацию о периоде к базовому тексту
    if (payment.periodStartDate != null && payment.periodEndDate != null) {
      final formatter = DateFormat('dd.MM.yy');
      final start = formatter.format(payment.periodStartDate!);
      final end = formatter.format(payment.periodEndDate!);
      baseText += ' ($start - $end)';
    }

    // 3. Проверяем состояние загрузки
    if (isPreviewLoading) {
      return '$baseText\nРасчет...'; // Показываем базовый текст и статус расчета
    }

    // 4. Пытаемся получить рассчитанную сумму
    final calculatedAmount = _calculatePreviewAmount();
    if (calculatedAmount != null) {
      // Объединяем базовый текст и рассчитанную сумму через перенос строки
      return '$baseText\n$calculatedAmount';
    }

    // 5. Если ничего из вышеперечисленного не сработало, возвращаем только базовый текст
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
        content: const Text(
          'Вы уверены, что хотите удалить это автопополнение?',
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
        const SnackBar(content: Text('Автопополнение удалено')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ScheduledPaymentProvider>(
      context,
      listen: false,
    );
    final debtorAccount = provider.allUserAccounts.firstWhere(
      (acc) => acc.id == payment.debtorAccountId,
      orElse: () => Account(
        id: 0,
        apiAccountId: 'N/A',
        nickname: 'Счет не найден',
        currency: '',
        balances: [],
        bankClientId: '',
        bankName: '',
        bankId: 0,
      ),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      color: Colors.amber[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Автопополнение #${payment.id}',
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
            _buildInfoRowWithWidget(
              'Со счета:',
              _buildDebtorAccountDetails(debtorAccount),
            ),
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

  /// Вспомогательный виджет для отображения полной информации о счете-доноре.
  Widget _buildDebtorAccountDetails(Account debtorAccount) {
    final balance = debtorAccount.availableBalance;
    final balanceText = balance != null
        ? (num.tryParse(balance.amount) ?? 0.0).toFormattedCurrency(
            balance.currency,
          )
        : 'Баланс н/д';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          debtorAccount.nickname,
          textAlign: TextAlign.end,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          '${debtorAccount.bankName.toUpperCase()} | ${debtorAccount.bankClientId}\n$balanceText',
          textAlign: TextAlign.end,
          style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.4),
        ),
      ],
    );
  }

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
            padding: const EdgeInsets.only(top: 2.0),
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          const SizedBox(width: 16),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }
}
