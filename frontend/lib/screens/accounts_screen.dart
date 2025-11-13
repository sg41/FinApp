// lib/screens/accounts_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/accounts_provider.dart';
import '../providers/connections_provider.dart';
import '../utils/formatting.dart';
import '../providers/account_details_provider.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  _AccountsScreenState createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final accountsProvider = Provider.of<AccountsProvider>(
        context,
        listen: false,
      );
      final connectionsProvider = Provider.of<ConnectionsProvider>(
        context,
        listen: false,
      );
      accountsProvider.refreshAllData(
        connectionsProvider: connectionsProvider,
        isInitialLoad: true,
      );
    });
  }

  Future<void> _triggerFullRefresh() async {
    try {
      final accountsProvider = Provider.of<AccountsProvider>(
        context,
        listen: false,
      );
      final connectionsProvider = Provider.of<ConnectionsProvider>(
        context,
        listen: false,
      );
      await accountsProvider.refreshAllData(
        connectionsProvider: connectionsProvider,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Данные успешно обновлены.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при обновлении: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _navigateToConnections() async {
    final result = await Navigator.of(context).pushNamed('/connections');
    if (result == true && mounted) {
      _triggerFullRefresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Получаем провайдер один раз, чтобы не вызывать его в цикле
    final accountDetailsProvider = Provider.of<AccountDetailsProvider>(
      context,
      listen: false,
    );

    return Consumer<AccountsProvider>(
      builder: (ctx, accountsProvider, child) {
        Widget? appBarTitle;
        Widget body;

        if (accountsProvider.isRefreshing) {
          body = const Center(child: CircularProgressIndicator());
        } else if (accountsProvider.errorMessage != null) {
          body = Center(
            child: Text(
              'Ошибка загрузки счетов: ${accountsProvider.errorMessage}',
            ),
          );
        } else if (accountsProvider.banksWithAccounts.isEmpty) {
          body = const Center(child: Text('Счетов не найдено.'));
        } else {
          final banks = accountsProvider.banksWithAccounts;
          final double grandTotal = accountsProvider.grandTotalBalance;

          appBarTitle = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Мои счета'),
              Text(
                grandTotal.toFormattedCurrency('RUB'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          );

          body = ListView.builder(
            itemCount: banks.length,
            itemBuilder: (ctx, index) {
              final bank = banks[index];
              return Card(
                margin: const EdgeInsets.all(8.0),
                child: ExpansionTile(
                  // VVV ИЗМЕНЕНИЕ ЗДЕСЬ VVV
                  onExpansionChanged: (isExpanded) {
                    if (isExpanded) {
                      // При раскрытии списка предзагружаем данные для каждого счета
                      for (final account in bank.accounts) {
                        accountDetailsProvider.fetchTurnoverForAccount(account);
                      }
                    }
                  },
                  // ^^^ КОНЕЦ ИЗМЕНЕНИЯ ^^^
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        bank.name.toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        bank.totalBalance.toFormattedCurrency('RUB'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  children: bank.accounts.map((account) {
                    final balance = account.balances.isNotEmpty
                        ? account.balances.first
                        : null;

                    return InkWell(
                      mouseCursor: SystemMouseCursors.click,
                      onTap: () async {
                        // VVV ИЗМЕНЕНИЕ ЗДЕСЬ VVV
                        // 1. Просто устанавливаем текущий аккаунт.
                        // Данные уже могут быть предзагружены.
                        accountDetailsProvider.setCurrentAccount(account);

                        // 2. Переходим на экран
                        final changed = await Navigator.of(
                          context,
                        ).pushNamed('/account-details');
                        // ^^^ КОНЕЦ ИЗМЕНЕНИЯ ^^^
                        if (changed == true) {
                          _triggerFullRefresh();
                        }
                      },
                      child: ListTile(
                        title: Text(account.nickname),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ID счета: ${account.apiAccountId}'),
                              Text('ID клиента: ${account.bankClientId}'),
                              if (account.ownerName != null &&
                                  account.ownerName!.isNotEmpty)
                                Text('Владелец: ${account.ownerName!}'),
                              if (account.accountType != null &&
                                  account.accountType!.isNotEmpty)
                                Text('Тип: ${account.accountType!}'),
                              if (account.status != null &&
                                  account.status != 'Enabled')
                                Text(
                                  'Статус: ${account.status!}',
                                  style: TextStyle(
                                    color: Colors.orange.shade800,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        trailing: balance != null
                            ? Text(
                                (num.tryParse(balance.amount) ?? 0.0)
                                    .toFormattedCurrency(balance.currency),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : const Text('Нет данных'),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: appBarTitle ?? const Text('Мои счета'),
            actions: [
              if (accountsProvider.isRefreshing)
                const Padding(
                  padding: EdgeInsets.only(right: 16.0),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    ),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Обновить данные',
                  onPressed: _triggerFullRefresh,
                ),
              IconButton(
                icon: const Icon(Icons.link),
                tooltip: 'Мои подключения',
                onPressed: _navigateToConnections,
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Выход',
                onPressed: () {
                  Provider.of<AuthProvider>(context, listen: false).logout();
                },
              ),
            ],
          ),
          body: body,
        );
      },
    );
  }
}
