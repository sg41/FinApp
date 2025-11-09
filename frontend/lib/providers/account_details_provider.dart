// lib/providers/account_details_provider.dart

import 'package:flutter/material.dart';
import '../models/account.dart';
import '../models/turnover_data.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

class AccountDetailsProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final AuthProvider? authProvider;

  Account? _account;
  TurnoverData? _turnoverData;
  bool _isLoading = false;
  bool _dataChanged = false;

  AccountDetailsProvider(this.authProvider);

  // Геттеры для доступа к состоянию из UI
  Account? get account => _account;
  TurnoverData? get turnoverData => _turnoverData;
  bool get isLoading => _isLoading;
  bool get dataChanged => _dataChanged;

  // Метод для первоначальной инициализации состояния
  void initialize(Account initialAccount) {
    if (_account?.id != initialAccount.id) {
      _account = initialAccount;
      _turnoverData = null;
      _dataChanged = false;
      _isLoading = false;
      // Уведомляем виджеты, чтобы они отобразили начальные данные
      notifyListeners(); 
      // Запускаем загрузку оборотов для начальных дат
      fetchTurnover();
    }
  }

  Future<void> updateAndRefresh({DateTime? statementDate, DateTime? paymentDate}) async {
    if (authProvider == null || !authProvider!.isAuthenticated || _account == null) return;

    _isLoading = true;
    _turnoverData = null; // Очищаем старые обороты
    notifyListeners();

    try {
      // 1. Сохраняем и получаем обновленный аккаунт
      final updatedAccount = await _apiService.updateAccountDates(
        userId: authProvider!.userId!,
        accountId: _account!.id,
        token: authProvider!.token!,
        statementDate: statementDate,
        paymentDate: paymentDate,
      );
      
      _account = updatedAccount;
      _dataChanged = true;
      notifyListeners(); // Обновляем UI с новыми датами

      // 2. Загружаем обороты для новых дат
      await fetchTurnover();

    } catch (e) {
      print("Error in updateAndRefresh: $e");
      // Можно добавить обработку ошибок для UI
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchTurnover() async {
    if (authProvider == null || !authProvider!.isAuthenticated || _account == null || _account!.statementDate == null || _account!.paymentDate == null) {
      return;
    }

    _isLoading = true;
    notifyListeners();
    
    try {
      final turnover = await _apiService.getAccountTurnover(
        token: authProvider!.token!,
        userId: authProvider!.userId!,
        bankId: _account!.bankId,
        apiAccountId: _account!.apiAccountId,
        from: _account!.statementDate!,
        to: _account!.paymentDate!,
      );
      _turnoverData = turnover;
    } catch (e) {
      print("Error in fetchTurnover: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}