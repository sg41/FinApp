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
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: DropdownButtonFormField<int>(
          value: selectedDebtorAccountId,
          decoration: const InputDecoration(
            labelText: 'Переводить со счета',
          ),
          isExpanded: true,
          itemHeight: 60,
          selectedItemBuilder: (context) {
            return availableAccounts.map<Widget>((Account account) {
              return Text(
                '${account.nickname} (${account.bankName.toUpperCase()})',
                overflow: TextOverflow.ellipsis,
              );
            }).toList();
          },
          items: availableAccounts.map((Account account) {
            final balance = account.availableBalance;
            final balanceText = balance != null
                ? (num.tryParse(balance.amount) ?? 0.0)
                    .toFormattedCurrency(balance.currency)
                : 'Баланс н/д';
            return DropdownMenuItem<int>(
              value: account.id,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${account.nickname} (${account.bankName.toUpperCase()})',
                    style: const TextStyle(fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    balanceText,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: onChanged,
          validator: (value) => value == null ? 'Выберите счет' : null,
        ),
      ),
    );
  }
}