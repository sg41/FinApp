// lib/screens/add_connection_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../providers/banks_provider.dart';
import '../providers/connections_provider.dart';

class AddConnectionScreen extends StatefulWidget {
  const AddConnectionScreen({super.key});

  @override
  _AddConnectionScreenState createState() => _AddConnectionScreenState();
}

class _AddConnectionScreenState extends State<AddConnectionScreen> {
  final _clientIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<BanksProvider>(context, listen: false).fetchBanks();
    });
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    super.dispose();
  }

  Future<void> _showAddBankDialog(String bankName) async {
    _clientIdController.text = 'team076-';

    final clientId = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Добавить $bankName'),
        content: TextField(
          controller: _clientIdController,
          decoration: const InputDecoration(labelText: 'ID клиента'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop(_clientIdController.text);
            },
            child: const Text('Подключить'),
          ),
        ],
      ),
    );

    if (clientId != null && clientId.isNotEmpty && mounted) {
      final connectionsProvider =
          Provider.of<ConnectionsProvider>(context, listen: false);
      try {
        final response = await connectionsProvider.initiateConnection(
          bankName,
          clientId,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message'] ?? 'Подключение обработано.'),
          ),
        );

        Navigator.of(context).pop(true);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Добавить банк')),
      body: Consumer<BanksProvider>(
        builder: (context, banksProvider, child) {
          if (banksProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (banksProvider.banks.isEmpty) {
            return const Center(child: Text("Нет доступных банков."));
          }

          final banks = banksProvider.banks;
          return ListView.builder(
            itemCount: banks.length,
            itemBuilder: (ctx, i) {
              final bank = banks[i];
              return Card(
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ListTile(
                  leading: SizedBox(
                    width: 40,
                    height: 40,
                    child:
                        bank.iconUrl != null && bank.iconUrl!.endsWith('.svg')
                            ? SvgPicture.network(
                                bank.iconUrl!,
                                placeholderBuilder: (context) =>
                                    const Icon(Icons.business),
                              )
                            : bank.iconUrl != null
                                ? Image.network(
                                    bank.iconUrl!,
                                    errorBuilder: (ctx, err, stack) =>
                                        const Icon(Icons.business),
                                  )
                                : const Icon(Icons.business),
                  ),
                  title: Text(bank.name),
                  trailing: const Icon(Icons.add_circle_outline),
                  onTap: () => _showAddBankDialog(bank.name),
                ),
              );
            },
          );
        },
      ),
    );
  }
}