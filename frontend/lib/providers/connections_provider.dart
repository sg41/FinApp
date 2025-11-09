// lib/providers/connections_provider.dart
import 'package:flutter/material.dart';
import '../models/connection.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

class ConnectionsProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final AuthProvider? authProvider;

  List<Connection> _connections = [];
  bool _isLoading = false;
  String? _errorMessage;

  ConnectionsProvider(this.authProvider);

  List<Connection> get connections => [..._connections];
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> fetchConnections() async {
    if (authProvider == null || !authProvider!.isAuthenticated) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _connections = await _apiService.getConnections(authProvider!.token!, authProvider!.userId!);
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteConnection(int connectionId) async {
    if (authProvider == null || !authProvider!.isAuthenticated) return;
    try {
      await _apiService.deleteConnection(authProvider!.token!, authProvider!.userId!, connectionId);
      _connections.removeWhere((conn) => conn.id == connectionId);
      notifyListeners();
    } catch (e) {
      print(e); // Для отладки
      rethrow;
    }
  }

  Future<Map<String, dynamic>> initiateConnection(String bankName, String bankClientId) async {
    if (authProvider == null || !authProvider!.isAuthenticated) {
      throw Exception("Not authenticated");
    }
    final response = await _apiService.initiateConnection(authProvider!.token!, authProvider!.userId!, bankName, bankClientId);
    // После инициации обновляем список, чтобы показать новое подключение
    await fetchConnections();
    return response;
  }
}