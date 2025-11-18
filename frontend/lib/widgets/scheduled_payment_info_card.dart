// lib/widgets/scheduled_payment_info_card.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/scheduled_payment.dart';
import '../providers/scheduled_payment_provider.dart';
import '../models/account.dart';

class ScheduledPaymentInfoCard extends StatelessWidget {
  final ScheduledPayment payment;
  final Account creditorAccount;

  const ScheduledPaymentInfoCard({
    super.key,
    required this.payment,
    required this.creditorAccount,
  });

  String _getAmountText() {
    switch (payment.amountType) {
      case AmountType.fixed:
        return '${payment.fixedAmount} ${payment.currency ?? ''}';
      case AmountType.total_debit:
        return 'Все расходы за период';
      case AmountType.net_debit:
        return 'Долг за период';
      case AmountType.minimum_payment:
        return 'Мин. платеж (${payment.minimumPaymentPercentage} % от долга)';
    }
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
        // --- ИЗМЕНЕНИЕ 6 ---
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
      // --- ИЗМЕНЕНИЕ 7 ---
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
                    // --- ИЗМЕНЕНИЕ 8 ---
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
            _buildInfoRow('Со счета:', debtorAccount.nickname),
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
}
