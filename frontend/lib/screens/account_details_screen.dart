// lib/screens/account_details_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../models/account.dart' show Balance;
import '../models/scheduled_payment.dart';
import '../models/turnover_data.dart';
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
  final Map<int, TurnoverData?> _turnoverPreviews = {};
  final Map<int, bool> _isLoadingPreviews = {};
  Account? _currentAccount;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _currentAccount = Provider.of<AccountDetailsProvider>(
          context,
          listen: false,
        ).account;
        _fetchData();
      }
    });
  }

  Future<void> _fetchData() async {
    final scheduledPaymentProvider = Provider.of<ScheduledPaymentProvider>(
      context,
      listen: false,
    );
    final accountsProvider = Provider.of<AccountsProvider>(
      context,
      listen: false,
    );

    await scheduledPaymentProvider.fetchData(accountsProvider);

    if (mounted) {
      _fetchTurnoverPreviews();
    }
  }

  Future<void> _fetchTurnoverPreviews() async {
    if (_currentAccount == null) return;

    final scheduledProvider = Provider.of<ScheduledPaymentProvider>(
      context,
      listen: false,
    );
    final payments = scheduledProvider.getPaymentsForAccount(
      _currentAccount!.id,
    );
    final debits = scheduledProvider.getDebitsForAccount(_currentAccount!.id);
    final allRelatedPayments = {...payments, ...debits}.toList();

    for (final payment in allRelatedPayments) {
      final creditorAccount = scheduledProvider.allUserAccounts.firstWhere(
        (acc) => acc.id == payment.creditorAccountId,
        orElse: () => _currentAccount!,
      );

      final needsFetching =
          payment.amountType != AmountType.fixed &&
          payment.periodStartDate != null &&
          payment.periodEndDate != null &&
          _isLoadingPreviews[payment.id] != true;

      if (needsFetching) {
        if (mounted) {
          setState(() {
            _isLoadingPreviews[payment.id] = true;
          });
        }

        final period = DateTimeRange(
          start: payment.periodStartDate!,
          end: payment.periodEndDate!,
        );

        final turnover = await scheduledProvider.fetchTurnoverForPeriod(
          accountId: creditorAccount.id,
          period: period,
        );

        if (mounted) {
          setState(() {
            _turnoverPreviews[payment.id] = turnover;
            _isLoadingPreviews[payment.id] = false;
          });
        }
      }
    }
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

    if (newRange == null) return;

    provider.updateAndRefresh(
      statementDate: newRange.start,
      paymentDate: newRange.end,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AccountDetailsProvider, ScheduledPaymentProvider>(
      builder: (context, detailsProvider, scheduledProvider, child) {
        if (detailsProvider.account == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final account = detailsProvider.account!;

        // VVV СОРТИРОВКА СПИСКОВ ПО ID (ПО ВОЗРАСТАНИЮ) VVV
        final paymentsForAccount = scheduledProvider.getPaymentsForAccount(
          account.id,
        )..sort((a, b) => a.id.compareTo(b.id));

        final debitsForAccount = scheduledProvider.getDebitsForAccount(
          account.id,
        )..sort((a, b) => a.id.compareTo(b.id));
        // ^^^ КОНЕЦ СОРТИРОВКИ ^^^

        return PopScope(
          canPop: false,
          onPopInvoked: (bool didPop) {
            if (didPop) return;
            Navigator.of(context).pop(detailsProvider.dataChanged);
          },
          child: Scaffold(
            appBar: AppBar(title: Text(account.nickname)),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () async {
                final result = await Navigator.of(context).pushNamed(
                  '/scheduled-payment',
                  arguments: {
                    'creditorAccount': account,
                    'existingPayment': null,
                  },
                );
                if (result == true && mounted) {
                  _fetchData();
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Новое автопополнение'),
            ),
            body: RefreshIndicator(
              onRefresh: _fetchData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 80.0),
                children: [
                  _buildInfoCard(context, account),
                  const SizedBox(height: 24),
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
                  const SizedBox(height: 24),
                  Text(
                    'Настроенные автопополнения',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Divider(),
                  if (scheduledProvider.isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24.0),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (paymentsForAccount.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24.0),
                      child: Center(
                        child: Text(
                          'Автопополнения для этого счета не настроены.',
                        ),
                      ),
                    )
                  else
                    ...paymentsForAccount.map((payment) {
                      final debtorAccount = scheduledProvider.allUserAccounts
                          .firstWhere(
                            (acc) => acc.id == payment.debtorAccountId,
                            orElse: () => account,
                          );
                      return ScheduledPaymentInfoCard(
                        payment: payment,
                        debtorAccount: debtorAccount,
                        creditorAccount: account,
                        turnoverForPreview: _turnoverPreviews[payment.id],
                        isPreviewLoading:
                            _isLoadingPreviews[payment.id] ?? false,
                      );
                    }).toList(),

                  const SizedBox(height: 24),
                  Text(
                    'Автосписания с этого счета',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Divider(),
                  if (scheduledProvider.isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24.0),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (debitsForAccount.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24.0),
                      child: Center(
                        child: Text('Автосписания с этого счета не настроены.'),
                      ),
                    )
                  else
                    ...debitsForAccount.map((payment) {
                      final creditorAccount = scheduledProvider.allUserAccounts
                          .firstWhere(
                            (acc) => acc.id == payment.creditorAccountId,
                            orElse: () => account,
                          );
                      return ScheduledPaymentInfoCard(
                        payment: payment,
                        debtorAccount: account,
                        creditorAccount: creditorAccount,
                        isDebitView: true,
                        turnoverForPreview: _turnoverPreviews[payment.id],
                        isPreviewLoading:
                            _isLoadingPreviews[payment.id] ?? false,
                      );
                    }).toList(),
                ],
              ),
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
      /* not found */
    }
    try {
      bookedBalance = account.balances.firstWhere(
        (b) => b.type == 'InterimBooked',
      );
    } catch (e) {
      /* not found */
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
