// lib/providers/account_details_provider.dart

import 'package:flutter/material.dart';
import '../models/account.dart';
import '../models/turnover_data.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

class AccountDetailsProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final AuthProvider? authProvider;

  Account? _currentAccount;
  final Map<int, TurnoverData> _turnoverCache = {};
  final Map<int, bool> _isLoadingMap = {};
  bool _dataChanged = false;

  AccountDetailsProvider(this.authProvider);

  Account? get account => _currentAccount;
  TurnoverData? get turnoverData => _turnoverCache[_currentAccount?.id];
  bool get isLoading => _isLoadingMap[_currentAccount?.id] ?? false;
  bool get dataChanged => _dataChanged;

  void setCurrentAccount(Account account) {
    _currentAccount = account;
    notifyListeners();
  }

  // --- VVV ГЛАВНОЕ ИЗМЕНЕНИЕ: Внутренний метод для загрузки данных VVV ---
  Future<void> _internalFetchAndCacheTurnover(Account accountToFetch) async {
    if (authProvider == null ||
        !authProvider!.isAuthenticated ||
        accountToFetch.statementDate == null ||
        accountToFetch.paymentDate == null) {
      return;
    }
    try {
      final turnover = await _apiService.getAccountTurnover(
        token: authProvider!.token!,
        userId: authProvider!.userId!,
        bankId: accountToFetch.bankId,
        apiAccountId: accountToFetch.apiAccountId,
        from: accountToFetch.statementDate!,
        to: accountToFetch.paymentDate!,
      );
      _turnoverCache[accountToFetch.id] = turnover; // Сохраняем в кэш
    } catch (e) {
      print(
        "Error in _internalFetchAndCacheTurnover for account ${accountToFetch.id}: $e",
      );
    }
  }
  // --- ^^^ КОНЕЦ ИЗМЕНЕНИЯ ^^^

  // Метод для предзагрузки с экрана счетов (остается с проверкой)
  Future<void> fetchTurnoverForAccount(Account accountToFetch) async {
    // Если уже грузится или есть в кэше - ничего не делаем
    if (_isLoadingMap[accountToFetch.id] == true ||
        _turnoverCache.containsKey(accountToFetch.id)) {
      return;
    }

    _isLoadingMap[accountToFetch.id] = true;
    if (accountToFetch.id == _currentAccount?.id) {
      notifyListeners();
    }

    await _internalFetchAndCacheTurnover(
      accountToFetch,
    ); // Вызываем внутренний метод

    _isLoadingMap[accountToFetch.id] = false;
    if (accountToFetch.id == _currentAccount?.id) {
      notifyListeners();
    }
  }

  // --- VVV ИЗМЕНЕННЫЙ МЕТОД: Теперь он работает корректно VVV ---
  Future<void> updateAndRefresh({
    DateTime? statementDate,
    DateTime? paymentDate,
  }) async {
    if (authProvider == null ||
        !authProvider!.isAuthenticated ||
        _currentAccount == null)
      return;

    final accountId = _currentAccount!.id;

    _isLoadingMap[accountId] = true;
    _turnoverCache.remove(accountId); // Очищаем старые обороты из кэша
    notifyListeners();

    try {
      final updatedAccount = await _apiService.updateAccountDates(
        userId: authProvider!.userId!,
        accountId: accountId,
        token: authProvider!.token!,
        statementDate: statementDate,
        paymentDate: paymentDate,
      );

      _currentAccount = updatedAccount; // Обновляем текущий аккаунт
      _dataChanged = true;
      // Уведомим UI, чтобы показать новые даты немедленно
      notifyListeners();

      // Напрямую вызываем внутренний метод, чтобы перезагрузить обороты
      await _internalFetchAndCacheTurnover(updatedAccount);
    } catch (e) {
      print("Error in updateAndRefresh: $e");
    } finally {
      _isLoadingMap[accountId] = false;
      notifyListeners(); // Финальное обновление UI
    }
  }
}
