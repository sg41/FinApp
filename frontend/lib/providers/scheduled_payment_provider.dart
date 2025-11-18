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

  // --- ИЗМЕНЕНИЕ 1: Упрощенный и эффективный метод сохранения ---
  Future<void> savePayment({
    required Map<String, dynamic> data,
    int? paymentId,
  }) async {
    if (authProvider == null || !authProvider!.isAuthenticated) return;

    if (paymentId != null) {
      // --- РЕЖИМ ОБНОВЛЕНИЯ ---
      final updatedPayment = await _apiService.updateScheduledPayment(
        authProvider!.token!,
        authProvider!.userId!,
        paymentId,
        data,
      );
      // Находим индекс старого платежа и заменяем его на обновленный
      final index = _allPayments.indexWhere((p) => p.id == paymentId);
      if (index != -1) {
        _allPayments[index] = updatedPayment;
      }
    } else {
      // --- РЕЖИМ СОЗДАНИЯ ---
      final newPayment = await _apiService.createScheduledPayment(
        authProvider!.token!,
        authProvider!.userId!,
        data,
      );
      // Просто добавляем новый платеж в список
      _allPayments.add(newPayment);
    }
    // Уведомляем слушателей об изменении списка
    notifyListeners();
  }

  // --- ИЗМЕНЕНИЕ 2: Упрощенный и эффективный метод удаления ---
  Future<void> deletePayment(int paymentId) async {
    if (authProvider == null || !authProvider!.isAuthenticated) return;

    await _apiService.deleteScheduledPayment(
      authProvider!.token!,
      authProvider!.userId!,
      paymentId,
    );

    // Просто удаляем платеж из локального списка
    _allPayments.removeWhere((p) => p.id == paymentId);

    // Уведомляем слушателей об изменении
    notifyListeners();
  }
}
