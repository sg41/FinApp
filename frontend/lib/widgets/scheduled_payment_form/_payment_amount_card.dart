// lib/widgets/scheduled_payment_form/_payment_amount_card.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/scheduled_payment.dart';

class PaymentAmountCard extends StatelessWidget {
  final AmountType selectedAmountType;
  final ValueChanged<AmountType?> onAmountTypeChanged;
  final TextEditingController fixedAmountController;
  final TextEditingController percentageController;
  final DateTimeRange? period;
  final ValueChanged<DateTimeRange> onPeriodChanged;
  final String? previewAmountText;
  final bool isCalculatingPreview;
  // --- НОВОЕ ИЗМЕНЕНИЕ: Добавляем колбэк для пересчета ---
  final VoidCallback onRecalculatePreview;

  const PaymentAmountCard({
    super.key,
    required this.selectedAmountType,
    required this.onAmountTypeChanged,
    required this.fixedAmountController,
    required this.percentageController,
    required this.period,
    required this.onPeriodChanged,
    this.previewAmountText,
    required this.isCalculatingPreview,
    required this.onRecalculatePreview, // <-- Инициализируем его
  });

  Future<void> _pickDateRange(
    BuildContext context,
    FormFieldState<DateTimeRange> field,
  ) async {
    final pickedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: field.value ?? period,
    );
    if (pickedRange != null) {
      field.didChange(pickedRange);
      onPeriodChanged(pickedRange);
    }
  }

  Widget _buildPreviewAmount() {
    if (isCalculatingPreview) {
      return const Padding(
        padding: EdgeInsets.only(right: 8.0),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (previewAmountText != null) {
      return Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: Text(
          previewAmountText!,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
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
                'Сумма платежа',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(),
            RadioListTile<AmountType>(
              title: const Text('Фиксированная сумма'),
              value: AmountType.fixed,
              groupValue: selectedAmountType,
              onChanged: onAmountTypeChanged,
            ),
            if (selectedAmountType == AmountType.fixed)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: TextFormField(
                  controller: fixedAmountController,
                  decoration: const InputDecoration(
                    labelText: 'Сумма',
                    suffixText: 'RUB',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) {
                    if (selectedAmountType == AmountType.fixed &&
                        (value == null ||
                            value.isEmpty ||
                            (double.tryParse(value) ?? 0) <= 0)) {
                      return 'Введите сумму больше нуля';
                    }
                    return null;
                  },
                ),
              ),
            RadioListTile<AmountType>(
              title: Row(
                children: [
                  const Text('Все расходы за период'),
                  const Spacer(),
                  if (selectedAmountType == AmountType.total_debit)
                    _buildPreviewAmount(),
                ],
              ),
              value: AmountType.total_debit,
              groupValue: selectedAmountType,
              onChanged: onAmountTypeChanged,
            ),
            RadioListTile<AmountType>(
              title: Row(
                children: [
                  const Text('Разница расходов и доходов (долг)'),
                  const Spacer(),
                  if (selectedAmountType == AmountType.net_debit)
                    _buildPreviewAmount(),
                ],
              ),
              value: AmountType.net_debit,
              groupValue: selectedAmountType,
              onChanged: onAmountTypeChanged,
            ),
            RadioListTile<AmountType>(
              title: Row(
                children: [
                  const Text('Минимальный платеж'),
                  const Spacer(),
                  if (selectedAmountType == AmountType.minimum_payment)
                    _buildPreviewAmount(),
                ],
              ),
              value: AmountType.minimum_payment,
              groupValue: selectedAmountType,
              onChanged: onAmountTypeChanged,
            ),
            if (selectedAmountType == AmountType.minimum_payment)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: TextFormField(
                  controller: percentageController,
                  // --- ГЛАВНОЕ ИЗМЕНЕНИЕ ЗДЕСЬ ---
                  onChanged: (_) =>
                      onRecalculatePreview(), // Вызываем колбэк при изменении текста
                  decoration: const InputDecoration(
                    labelText: 'Процент от суммы долга',
                    suffixText: '%',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) {
                    if (selectedAmountType == AmountType.minimum_payment &&
                        (value == null ||
                            value.isEmpty ||
                            (double.tryParse(value) ?? 0) <= 0)) {
                      return 'Введите процент больше нуля';
                    }
                    return null;
                  },
                ),
              ),
            if (selectedAmountType != AmountType.fixed)
              FormField<DateTimeRange>(
                initialValue: period,
                validator: (value) {
                  final requiresPeriod =
                      selectedAmountType == AmountType.total_debit ||
                      selectedAmountType == AmountType.net_debit ||
                      selectedAmountType == AmountType.minimum_payment;
                  if (requiresPeriod && value == null) {
                    return 'Выберите период для расчета суммы';
                  }
                  return null;
                },
                builder: (field) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        title: const Text('Период для расчета'),
                        subtitle: field.value == null
                            ? const Text('Не выбран')
                            : Text(
                                '${DateFormat('dd.MM.yy').format(field.value!.start)} - ${DateFormat('dd.MM.yy').format(field.value!.end)}',
                              ),
                        trailing: const Icon(Icons.date_range),
                        onTap: () => _pickDateRange(context, field),
                      ),
                      if (field.hasError)
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 16.0,
                            bottom: 8.0,
                          ),
                          child: Text(
                            field.errorText!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
