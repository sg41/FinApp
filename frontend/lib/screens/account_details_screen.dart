// lib/screens/account_details_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/account.dart';
import '../providers/account_details_provider.dart';
import '../utils/formatting.dart';

class AccountDetailsScreen extends StatelessWidget {
  const AccountDetailsScreen({super.key});

  Future<void> _selectDate(BuildContext context, bool isStatementDate) async {
    final provider = Provider.of<AccountDetailsProvider>(
      context,
      listen: false,
    );
    if (provider.account == null) return;

    final initialDate =
        (isStatementDate
            ? provider.account!.statementDate
            : provider.account!.paymentDate) ??
        DateTime.now();

    final newDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (newDate == null) return;

    // Вызываем единый метод в провайдере
    provider.updateAndRefresh(
      statementDate: isStatementDate
          ? newDate
          : provider.account!.statementDate,
      paymentDate: isStatementDate ? provider.account!.paymentDate : newDate,
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
                _buildDatesCard(context, account),
                const SizedBox(height: 16),
                if (provider.isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (provider.turnoverData != null)
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pushNamed(
                        '/transactions',
                        arguments: {
                          'account': account,
                          'fromDate': account.statementDate!,
                          'toDate': account.paymentDate!,
                        },
                      );
                    },
                    child: _buildTurnoverCard(context, provider),
                  ),
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

  Widget _buildDatesCard(BuildContext context, Account account) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Отчетный период',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Divider(),
            ListTile(
              title: const Text('Дата выписки'),
              subtitle: Text(
                account.statementDate != null
                    ? DateFormat('dd.MM.yyyy').format(account.statementDate!)
                    : 'Не указана',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: () => _selectDate(context, true),
            ),
            ListTile(
              title: const Text('Дата платежа'),
              subtitle: Text(
                account.paymentDate != null
                    ? DateFormat('dd.MM.yyyy').format(account.paymentDate!)
                    : 'Не указана',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: () => _selectDate(context, false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTurnoverCard(
    BuildContext context,
    AccountDetailsProvider provider,
  ) {
    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Обороты за период',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Divider(),
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
