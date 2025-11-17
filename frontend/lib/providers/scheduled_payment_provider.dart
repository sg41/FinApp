// lib/providers/scheduled_payment_provider.dart

import 'package:flutter/material.dart';
import '../models/account.dart';
import '../models/scheduled_payment.dart';
import '../services/api_service.dart';
import 'accounts_provider.dart';
import 'auth_provider.dart';

class ScheduledPaymentProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final AuthProvider? authProvider;

  // Храним платежи в карте для быстрого доступа по ID счета-получателя
  Map<int, ScheduledPayment> _paymentsByCreditorAccount = {};
  List<Account> _allUserAccounts = [];
  bool _isLoading = false;

  ScheduledPaymentProvider(this.authProvider);

  bool get isLoading => _isLoading;
  List<Account> get allUserAccounts => _allUserAccounts;

  // Метод для получения настроек автоплатежа для конкретного счета
  ScheduledPayment? getPaymentForAccount(int creditorAccountId) {
    return _paymentsByCreditorAccount[creditorAccountId];
  }

  // Загружаем все данные, необходимые для работы
  Future<void> fetchData(AccountsProvider accountsProvider) async {
    if (authProvider == null || !authProvider!.isAuthenticated) return;
    _isLoading = true;
    notifyListeners();

    try {
      // Загружаем все настроенные автоплатежи
      final payments = await _apiService.getScheduledPayments(
        authProvider!.token!,
        authProvider!.userId!,
      );
      _paymentsByCreditorAccount = {
        for (var p in payments) p.creditorAccountId: p,
      };

      // Получаем список всех счетов пользователя из другого провайдера
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

  // Универсальный метод для сохранения (создания или обновления)
  Future<void> savePayment(Map<String, dynamic> data) async {
    if (authProvider == null || !authProvider!.isAuthenticated) return;

    final existingPayment = getPaymentForAccount(data['creditor_account_id']);

    if (existingPayment != null) {
      // Обновляем существующий
      await _apiService.updateScheduledPayment(
        authProvider!.token!,
        authProvider!.userId!,
        existingPayment.id,
        data,
      );
    } else {
      // Создаем новый
      await _apiService.createScheduledPayment(
        authProvider!.token!,
        authProvider!.userId!,
        data,
      );
    }
    // После сохранения перезагружаем данные, чтобы UI обновился
    final tempAccountsProvider = AccountsProvider(authProvider);
    await fetchData(tempAccountsProvider);
  }

  // Метод для удаления
  Future<void> deletePayment(int paymentId) async {
    if (authProvider == null || !authProvider!.isAuthenticated) return;
    await _apiService.deleteScheduledPayment(
      authProvider!.token!,
      authProvider!.userId!,
      paymentId,
    );
    final tempAccountsProvider = AccountsProvider(authProvider);
    await fetchData(tempAccountsProvider);
  }
}
