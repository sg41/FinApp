// lib/providers/scheduled_payment_provider.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Потребуется для дат
import '../models/account.dart';
import '../models/scheduled_payment.dart';
import '../models/turnover_data.dart'; // <-- НОВЫЙ ИМПОРТ
import '../services/api_service.dart';
import 'accounts_provider.dart';
import 'auth_provider.dart';

class ScheduledPaymentProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final AuthProvider? authProvider;

  List<ScheduledPayment> _allPayments = [];
  List<Account> _allUserAccounts = [];
  bool _isLoading = false;

  ScheduledPaymentProvider(this.authProvider);

  bool get isLoading => _isLoading;
  List<Account> get allUserAccounts => _allUserAccounts;

  List<ScheduledPayment> getPaymentsForAccount(int creditorAccountId) {
    return _allPayments
        .where((p) => p.creditorAccountId == creditorAccountId)
        .toList();
  }

  Future<void> fetchData(AccountsProvider accountsProvider) async {
    if (authProvider == null || !authProvider!.isAuthenticated) return;
    _isLoading = true;
    notifyListeners();

    try {
      _allPayments = await _apiService.getScheduledPayments(
        authProvider!.token!,
        authProvider!.userId!,
      );

      _allUserAccounts = accountsProvider.banksWithAccounts
          .expand((bank) => bank.accounts)
          .toList();
    } catch (e) {
      print("Error fetching scheduled payment data: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- НОВЫЙ МЕТОД ДЛЯ ПОЛУЧЕНИЯ ДАННЫХ ДЛЯ ПРЕДПРОСМОТРА ---
  Future<TurnoverData?> fetchTurnoverForPeriod({
    required int accountId,
    required DateTimeRange period,
  }) async {
    if (authProvider == null || !authProvider!.isAuthenticated) return null;

    // Находим полный объект счета, чтобы получить bankId и apiAccountId
    final account = _allUserAccounts.firstWhere(
      (acc) => acc.id == accountId,
      orElse: () {
        throw Exception('Account not found in provider cache');
      },
    );

    try {
      final turnover = await _apiService.getAccountTurnover(
        token: authProvider!.token!,
        userId: authProvider!.userId!,
        bankId: account.bankId,
        apiAccountId: account.apiAccountId,
        from: period.start,
        to: period.end,
      );
      return turnover;
    } catch (e) {
      print("Error fetching turnover for preview: $e");
      // Возвращаем null в случае ошибки, чтобы UI мог это обработать
      return null;
    }
  }
  // --- КОНЕЦ НОВОГО МЕТОДА ---

  Future<void> savePayment({
    required Map<String, dynamic> data,
    int? paymentId,
  }) async {
    if (authProvider == null || !authProvider!.isAuthenticated) return;

    if (paymentId != null) {
      final updatedPayment = await _apiService.updateScheduledPayment(
        authProvider!.token!,
        authProvider!.userId!,
        paymentId,
        data,
      );
      final index = _allPayments.indexWhere((p) => p.id == paymentId);
      if (index != -1) {
        _allPayments[index] = updatedPayment;
      }
    } else {
      final newPayment = await _apiService.createScheduledPayment(
        authProvider!.token!,
        authProvider!.userId!,
        data,
      );
      _allPayments.add(newPayment);
    }
    notifyListeners();
  }

  Future<void> deletePayment(int paymentId) async {
    if (authProvider == null || !authProvider!.isAuthenticated) return;

    await _apiService.deleteScheduledPayment(
      authProvider!.token!,
      authProvider!.userId!,
      paymentId,
    );

    _allPayments.removeWhere((p) => p.id == paymentId);

    notifyListeners();
  }
}
