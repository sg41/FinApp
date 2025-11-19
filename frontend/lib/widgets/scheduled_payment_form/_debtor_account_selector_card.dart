// lib/widgets/scheduled_payment_form/_debtor_account_selector_card.dart

import 'package:flutter/material.dart';
import '../../models/account.dart';
import '../../utils/formatting.dart';

class DebtorAccountSelectorCard extends StatelessWidget {
  final List<Account> availableAccounts;
  final int? selectedDebtorAccountId;
  final ValueChanged<int?> onChanged;

  const DebtorAccountSelectorCard({
    super.key,
    required this.availableAccounts,
    required this.selectedDebtorAccountId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(4.0),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              'Переводить со счета',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: selectedDebtorAccountId,
                isExpanded: true,
                // 1. СКРЫВАЕМ СТАНДАРТНУЮ СТРЕЛКУ, ЧТОБЫ УПРАВЛЯТЬ ЕЮ САМИМ
                icon: const SizedBox.shrink(),
                hint: const Text('Выберите счет'),
                onChanged: onChanged,

                // Строитель того, что показано в свернутом состоянии
                selectedItemBuilder: (BuildContext context) {
                  return availableAccounts.map<Widget>((Account account) {
                    // Тут передаем true, чтобы показать стрелку
                    return _buildSingleLineRow(
                      context,
                      account,
                      showArrow: true,
                    );
                  }).toList();
                },

                // Элементы выпадающего списка
                items: availableAccounts.map((Account account) {
                  return DropdownMenuItem<int>(
                    value: account.id,
                    // В списке стрелка не нужна
                    child: _buildSingleLineRow(
                      context,
                      account,
                      showArrow: false,
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSingleLineRow(
    BuildContext context,
    Account account, {
    required bool showArrow,
  }) {
    final balance = account.availableBalance;
    final balanceText = balance != null
        ? (num.tryParse(balance.amount) ?? 0.0).toFormattedCurrency(
            balance.currency,
          )
        : 'Баланс н/д';

    return Row(
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

        // 2. ЕСЛИ НУЖНА СТРЕЛКА — ДОБАВЛЯЕМ ЕЁ В КОНЕЦ СТРОКИ
        if (showArrow) ...[
          const SizedBox(width: 8),
          const Icon(Icons.arrow_drop_down, color: Colors.black54),
        ],
      ],
    );
  }
}
