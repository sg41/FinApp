// lib/features/home/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart'; // <-- Импортируем пакет SVG
import 'package:flutter/foundation.dart'
    show kIsWeb; // <-- ДОБАВЬТЕ ЭТОТ ИМПОРТ
import '../../../core/services/api_service.dart';
import '../../accounts/screens/accounts_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _apiService = ApiService();
  late Future<List<dynamic>> _banks;

  @override
  void initState() {
    super.initState();
    _banks = _apiService.getBanks();
  }

  // ВАЖНО: Эта функция корректирует URL для работы с эмулятором Android
  String _fixLocalhostUrl(String url) {
    // В вебе localhost работает как есть.
    // Проверяем, что мы НЕ в вебе И что платформа - Android.
    if (!kIsWeb && Theme.of(context).platform == TargetPlatform.android) {
      return url.replaceAll('localhost', '10.0.2.2');
    }
    return url;
  }

  Widget _buildBankIcon(String iconUrl) {
    final fixedUrl = _fixLocalhostUrl(iconUrl);

    // Проверяем, является ли иконка SVG
    if (fixedUrl.toLowerCase().endsWith('.svg')) {
      return SvgPicture.network(
        fixedUrl,
        placeholderBuilder: (context) => const CircularProgressIndicator(),
        width: 40,
        height: 40,
      );
    } else {
      // Для других форматов (PNG, JPG) используем Image.network
      return Image.network(
        fixedUrl,
        width: 40,
        height: 40,
        // Виджет, который будет показан во время загрузки
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(child: CircularProgressIndicator());
        },
        // Виджет, который будет показан в случае ошибки загрузки
        errorBuilder: (context, error, stackTrace) {
          return const Icon(Icons.error, size: 40);
        },
      );
    }
  }

  void _connectToBank(String bankName) async {
    // ... (логика подключения остается без изменений)
    try {
      final connection = await _apiService.createConnection(
        bankName,
        "team076-1",
      );
      final connectionId = connection['connection_id'];

      final statusResult = await _apiService.checkConnectionStatus(
        connectionId,
      );

      if (statusResult['status'] == 'success_approved' ||
          statusResult['status'] == 'success_auto_approved') {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                AccountsScreen(accountsData: statusResult['accounts_data']),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Подключение в ожидании: ${statusResult['status']}'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка подключения: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Добро пожаловать в FinApp")),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Подключите свои банковские счета, чтобы управлять финансами в одном месте.",
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            const Text(
              "Доступные банки:",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: FutureBuilder<List<dynamic>>(
                future: _banks,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError) {
                    return Center(child: Text("Ошибка: ${snapshot.error}"));
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(child: Text("Банки не найдены."));
                  } else {
                    return ListView.builder(
                      itemCount: snapshot.data!.length,
                      itemBuilder: (context, index) {
                        final bank = snapshot.data![index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 8,
                          ),
                          child: ListTile(
                            // Используем свой виджет для отображения иконки
                            leading: _buildBankIcon(bank['icon_url']),
                            title: Text(bank['name']),
                            onTap: () => _connectToBank(bank['name']),
                          ),
                        );
                      },
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
