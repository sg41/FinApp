// lib/widgets/scheduled_payment_form/_creditor_account_card.dart

import 'package:flutter/material.dart';
import '../../models/account.dart';
import '../../utils/formatting.dart';

class CreditorAccountCard extends StatelessWidget {
  final Account account;

  const CreditorAccountCard({super.key, required this.account});

  @override
  Widget build(BuildContext context) {
    final balance = account.availableBalance;
    final balanceText = balance != null
        ? (num.tryParse(balance.amount) ?? 0.0).toFormattedCurrency(
            balance.currency,
          )
        : 'Баланс н/д';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(4.0),
      ),
      color: Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Переводить на счет',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 4),

            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: RichText(
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                          text: account.nickname,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                        TextSpan(
                          text:
                              '  •  ${account.bankName.toUpperCase()} ${account.bankClientId} ${account.apiAccountId}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                Text(
                  balanceText,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),

                // 3. ДОБАВЛЯЕМ НЕВИДИМУЮ СТРЕЛКУ ДЛЯ ИДЕАЛЬНОГО ВЫРАВНИВАНИЯ
                const SizedBox(width: 8),
                const Opacity(
                  opacity: 0.0, // Делаем невидимой
                  child: Icon(
                    Icons.arrow_drop_down,
                  ), // Тот же размер, что и в селекторе
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
