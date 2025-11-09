// lib/screens/account_details_screen.dart

import 'package:finapp/models/turnover_data.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/account.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/formatting.dart';

class AccountDetailsScreen extends StatefulWidget {
  const AccountDetailsScreen({super.key});

  @override
  _AccountDetailsScreenState createState() => _AccountDetailsScreenState();
}

class _AccountDetailsScreenState extends State<AccountDetailsScreen> {
  late Account _account;
  DateTime? _statementDate;
  DateTime? _paymentDate;
  TurnoverData? _turnoverData;
  bool _isLoadingTurnover = false;
  bool _dataChanged = false; // Флаг для возврата на предыдущий экран

  final ApiService _apiService = ApiService();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Получаем аккаунт из аргументов маршрута
    _account = ModalRoute.of(context)!.settings.arguments as Account;
    _statementDate = _account.statementDate;
    _paymentDate = _account.paymentDate;
    // Сразу пытаемся загрузить обороты, если даты уже есть
    _fetchTurnover();
  }

  Future<void> _selectDate(BuildContext context, bool isStatementDate) async {
    final initialDate =
        (isStatementDate ? _statementDate : _paymentDate) ?? DateTime.now();
    final newDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (newDate != null) {
      setState(() {
        if (isStatementDate) {
          _statementDate = newDate;
        } else {
          _paymentDate = newDate;
        }
      });
      await _saveDates();
      await _fetchTurnover();
    }
  }

  Future<void> _saveDates() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    try {
      final updatedAccount = await _apiService.updateAccountDates(
        userId: authProvider.userId!,
        accountId: _account.id,
        token: authProvider.token!,
        statementDate: _statementDate,
        paymentDate: _paymentDate,
      );
      // Обновляем локальный стейт аккаунта
      setState(() {
        _account = updatedAccount;
        _dataChanged = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Даты сохранены'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка сохранения: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _fetchTurnover() async {
    if (_statementDate == null || _paymentDate == null) {
      return;
    }

    setState(() {
      _isLoadingTurnover = true;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    try {
      final turnover = await _apiService.getAccountTurnover(
        token: authProvider.token!,
        userId: authProvider.userId!,
        bankId: _account.bankId,
        apiAccountId: _account.apiAccountId,
        from: _statementDate!,
        to: _paymentDate!,
      );
      setState(() {
        _turnoverData = turnover;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки оборотов: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        _isLoadingTurnover = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) {
        if (didPop) return;
        Navigator.of(context).pop(_dataChanged);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_account.nickname),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildInfoCard(),
            const SizedBox(height: 16),
            _buildDatesCard(),
            const SizedBox(height: 16),
            if (_isLoadingTurnover)
              const Center(child: CircularProgressIndicator())
            else if (_turnoverData != null)
              _buildTurnoverCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Основная информация', style: Theme.of(context).textTheme.titleLarge),
            const Divider(),
            _buildInfoRow('Банк:', _account.bankName.toUpperCase()),
            if (_account.ownerName != null) _buildInfoRow('Владелец:', _account.ownerName!),
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
                  (num.tryParse(b.amount) ?? 0)
                      .toFormattedCurrency(b.currency)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Отчетный период', style: Theme.of(context).textTheme.titleLarge),
            const Divider(),
            ListTile(
              title: const Text('Дата выписки'),
              subtitle: Text(_statementDate != null
                  ? DateFormat('dd.MM.yyyy').format(_statementDate!)
                  : 'Не указана'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () => _selectDate(context, true),
            ),
            ListTile(
              title: const Text('Дата платежа'),
              subtitle: Text(_paymentDate != null
                  ? DateFormat('dd.MM.yyyy').format(_paymentDate!)
                  : 'Не указана'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () => _selectDate(context, false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTurnoverCard() {
    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Обороты за период', style: Theme.of(context).textTheme.titleLarge),
            const Divider(),
            _buildInfoRow(
              'Приход:',
              _turnoverData!.totalCredit
                  .toFormattedCurrency(_turnoverData!.currency),
              valueColor: Colors.green[700],
            ),
            _buildInfoRow(
              'Расход:',
              _turnoverData!.totalDebit
                  .toFormattedCurrency(_turnoverData!.currency),
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
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: valueColor)),
        ],
      ),
    );
  }
}