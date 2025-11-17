// lib/screens/account_details_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../models/account.dart' show Balance;
import '../providers/account_details_provider.dart';
import '../providers/accounts_provider.dart';
import '../providers/scheduled_payment_provider.dart';
import '../utils/formatting.dart';
import '../widgets/scheduled_payment_info_card.dart';

class AccountDetailsScreen extends StatefulWidget {
  const AccountDetailsScreen({super.key});

  @override
  State<AccountDetailsScreen> createState() => _AccountDetailsScreenState();
}

class _AccountDetailsScreenState extends State<AccountDetailsScreen> {
  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    // Используем addPostFrameCallback, чтобы гарантировать, что context доступен
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scheduledPaymentProvider = Provider.of<ScheduledPaymentProvider>(
        context,
        listen: false,
      );
      final accountsProvider = Provider.of<AccountsProvider>(
        context,
        listen: false,
      );
      // Этот метод загрузит и существующие автоплатежи, и список всех счетов
      scheduledPaymentProvider.fetchData(accountsProvider);
    });
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final provider = Provider.of<AccountDetailsProvider>(
      context,
      listen: false,
    );
    final account = provider.account;
    if (account == null) return;

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

    provider.updateAndRefresh(
      statementDate: newRange.start,
      paymentDate: newRange.end,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Используем Consumer2 для подписки на два провайдера одновременно
    return Consumer2<AccountDetailsProvider, ScheduledPaymentProvider>(
      builder: (context, detailsProvider, scheduledProvider, child) {
        if (detailsProvider.account == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final account = detailsProvider.account!;
        final existingPayment = scheduledProvider.getPaymentForAccount(
          account.id,
        );

        return PopScope(
          canPop: false,
          onPopInvoked: (bool didPop) {
            if (didPop) return;
            // Возвращаем true, если данные по оборотам были изменены
            Navigator.of(context).pop(detailsProvider.dataChanged);
          },
          child: Scaffold(
            appBar: AppBar(title: Text(account.nickname)),
            body: RefreshIndicator(
              onRefresh: _fetchData,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  _buildInfoCard(context, account),
                  const SizedBox(height: 16),

                  // --- ОСНОВНАЯ ЛОГИКА ОТОБРАЖЕНИЯ АВТОПЛАТЕЖА ---
                  if (scheduledProvider.isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (existingPayment != null)
                    // Если автоплатеж есть, показываем инфо-карточку
                    ScheduledPaymentInfoCard(
                      payment: existingPayment,
                      creditorAccount: account,
                    )
                  else
                    // Если автоплатежа нет, показываем кнопку добавления
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Добавить автоплатеж'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                      onPressed: () async {
                        final result = await Navigator.of(context).pushNamed(
                          '/scheduled-payment',
                          arguments: account, // Передаем текущий счет
                        );
                        // Если с экрана создания/редактирования вернулся true, обновляем данные
                        if (result == true && mounted) {
                          _fetchData();
                        }
                      },
                    ),

                  const SizedBox(height: 16),

                  if (detailsProvider.isLoading)
                    const Center(child: CircularProgressIndicator())
                  else
                    GestureDetector(
                      onTap:
                          (account.statementDate != null &&
                              account.paymentDate != null)
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
                      child: _buildTurnoverCard(
                        context,
                        detailsProvider,
                        account,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // --- Вспомогательные методы для отрисовки UI ---

  List<Widget> _buildBalanceRows(Account account) {
    final List<Widget> widgets = [];
    Balance? availableBalance;
    Balance? bookedBalance;

    try {
      availableBalance = account.balances.firstWhere(
        (b) => b.type == 'InterimAvailable',
      );
    } catch (e) {
      /* не найден */
    }

    try {
      bookedBalance = account.balances.firstWhere(
        (b) => b.type == 'InterimBooked',
      );
    } catch (e) {
      /* не найден */
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

  Widget _buildInfoCard(BuildContext context, Account account) {
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
            _buildInfoRow('Банк:', account.bankName.toUpperCase()),
            if (account.ownerName != null)
              _buildInfoRow('Владелец:', account.ownerName!),
            _buildInfoRow('Тип:', account.accountType ?? 'N/A'),
            _buildInfoRow('Статус:', account.status ?? 'N/A'),
            _buildInfoRow('ID счета:', account.apiAccountId),
            _buildInfoRow('ID клиента:', account.bankClientId),
            const SizedBox(height: 16),
            Text('Балансы', style: Theme.of(context).textTheme.titleLarge),
            const Divider(),
            ..._buildBalanceRows(account),
          ],
        ),
      ),
    );
  }

  Widget _buildTurnoverCard(
    BuildContext context,
    AccountDetailsProvider provider,
    Account account,
  ) {
    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    'Обороты за период',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                InkWell(
                  onTap: () => _selectDateRange(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Row(
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
