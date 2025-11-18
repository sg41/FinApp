// lib/widgets/scheduled_payment_info_card.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/scheduled_payment.dart';
import '../providers/scheduled_payment_provider.dart';
import '../models/account.dart';
import '../utils/formatting.dart'; // Убедитесь, что этот импорт есть

class ScheduledPaymentInfoCard extends StatelessWidget {
  final ScheduledPayment payment;
  final Account creditorAccount; // Счет, для которого настроен платеж

  const ScheduledPaymentInfoCard({
    super.key,
    required this.payment,
    required this.creditorAccount,
  });

  // --- ИЗМЕНЕНИЕ 1: Обновленный метод для получения текста суммы с периодом ---
  String _getAmountText() {
    String text;
    // Сначала определяем базовый текст
    switch (payment.amountType) {
      case AmountType.fixed:
        // Для фиксированной суммы период не нужен, возвращаем сразу
        return '${payment.fixedAmount} ${payment.currency ?? ''}';
      case AmountType.total_debit:
        text = 'Все расходы за период';
        break;
      case AmountType.net_debit:
        text = 'Долг за период';
        break;
      case AmountType.minimum_payment:
        text = 'Мин. платеж (${payment.minimumPaymentPercentage} % от долга)';
        break;
    }

    // Если для этого типа нужен период и он задан, добавляем его
    if (payment.periodStartDate != null && payment.periodEndDate != null) {
      final formatter = DateFormat('dd.MM.yy');
      final start = formatter.format(payment.periodStartDate!);
      final end = formatter.format(payment.periodEndDate!);
      text += ' ($start - $end)';
    }

    return text;
  }

  String _getRecurrenceText() {
    if (payment.recurrenceType == null || payment.recurrenceInterval == null) {
      return 'Одноразовый платеж';
    }
    String periodText;
    switch (payment.recurrenceType!) {
      case RecurrenceType.days:
        periodText = 'день';
        break;
      case RecurrenceType.weeks:
        periodText = 'неделю';
        break;
      case RecurrenceType.months:
        periodText = 'месяц';
        break;
      case RecurrenceType.years:
        periodText = 'год';
        break;
    }
    // Простое правило для склонения
    if (payment.recurrenceInterval! > 1 && payment.recurrenceInterval! < 5) {
      if (periodText == 'неделю') periodText = 'недели';
      if (periodText == 'месяц') periodText = 'месяца';
      if (periodText == 'год') periodText = 'года';
    } else if (payment.recurrenceInterval! >= 5) {
      if (periodText == 'неделю') periodText = 'недель';
      if (periodText == 'месяц') periodText = 'месяцев';
      if (periodText == 'год') periodText = 'лет';
    }

    return 'Каждые ${payment.recurrenceInterval} $periodText';
  }

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
            // --- ИЗМЕНЕНИЕ 2: Используем новый метод для отображения счета ---
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

  // --- ИЗМЕНЕНИЕ 3: Новый метод для отрисовки сложного виджета счета ---
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

  // Обычная строка для простых пар "метка: значение"
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
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

  // --- ИЗМЕНЕНИЕ 4: Новый метод-обертка для пар "метка: сложный виджет" ---
  Widget _buildInfoRowWithWidget(String label, Widget valueWidget) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              top: 2.0,
            ), // Небольшой отступ для метки
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          const SizedBox(width: 16),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }
}
