// lib/screens/account_details_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/account.dart';
import '../providers/account_details_provider.dart';
import '../utils/formatting.dart';
import '../models/account.dart' show Balance;
import '../widgets/scheduled_payment_form.dart'; // <-- НОВЫЙ ИМПОРТ

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
                // VVV ДОБАВЛЯЕМ НОВЫЙ ВИДЖЕТ ЗДЕСЬ VVV
                const ScheduledPaymentForm(),
                const SizedBox(height: 16),
                // ^^^ КОНЕЦ ИЗМЕНЕНИЙ ^^^
                if (provider.isLoading)
                  const Center(child: CircularProgressIndicator())
                else
                  GestureDetector(
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
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildBalanceRows(Account account) {
    final List<Widget> widgets = [];
    Balance? availableBalance;
    Balance? bookedBalance;

    try {
      availableBalance = account.balances.firstWhere(
        (b) => b.type == 'InterimAvailable',
      );
    } catch (e) {
      /* InterimAvailable не найден, он останется null */
    }

    try {
      bookedBalance = account.balances.firstWhere(
        (b) => b.type == 'InterimBooked',
      );
    } catch (e) {
      /* InterimBooked не найден, он останется null */
    }

    if (availableBalance == null) {
      widgets.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4.0),
          child: Text('Данные о доступном балансе отсутствуют.'),
        ),
      );
      return widgets;
    }

    widgets.add(
      _buildInfoRow(
        'Доступно:',
        (num.tryParse(availableBalance.amount) ?? 0).toFormattedCurrency(
          availableBalance.currency,
        ),
      ),
    );

    if (bookedBalance != null) {
      final availableAmount = num.tryParse(availableBalance.amount) ?? 0.0;
      final bookedAmount = num.tryParse(bookedBalance.amount) ?? 0.0;
      final difference = availableAmount - bookedAmount;

      if (difference.abs() > 0.01) {
        widgets.add(
          _buildInfoRow(
            'Операции в обработке:',
            difference.toFormattedCurrency(availableBalance.currency),
            valueColor: Colors.grey[600],
          ),
        );
      }
    }

    return widgets;
  }

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
            ..._buildBalanceRows(_account),
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
            // --- vvv ИЗМЕНЕНИЕ ЗДЕСЬ vvv ---
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  // 1. Оборачиваем заголовок в Expanded
                  child: Text(
                    'Обороты за период',
                    style: Theme.of(context).textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8), // 2. Заменяем Spacer на отступ
                InkWell(
                  onTap: () => _selectDateRange(context),
                  borderRadius: BorderRadius.circular(8), // для красоты
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
            // --- ^^^ КОНЕЦ ИЗМЕНЕНИЯ ^^^ ---
            const Divider(),
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
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
