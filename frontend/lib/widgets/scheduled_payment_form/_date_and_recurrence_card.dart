// lib/widgets/scheduled_payment_form/_date_and_recurrence_card.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/scheduled_payment.dart';

class DateAndRecurrenceCard extends StatelessWidget {
  final DateTime nextPaymentDate;
  final ValueChanged<DateTime> onDateChanged;
  final bool isRecurring;
  final ValueChanged<bool> onIsRecurringChanged;
  final TextEditingController recurrenceIntervalController;
  final RecurrenceType? selectedRecurrenceType;
  final ValueChanged<RecurrenceType?> onRecurrenceTypeChanged;

  const DateAndRecurrenceCard({
    super.key,
    required this.nextPaymentDate,
    required this.onDateChanged,
    required this.isRecurring,
    required this.onIsRecurringChanged,
    required this.recurrenceIntervalController,
    required this.selectedRecurrenceType,
    required this.onRecurrenceTypeChanged,
  });

  Future<void> _pickDate(BuildContext context) async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: nextPaymentDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (pickedDate != null) {
      onDateChanged(pickedDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                'Дата и повторения',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(),
            ListTile(
              title: const Text('Дата следующего платежа'),
              subtitle: Text(
                DateFormat('dd MMMM yyyy').format(nextPaymentDate),
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: () => _pickDate(context),
            ),
            SwitchListTile(
              title: const Text('Повторять платеж'),
              value: isRecurring,
              onChanged: onIsRecurringChanged,
            ),
            if (isRecurring)
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: recurrenceIntervalController,
                        decoration: const InputDecoration(labelText: 'Каждые'),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (isRecurring &&
                              (int.tryParse(v ?? '0') ?? 0) < 1) {
                            return 'Введите > 0';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<RecurrenceType>(
                        value: selectedRecurrenceType,
                        hint: const Text('Период'),
                        items: RecurrenceType.values
                            .map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(describeEnum(type)),
                              ),
                            )
                            .toList(),
                        onChanged: onRecurrenceTypeChanged,
                        validator: (v) {
                          if (isRecurring && v == null) {
                            return 'Выберите';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
