// lib/widgets/scheduled_payment_info_card.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/scheduled_payment.dart';
import '../providers/scheduled_payment_provider.dart';
import '../models/account.dart'; // Для навигации

class ScheduledPaymentInfoCard extends StatelessWidget {
  final ScheduledPayment payment;
  final Account creditorAccount; // Счет, для которого настроен платеж

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
      // vvv НОВЫЙ КЕЙС vvv
      case AmountType.minimum_payment:
        return 'Мин. платеж (${payment.minimumPaymentPercentage} % от долга)';
      // ^^^ КОНЕЦ ^^^
    }
  }

  Future<void> _deletePayment(BuildContext context) async {
    // 1. Сохраняем ссылку на ScaffoldMessenger ДО всех await.
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удаление'),
        content: const Text('Вы уверены, что хотите удалить этот автоплатеж?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // 2. Проверяем, что виджет все еще "жив" после showDialog.
      if (!context.mounted) return;

      await Provider.of<ScheduledPaymentProvider>(
        context,
        listen: false,
      ).deletePayment(payment.id);

      // 3. Снова проверяем 'mounted' после самого долгого await
      if (!context.mounted) return;

      // 4. Используем сохраненную ссылку, а не 'context', который может быть уже невалидным.
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Автоплатеж удален')),
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
        nickname: 'Не найден',
        currency: '',
        balances: [],
        bankClientId: '',
        bankName: '',
        bankId: 0,
      ),
    );

    return Card(
      color: Colors.amber[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Автоплатеж настроен',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.black54),
                  onPressed: () {
                    Navigator.of(context).pushNamed(
                      '/scheduled-payment',
                      arguments: creditorAccount, // Передаем счет-получатель
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
            _buildInfoRow(
              'День платежа:',
              '${payment.paymentDayOfMonth}-е число',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
