// lib/providers/banks_provider.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/bank.dart';
import 'auth_provider.dart';

class BanksProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final AuthProvider? authProvider;

  List<Bank> _banks = [];
  bool _isLoading = false;

  BanksProvider(this.authProvider);

  List<Bank> get banks => [..._banks];
  bool get isLoading => _isLoading;

  Future<void> fetchBanks() async {
    if (authProvider == null || !authProvider!.isAuthenticated) return;
    _isLoading = true;
    notifyListeners();
    try {
      _banks = await _apiService.getAvailableBanks(authProvider!.token!);
    } catch (error) {
      print(error); // Для отладки
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}