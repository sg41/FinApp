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

  // --- ИЗМЕНЕНИЕ 1: Храним все платежи в одном списке, а не в карте ---
  List<ScheduledPayment> _allPayments = [];
  List<Account> _allUserAccounts = [];
  bool _isLoading = false;

  ScheduledPaymentProvider(this.authProvider);

  bool get isLoading => _isLoading;
  List<Account> get allUserAccounts => _allUserAccounts;

  // --- ИЗМЕНЕНИЕ 2: Метод для получения ВСЕХ автоплатежей для конкретного счета ---
  List<ScheduledPayment> getPaymentsForAccount(int creditorAccountId) {
    return _allPayments
        .where((p) => p.creditorAccountId == creditorAccountId)
        .toList();
  }

  // Загружаем все данные, необходимые для работы
  Future<void> fetchData(AccountsProvider accountsProvider) async {
    if (authProvider == null || !authProvider!.isAuthenticated) return;
    _isLoading = true;
    notifyListeners();

    try {
      // --- ИЗМЕНЕНИЕ 3: Просто загружаем все настроенные автоплатежи в список ---
      _allPayments = await _apiService.getScheduledPayments(
        authProvider!.token!,
        authProvider!.userId!,
      );

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

  // --- ИЗМЕНЕНИЕ 4: Универсальный метод для сохранения (создания ИЛИ обновления) ---
  Future<void> savePayment({
    required Map<String, dynamic> data,
    int? paymentId, // Необязательный ID для режима обновления
  }) async {
    if (authProvider == null || !authProvider!.isAuthenticated) return;

    if (paymentId != null) {
      // Обновляем существующий платеж
      await _apiService.updateScheduledPayment(
        authProvider!.token!,
        authProvider!.userId!,
        paymentId,
        data,
      );
    } else {
      // Создаем новый платеж
      await _apiService.createScheduledPayment(
        authProvider!.token!,
        authProvider!.userId!,
        data,
      );
    }
    // После сохранения перезагружаем данные, чтобы UI обновился
    // Создаем временный AccountsProvider, так как у нас нет прямого доступа к нему здесь
    final tempAccountsProvider = AccountsProvider(authProvider);
    await fetchData(tempAccountsProvider);
  }

  // Метод для удаления (остается без изменений)
  Future<void> deletePayment(int paymentId) async {
    if (authProvider == null || !authProvider!.isAuthenticated) return;
    await _apiService.deleteScheduledPayment(
      authProvider!.token!,
      authProvider!.userId!,
      paymentId,
    );
    // Перезагружаем данные после удаления
    final tempAccountsProvider = AccountsProvider(authProvider);
    await fetchData(tempAccountsProvider);
  }
}
