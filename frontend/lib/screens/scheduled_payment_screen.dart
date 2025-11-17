// lib/screens/scheduled_payment_screen.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../models/scheduled_payment.dart';
import '../providers/accounts_provider.dart';
import '../providers/scheduled_payment_provider.dart';

class ScheduledPaymentScreen extends StatefulWidget {
  const ScheduledPaymentScreen({super.key});

  @override
  State<ScheduledPaymentScreen> createState() => _ScheduledPaymentScreenState();
}

class _ScheduledPaymentScreenState extends State<ScheduledPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fixedAmountController = TextEditingController();

  // --- vvv ИСПРАВЛЕННАЯ ЛОГИКА ИНИЦИАЛИЗАЦИИ vvv ---

  // Делаем поле nullable, чтобы избежать LateInitializationError
  Account? _creditorAccount;
  ScheduledPayment? _existingPayment;

  AmountType _selectedAmountType = AmountType.fixed;
  int? _selectedDebtorAccountId;
  int _paymentDay = 15;
  int _statementDay = 25;

  // Экран всегда начинается в состоянии загрузки
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Этот код запланирует выполнение после отрисовки первого кадра.
    // Это самый безопасный способ запустить загрузку данных.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // К этому моменту 'context' уже полностью доступен
      if (mounted) {
        _creditorAccount =
            ModalRoute.of(context)!.settings.arguments as Account;
        _fetchInitialData();
      }
    });
  }

  Future<void> _fetchInitialData() async {
    // setState здесь не нужен, так как _isLoading уже true
    final provider = Provider.of<ScheduledPaymentProvider>(
      context,
      listen: false,
    );
    final accountsProvider = Provider.of<AccountsProvider>(
      context,
      listen: false,
    );

    await provider.fetchData(accountsProvider);

    if (mounted) {
      setState(() {
        _existingPayment = provider.getPaymentForAccount(_creditorAccount!.id);
        if (_existingPayment != null) {
          _selectedAmountType = _existingPayment!.amountType;
          _selectedDebtorAccountId = _existingPayment!.debtorAccountId;
          _paymentDay = _existingPayment!.paymentDayOfMonth;
          _statementDay = _existingPayment!.statementDayOfMonth;
          if (_existingPayment!.fixedAmount != null) {
            _fixedAmountController.text = _existingPayment!.fixedAmount
                .toString();
          }
        }
        // Завершаем загрузку и показываем форму
        _isLoading = false;
      });
    }
  }

  // --- ^^^ КОНЕЦ ИСПРАВЛЕНИЙ ^^^ ---

  @override
  void dispose() {
    _fixedAmountController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (_creditorAccount == null || !_formKey.currentState!.validate()) {
      return;
    }
    _formKey.currentState!.save();

    setState(() => _isLoading = true);

    final provider = Provider.of<ScheduledPaymentProvider>(
      context,
      listen: false,
    );

    final Map<String, dynamic> data = {
      'creditor_account_id': _creditorAccount!.id,
      'debtor_account_id': _selectedDebtorAccountId,
      'payment_day_of_month': _paymentDay,
      'statement_day_of_month': _statementDay,
      'amount_type': describeEnum(_selectedAmountType),
      'fixed_amount': _selectedAmountType == AmountType.fixed
          ? double.tryParse(_fixedAmountController.text)
          : null,
      'is_active': true,
    };

    try {
      await provider.savePayment(data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Настройки автоплатежа сохранены!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Временный заголовок, пока _existingPayment не определен
    final appBarTitle = _isLoading
        ? 'Загрузка...'
        : (_existingPayment == null
              ? 'Новый автоплатеж'
              : 'Изменить автоплатеж');

    return Scaffold(
      appBar: AppBar(title: Text(appBarTitle)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Consumer<ScheduledPaymentProvider>(
                      builder: (context, provider, child) {
                        final availableAccounts = provider.allUserAccounts
                            .where((acc) => acc.id != _creditorAccount?.id)
                            .toList();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DropdownButtonFormField<int>(
                              value: _selectedDebtorAccountId,
                              decoration: const InputDecoration(
                                labelText: 'Платить со счета',
                              ),
                              items: availableAccounts.map((Account account) {
                                return DropdownMenuItem<int>(
                                  value: account.id,
                                  child: Text(
                                    '${account.nickname} (${account.bankName.toUpperCase()})',
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedDebtorAccountId = value;
                                });
                              },
                              validator: (value) =>
                                  value == null ? 'Выберите счет' : null,
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    value: _paymentDay,
                                    decoration: const InputDecoration(
                                      labelText: 'День платежа',
                                    ),
                                    items:
                                        List.generate(28, (index) => index + 1)
                                            .map(
                                              (day) => DropdownMenuItem(
                                                value: day,
                                                child: Text(day.toString()),
                                              ),
                                            )
                                            .toList(),
                                    onChanged: (val) =>
                                        setState(() => _paymentDay = val!),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    value: _statementDay,
                                    decoration: const InputDecoration(
                                      labelText: 'День выписки',
                                    ),
                                    items:
                                        List.generate(28, (index) => index + 1)
                                            .map(
                                              (day) => DropdownMenuItem(
                                                value: day,
                                                child: Text(day.toString()),
                                              ),
                                            )
                                            .toList(),
                                    onChanged: (val) =>
                                        setState(() => _statementDay = val!),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Сумма платежа:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            RadioListTile<AmountType>(
                              title: const Text('Фиксированная сумма'),
                              value: AmountType.fixed,
                              groupValue: _selectedAmountType,
                              onChanged: (val) =>
                                  setState(() => _selectedAmountType = val!),
                            ),
                            Visibility(
                              visible: _selectedAmountType == AmountType.fixed,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  left: 16.0,
                                  right: 16.0,
                                  bottom: 8.0,
                                ),
                                child: TextFormField(
                                  controller: _fixedAmountController,
                                  decoration: const InputDecoration(
                                    labelText: 'Сумма',
                                    suffixText: 'RUB',
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  validator: (value) {
                                    if (_selectedAmountType ==
                                        AmountType.fixed) {
                                      if (value == null ||
                                          value.isEmpty ||
                                          (double.tryParse(value) ?? 0) <= 0) {
                                        return 'Введите сумму больше нуля';
                                      }
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ),
                            RadioListTile<AmountType>(
                              title: const Text('Все расходы за период'),
                              value: AmountType.total_debit,
                              groupValue: _selectedAmountType,
                              onChanged: (val) =>
                                  setState(() => _selectedAmountType = val!),
                            ),
                            RadioListTile<AmountType>(
                              title: const Text(
                                'Разница расходов и доходов (долг)',
                              ),
                              value: AmountType.net_debit,
                              groupValue: _selectedAmountType,
                              onChanged: (val) =>
                                  setState(() => _selectedAmountType = val!),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                ElevatedButton(
                                  onPressed: _submitForm,
                                  child: Text(
                                    _existingPayment == null
                                        ? 'Создать'
                                        : 'Сохранить',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
