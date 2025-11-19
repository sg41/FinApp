// lib/widgets/scheduled_payment_form/_creditor_account_card.dart

import 'package:flutter/material.dart';
import '../../models/account.dart';
import '../../utils/formatting.dart';

class CreditorAccountCard extends StatelessWidget {
  final Account account;

  const CreditorAccountCard({
    super.key,
    required this.account,
  });

  @override
  Widget build(BuildContext context) {
    // Получаем баланс для отображения
    final balance = account.availableBalance;
    final balanceText = balance != null
        ? (num.tryParse(balance.amount) ?? 0.0)
            .toFormattedCurrency(balance.currency)
        : 'Баланс н/д';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок поля, имитирующий Label текстового поля
            Text(
              'Переводить на счет',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            // Основное название счета
            Text(
              account.nickname,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500, // Чуть жирнее
              ),
            ),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            // Детальная информация
            _buildDetailRow('Банк', account.bankName.toUpperCase()),
            _buildDetailRow('ID клиента', account.bankClientId),
            _buildDetailRow('ID счета', account.apiAccountId),
            const SizedBox(height: 4),
            // Баланс выделяем
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Текущий баланс',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                Text(
                  balanceText,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green, // Можно использовать зеленый для акцента
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}