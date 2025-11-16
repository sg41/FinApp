// lib/screens/account_details_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/account.dart';
import '../providers/account_details_provider.dart';
import '../utils/formatting.dart';

class AccountDetailsScreen extends StatelessWidget {
  const AccountDetailsScreen({super.key});

  Future<void> _selectDateRange(BuildContext context) async {
    final provider = Provider.of<AccountDetailsProvider>(
      context,
      listen: false,
    );
    final account = provider.account;
    if (account == null) return;

    // Устанавливаем начальный диапазон на основе текущих дат в счете
    final initialRange = DateTimeRange(
      start:
          account.statementDate ??
          DateTime.now().subtract(const Duration(days: 30)),
      end: account.paymentDate ?? DateTime.now(),
    );

    final newRange = await showDateRangePicker(
      context: context,
      initialDateRange: initialRange,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (newRange == null) return; // Пользователь нажал "Отмена"

    // Вызываем метод обновления с обеими новыми датами
    provider.updateAndRefresh(
      statementDate: newRange.start,
      paymentDate: newRange.end,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Используем Consumer для подписки на изменения
    return Consumer<AccountDetailsProvider>(
      builder: (context, provider, child) {
        if (provider.account == null) {
          // Показываем заглушку, пока провайдер не инициализирован
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final account = provider.account!;
        final hasDates =
            account.statementDate != null && account.paymentDate != null;

        return PopScope(
          canPop: false,
          onPopInvoked: (bool didPop) {
            if (didPop) return;
            Navigator.of(context).pop(provider.dataChanged);
          },
          child: Scaffold(
            appBar: AppBar(title: Text(account.nickname)),
            body: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildInfoCard(context, account),
                const SizedBox(height: 16),
                // --- vvv ИЗМЕНЕНИЕ: Карточка оборотов теперь отображается всегда vvv ---
                if (provider.isLoading)
                  const Center(child: CircularProgressIndicator())
                else
                  // Оборачиваем карточку в GestureDetector
                  GestureDetector(
                    // Навигация на экран транзакций работает только если есть даты
                    onTap: hasDates
                        ? () {
                            Navigator.of(context).pushNamed(
                              '/transactions',
                              arguments: {
                                'account': account,
                                'fromDate': account.statementDate!,
                                'toDate': account.paymentDate!,
                              },
                            );
                          }
                        : null,
                    child: _buildTurnoverCard(context, provider, account),
                  ),
                // --- ^^^ КОНЕЦ ИЗМЕНЕНИЯ ^^^ ---
              ],
            ),
          ),
        );
      },
    );
  }

  // ... (все методы _build... остаются без изменений)
  Widget _buildInfoCard(BuildContext context, Account _account) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Основная информация',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Divider(),
            _buildInfoRow('Банк:', _account.bankName.toUpperCase()),
            if (_account.ownerName != null)
              _buildInfoRow('Владелец:', _account.ownerName!),
            _buildInfoRow('Тип:', _account.accountType ?? 'N/A'),
            _buildInfoRow('Статус:', _account.status ?? 'N/A'),
            _buildInfoRow('ID счета:', _account.apiAccountId),
            _buildInfoRow('ID клиента:', _account.bankClientId),
            const SizedBox(height: 16),
            Text('Балансы', style: Theme.of(context).textTheme.titleLarge),
            const Divider(),
            ..._account.balances.map(
              (b) => _buildInfoRow(
                '${b.type}:',
                (num.tryParse(b.amount) ?? 0).toFormattedCurrency(b.currency),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTurnoverCard(
    BuildContext context,
    AccountDetailsProvider provider,
    Account account, // Принимаем аккаунт для отображения дат
  ) {
    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Обороты за период',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                InkWell(
                  onTap: () => _selectDateRange(context),
                  borderRadius: BorderRadius.circular(8), // для красоты
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // --- vvv ИЗМЕНЕНИЕ: Показываем либо даты, либо плейсхолдер vvv ---
                        if (account.statementDate != null &&
                            account.paymentDate != null)
                          Text(
                            '${DateFormat('dd.MM.yy').format(account.statementDate!)} - ${DateFormat('dd.MM.yy').format(account.paymentDate!)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        else
                          Text(
                            'Выберите период',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontStyle: FontStyle.italic),
                          ),
                        // --- ^^^ КОНЕЦ ИЗМЕНЕНИЯ ^^^ ---
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.calendar_today,
                          size: 20,
                          color: Colors.black54,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const Divider(),
            // --- vvv ИЗМЕНЕНИЕ: Показываем либо данные, либо плейсхолдеры vvv ---
            if (provider.turnoverData != null) ...[
              _buildInfoRow(
                'Приход:',
                provider.turnoverData!.totalCredit.toFormattedCurrency(
                  provider.turnoverData!.currency,
                ),
                valueColor: Colors.green[700],
              ),
              _buildInfoRow(
                'Расход:',
                provider.turnoverData!.totalDebit.toFormattedCurrency(
                  provider.turnoverData!.currency,
                ),
                valueColor: Colors.red[700],
              ),
            ] else ...[
              _buildInfoRow('Приход:', '—', valueColor: Colors.grey[600]),
              _buildInfoRow('Расход:', '—', valueColor: Colors.grey[600]),
            ],
            // --- ^^^ КОНЕЦ ИЗМЕНЕНИЯ ^^^ ---
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
