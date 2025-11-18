// lib/screens/scheduled_payment_screen.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../models/scheduled_payment.dart';
import '../providers/accounts_provider.dart';
import '../providers/scheduled_payment_provider.dart';
import '../utils/formatting.dart';

class ScheduledPaymentScreen extends StatefulWidget {
  const ScheduledPaymentScreen({super.key});

  @override
  State<ScheduledPaymentScreen> createState() => _ScheduledPaymentScreenState();
}

class _ScheduledPaymentScreenState extends State<ScheduledPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fixedAmountController = TextEditingController();
  // vvv НОВЫЙ КОНТРОЛЛЕР vvv
  final _percentageController = TextEditingController();
  // ^^^ КОНЕЦ ^^^

  Account? _creditorAccount;
  ScheduledPayment? _existingPayment;

  AmountType _selectedAmountType = AmountType.fixed;
  int? _selectedDebtorAccountId;
  int _paymentDay = 15;
  int _statementDay = 25;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _creditorAccount =
            ModalRoute.of(context)!.settings.arguments as Account;
        _fetchInitialData();
      }
    });
  }

  Future<void> _fetchInitialData() async {
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
          // vvv ЗАПОЛНЯЕМ НОВОЕ ПОЛЕ vvv
          if (_existingPayment!.minimumPaymentPercentage != null) {
            _percentageController.text = _existingPayment!
                .minimumPaymentPercentage
                .toString();
          }
          // ^^^ КОНЕЦ ^^^
        }
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _fixedAmountController.dispose();
    _percentageController.dispose(); // <-- НЕ ЗАБЫТЬ
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
      // vvv ДОБАВЛЯЕМ НОВОЕ ПОЛЕ В ЗАПРОС vvv
      'minimum_payment_percentage':
          _selectedAmountType == AmountType.minimum_payment
          ? double.tryParse(_percentageController.text)
          : null,
      // ^^^ КОНЕЦ ^^^
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
    final appBarTitle = _isLoading
        ? 'Загрузка...'
        : (_existingPayment == null
              ? 'Настройка автопополнения счета'
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
                                labelText: 'Переводить со счета',
                              ),
                              isExpanded: true,
                              itemHeight: 60,
                              selectedItemBuilder: (BuildContext context) {
                                return availableAccounts.map<Widget>((
                                  Account account,
                                ) {
                                  return Text(
                                    '${account.nickname} (${account.bankName.toUpperCase()})',
                                    overflow: TextOverflow.ellipsis,
                                  );
                                }).toList();
                              },
                              items: availableAccounts.map((Account account) {
                                final balance = account.availableBalance;
                                final balanceText = balance != null
                                    ? (num.tryParse(balance.amount) ?? 0.0)
                                          .toFormattedCurrency(balance.currency)
                                    : 'Баланс н/д';

                                return DropdownMenuItem<int>(
                                  value: account.id,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '${account.nickname} (${account.bankName.toUpperCase()})',
                                        style: const TextStyle(fontSize: 16),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text.rich(
                                        TextSpan(
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey.shade700,
                                          ),
                                          children: [
                                            TextSpan(
                                              text:
                                                  '${account.bankClientId}     ',
                                            ),
                                            TextSpan(
                                              text: balanceText,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
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
                                // --- ОБНОВЛЕННОЕ УСЛОВИЕ ---
                                if (_selectedAmountType ==
                                        AmountType.total_debit ||
                                    _selectedAmountType ==
                                        AmountType.net_debit ||
                                    _selectedAmountType ==
                                        AmountType.minimum_payment) ...[
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: DropdownButtonFormField<int>(
                                      value: _statementDay,
                                      decoration: const InputDecoration(
                                        labelText: 'День выписки',
                                      ),
                                      items:
                                          List.generate(
                                                28,
                                                (index) => index + 1,
                                              )
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
                            // vvv НОВЫЙ БЛОК ДЛЯ МИНИМАЛЬНОГО ПЛАТЕЖА vvv
                            RadioListTile<AmountType>(
                              title: const Text('Минимальный платеж'),
                              value: AmountType.minimum_payment,
                              groupValue: _selectedAmountType,
                              onChanged: (val) =>
                                  setState(() => _selectedAmountType = val!),
                            ),
                            Visibility(
                              visible:
                                  _selectedAmountType ==
                                  AmountType.minimum_payment,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  left: 16.0,
                                  right: 16.0,
                                  bottom: 8.0,
                                ),
                                child: TextFormField(
                                  controller: _percentageController,
                                  decoration: const InputDecoration(
                                    labelText: 'Процент от суммы долга',
                                    suffixText: '%',
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  validator: (value) {
                                    if (_selectedAmountType ==
                                        AmountType.minimum_payment) {
                                      if (value == null ||
                                          value.isEmpty ||
                                          (double.tryParse(value) ?? 0) <= 0) {
                                        return 'Введите процент больше нуля';
                                      }
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ),
                            // ^^^ КОНЕЦ НОВОГО БЛОКА ^^^
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
