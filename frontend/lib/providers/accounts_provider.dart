// lib/providers/accounts_provider.dart

import 'package:flutter/material.dart';
import '../models/account.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';
import 'connections_provider.dart'; // Импорт остаётся

class AccountsProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final AuthProvider? authProvider;
  // --- УДАЛЯЕМ ConnectionsProvider из свойств ---
  // final ConnectionsProvider? connectionsProvider;

  List<BankWithAccounts> _banksWithAccounts = [];
  bool _isRefreshing = false;
  String? _errorMessage;
  bool _isDisposed = false;

  // --- ИЗМЕНЯЕМ КОНСТРУКТОР ---
  AccountsProvider(this.authProvider);

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  List<BankWithAccounts> get banksWithAccounts => [..._banksWithAccounts];
  bool get isRefreshing => _isRefreshing;
  String? get errorMessage => _errorMessage;

  double get grandTotalBalance {
    return _banksWithAccounts.fold(0.0, (sum, bank) => sum + bank.totalBalance);
  }

  Future<void> _fetchFromDB() async {
    if (authProvider == null || !authProvider!.isAuthenticated) return;
    _banksWithAccounts = await _apiService.getAccounts(
      authProvider!.token!,
      authProvider!.userId!,
    );
    if (_isDisposed) return;
    notifyListeners();
  }

  // --- VVV ИЗМЕНЯЕМ СИГНАТУРУ МЕТОДА VVV ---
  Future<void> refreshAllData({
    required ConnectionsProvider connectionsProvider, // Добавляем аргумент
    bool isInitialLoad = false,
  }) async {
    if (authProvider == null || !authProvider!.isAuthenticated) return;
    if (_isRefreshing) return;

    _isRefreshing = true;
    _errorMessage = null;
    if (isInitialLoad) {
      if (_isDisposed) return;
      notifyListeners();
    }

    try {
      // 1. Обновляем список подключений, используя переданный провайдер
      await connectionsProvider.fetchConnections();
      if (_isDisposed) return;
      final connections = connectionsProvider.connections;

      // 2. Запускаем фоновое обновление данных для каждого подключения
      final List<Future<void>> allTasks = [];
      for (final conn in connections) {
        if (conn.status == 'active') {
          allTasks.add(
            _apiService.refreshConnection(
              authProvider!.token!,
              authProvider!.userId!,
              conn.id,
            ),
          );
        } else if (conn.status == 'awaitingauthorization') {
          allTasks.add(
            _apiService.checkConsentStatus(
              authProvider!.token!,
              authProvider!.userId!,
              conn.id,
            ),
          );
        }
      }
      await Future.wait(allTasks, eagerError: false);
      if (_isDisposed) return;

      await _fetchFromDB();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isRefreshing = false;
      if (_isDisposed) return;
      notifyListeners();
    }
  }
}
