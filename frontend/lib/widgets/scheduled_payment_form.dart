// lib/widgets/scheduled_payment_form.dart (новый файл)

import 'package:flutter/material.dart';

class ScheduledPaymentForm extends StatefulWidget {
  const ScheduledPaymentForm({super.key});

  @override
  State<ScheduledPaymentForm> createState() => _ScheduledPaymentFormState();
}

class _ScheduledPaymentFormState extends State<ScheduledPaymentForm> {
  // Здесь будут контроллеры и переменные для хранения состояния формы
  int? _selectedDebtorAccountId;
  int _paymentDay = 15;
  int _statementDay = 25;
  // ... и так далее

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.amber[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Настройка автоплатежа', style: Theme.of(context).textTheme.titleLarge),
            const Divider(),
            
            // Здесь будут поля формы:
            // 1. Dropdown для выбора счета списания
            // 2. Dropdown/TextField для выбора дня платежа
            // 3. Dropdown/TextField для выбора дня выписки
            // 4. Radio buttons для выбора типа суммы
            // 5. TextField для фиксированной суммы (если выбран)
            
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () {}, child: const Text('Отмена')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: () {}, child: const Text('Сохранить')),
              ],
            )
          ],
        ),
      ),
    );
  }
}