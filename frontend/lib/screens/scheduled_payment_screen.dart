// lib/screens/scheduled_payment_screen.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../models/scheduled_payment.dart';
import '../models/turnover_data.dart';
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
  final _percentageController = TextEditingController();
  final _recurrenceIntervalController = TextEditingController(text: '1');

  // Данные, переданные на экран
  Account? _creditorAccount;
  ScheduledPayment? _existingPayment;

  // Состояние формы
  AmountType _selectedAmountType = AmountType.fixed;
  int? _selectedDebtorAccountId;
  DateTime _nextPaymentDate = DateTime.now();
  DateTimeRange? _period;
  RecurrenceType? _selectedRecurrenceType;
  bool _isRecurring = false;

  // Состояние UI
  bool _isInit = true;
  bool _isLoading = true;

  // Состояние для предпросмотра суммы
  bool _isCalculatingPreview = false;
  TurnoverData? _turnoverDataForPreview;
  String? _previewAmountText;

  @override
  void initState() {
    super.initState();
    _percentageController.addListener(_recalculatePreviewText);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInit) {
      final args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
      _creditorAccount = args['creditorAccount'];
      _existingPayment = args['existingPayment'];

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _fetchInitialData();
        }
      });
    }
    _isInit = false;
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
        if (_existingPayment != null) {
          _selectedAmountType = _existingPayment!.amountType;
          _selectedDebtorAccountId = _existingPayment!.debtorAccountId;
          _nextPaymentDate = _existingPayment!.nextPaymentDate;
          if (_existingPayment!.periodStartDate != null &&
              _existingPayment!.periodEndDate != null) {
            _period = DateTimeRange(
              start: _existingPayment!.periodStartDate!,
              end: _existingPayment!.periodEndDate!,
            );
          }
          if (_existingPayment!.recurrenceType != null) {
            _isRecurring = true;
            _selectedRecurrenceType = _existingPayment!.recurrenceType;
            _recurrenceIntervalController.text = _existingPayment!
                .recurrenceInterval
                .toString();
          }
          if (_existingPayment!.fixedAmount != null) {
            _fixedAmountController.text = _existingPayment!.fixedAmount
                .toString();
          }
          if (_existingPayment!.minimumPaymentPercentage != null) {
            _percentageController.text = _existingPayment!
                .minimumPaymentPercentage
                .toString();
          }
        }
        _isLoading = false;
      });
      _onFormChange();
    }
  }

  @override
  void dispose() {
    _fixedAmountController.dispose();
    _percentageController.removeListener(_recalculatePreviewText);
    _percentageController.dispose();
    _recurrenceIntervalController.dispose();
    super.dispose();
  }

  /// Вызывается при изменении периода или типа суммы для запуска перерасчета
  void _onFormChange() {
    // --- ИЗМЕНЕНИЕ 1: Убираем зависимость от счета списания ---
    final needsRecalculation =
        _creditorAccount != null &&
        _period != null &&
        _selectedAmountType != AmountType.fixed;

    if (needsRecalculation) {
      _fetchTurnover();
    } else {
      setState(() {
        _turnoverDataForPreview = null;
        _recalculatePreviewText();
      });
    }
  }

  /// Асинхронно запрашивает данные об оборотах с сервера
  Future<void> _fetchTurnover() async {
    // --- ИЗМЕНЕНИЕ 2: Проверяем _creditorAccount, а не _selectedDebtorAccountId ---
    if (_creditorAccount == null || _period == null) return;

    setState(() {
      _isCalculatingPreview = true;
      _previewAmountText = null;
    });

    final provider = Provider.of<ScheduledPaymentProvider>(
      context,
      listen: false,
    );
    // --- ИЗМЕНЕНИЕ 3: Используем ID счета пополнения (_creditorAccount) ---
    final turnover = await provider.fetchTurnoverForPeriod(
      accountId: _creditorAccount!.id,
      period: _period!,
    );

    if (mounted) {
      setState(() {
        _turnoverDataForPreview = turnover;
        _isCalculatingPreview = false;
        _recalculatePreviewText();
      });
    }
  }

  /// Синхронно вычисляет и форматирует текст предпросмотра
  void _recalculatePreviewText() {
    if (_turnoverDataForPreview == null) {
      setState(() => _previewAmountText = null);
      return;
    }
    double amount = 0;
    bool calculationDone = false;
    switch (_selectedAmountType) {
      case AmountType.total_debit:
        amount = _turnoverDataForPreview!.totalDebit;
        calculationDone = true;
        break;
      case AmountType.net_debit:
        amount =
            _turnoverDataForPreview!.totalDebit -
            _turnoverDataForPreview!.totalCredit;
        calculationDone = true;
        break;
      case AmountType.minimum_payment:
        final percentage = double.tryParse(_percentageController.text) ?? 0.0;
        if (percentage > 0) {
          final debt =
              _turnoverDataForPreview!.totalDebit -
              _turnoverDataForPreview!.totalCredit;
          amount = debt * (percentage / 100);
          calculationDone = true;
        }
        break;
      case AmountType.fixed:
        break;
    }
    if (!calculationDone) {
      setState(() => _previewAmountText = null);
      return;
    }
    if (amount < 0) amount = 0;
    String previewText =
        '~ ${amount.toFormattedCurrency(_turnoverDataForPreview!.currency)}';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_period!.end.isAfter(today)) {
      previewText += ' (на ${DateFormat('dd.MM.yy').format(today)})';
    }
    setState(() => _previewAmountText = previewText);
  }

  Future<void> _pickDate(FormFieldState<DateTime> field) async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: field.value ?? _nextPaymentDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (pickedDate != null) {
      field.didChange(pickedDate);
      setState(() {
        _nextPaymentDate = pickedDate;
      });
    }
  }

  Future<void> _pickDateRange(FormFieldState<DateTimeRange> field) async {
    final pickedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: field.value ?? _period,
    );
    if (pickedRange != null) {
      field.didChange(pickedRange);
      setState(() {
        _period = pickedRange;
        _onFormChange();
      });
    }
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
    String? formatDate(DateTime? dt) => dt?.toIso8601String().substring(0, 10);

    final Map<String, dynamic> data = {
      'creditor_account_id': _creditorAccount!.id,
      'debtor_account_id': _selectedDebtorAccountId,
      'next_payment_date': formatDate(_nextPaymentDate),
      'period_start_date': _selectedAmountType != AmountType.fixed
          ? formatDate(_period?.start)
          : null,
      'period_end_date': _selectedAmountType != AmountType.fixed
          ? formatDate(_period?.end)
          : null,
      'recurrence_type': _isRecurring
          ? describeEnum(_selectedRecurrenceType!)
          : null,
      'recurrence_interval': _isRecurring
          ? int.tryParse(_recurrenceIntervalController.text)
          : null,
      'amount_type': describeEnum(_selectedAmountType),
      'fixed_amount': _selectedAmountType == AmountType.fixed
          ? double.tryParse(_fixedAmountController.text)
          : null,
      'minimum_payment_percentage':
          _selectedAmountType == AmountType.minimum_payment
          ? double.tryParse(_percentageController.text)
          : null,
      'is_active': true,
    };

    try {
      await provider.savePayment(data: data, paymentId: _existingPayment?.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Настройки автопополнения сохранены!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildPreviewAmount() {
    if (_isCalculatingPreview) {
      return const Padding(
        padding: EdgeInsets.only(right: 8.0),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_previewAmountText != null) {
      return Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: Text(
          _previewAmountText!,
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
    final appBarTitle = _existingPayment == null
        ? 'Новое автопополнение'
        : 'Изменить автопополнение';

    return Scaffold(
      appBar: AppBar(title: Text(appBarTitle)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Consumer<ScheduledPaymentProvider>(
                          builder: (context, provider, child) {
                            final availableAccounts = provider.allUserAccounts
                                .where((acc) => acc.id != _creditorAccount?.id)
                                .toList();
                            return DropdownButtonFormField<int>(
                              value: _selectedDebtorAccountId,
                              decoration: const InputDecoration(
                                labelText: 'Переводить со счета',
                              ),
                              isExpanded: true,
                              itemHeight: 60,
                              selectedItemBuilder: (context) {
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
                                      Text(
                                        balanceText,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey.shade700,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedDebtorAccountId = value;
                                  // --- ИЗМЕНЕНИЕ 4: Расчет НЕ зависит от счета списания, поэтому убираем вызов ---
                                  // _onFormChange();
                                });
                              },
                              validator: (value) =>
                                  value == null ? 'Выберите счет' : null,
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                              ),
                              child: Text(
                                'Дата и повторения',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            const Divider(),
                            FormField<DateTime>(
                              initialValue: _nextPaymentDate,
                              builder: (field) {
                                return ListTile(
                                  title: const Text('Дата следующего платежа'),
                                  subtitle: Text(
                                    DateFormat(
                                      'dd MMMM yyyy',
                                    ).format(field.value!),
                                  ),
                                  trailing: const Icon(Icons.calendar_today),
                                  onTap: () => _pickDate(field),
                                );
                              },
                            ),
                            SwitchListTile(
                              title: const Text('Повторять платеж'),
                              value: _isRecurring,
                              onChanged: (val) =>
                                  setState(() => _isRecurring = val),
                            ),
                            if (_isRecurring)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16.0,
                                  0,
                                  16.0,
                                  16.0,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        controller:
                                            _recurrenceIntervalController,
                                        decoration: const InputDecoration(
                                          labelText: 'Каждые',
                                        ),
                                        keyboardType: TextInputType.number,
                                        validator: (v) {
                                          if (_isRecurring &&
                                              (int.tryParse(v ?? '0') ?? 0) <
                                                  1) {
                                            return 'Введите > 0';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      flex: 3,
                                      child:
                                          DropdownButtonFormField<
                                            RecurrenceType
                                          >(
                                            value: _selectedRecurrenceType,
                                            hint: const Text('Период'),
                                            items: RecurrenceType.values
                                                .map(
                                                  (type) => DropdownMenuItem(
                                                    value: type,
                                                    child: Text(
                                                      describeEnum(type),
                                                    ),
                                                  ),
                                                )
                                                .toList(),
                                            onChanged: (val) => setState(
                                              () =>
                                                  _selectedRecurrenceType = val,
                                            ),
                                            validator: (v) {
                                              if (_isRecurring && v == null) {
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
                    ),
                    const SizedBox(height: 16),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                              ),
                              child: Text(
                                'Сумма платежа',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            const Divider(),
                            RadioListTile<AmountType>(
                              title: const Text('Фиксированная сумма'),
                              value: AmountType.fixed,
                              groupValue: _selectedAmountType,
                              onChanged: (val) => setState(() {
                                _selectedAmountType = val!;
                                _onFormChange();
                              }),
                            ),
                            if (_selectedAmountType == AmountType.fixed)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
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
                                            AmountType.fixed &&
                                        (value == null ||
                                            value.isEmpty ||
                                            (double.tryParse(value) ?? 0) <=
                                                0)) {
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
                                  if (_selectedAmountType ==
                                      AmountType.total_debit)
                                    _buildPreviewAmount(),
                                ],
                              ),
                              value: AmountType.total_debit,
                              groupValue: _selectedAmountType,
                              onChanged: (val) => setState(() {
                                _selectedAmountType = val!;
                                _onFormChange();
                              }),
                            ),
                            RadioListTile<AmountType>(
                              title: Row(
                                children: [
                                  const Text(
                                    'Разница расходов и доходов (долг)',
                                  ),
                                  const Spacer(),
                                  if (_selectedAmountType ==
                                      AmountType.net_debit)
                                    _buildPreviewAmount(),
                                ],
                              ),
                              value: AmountType.net_debit,
                              groupValue: _selectedAmountType,
                              onChanged: (val) => setState(() {
                                _selectedAmountType = val!;
                                _onFormChange();
                              }),
                            ),
                            RadioListTile<AmountType>(
                              title: Row(
                                children: [
                                  const Text('Минимальный платеж'),
                                  const Spacer(),
                                  if (_selectedAmountType ==
                                      AmountType.minimum_payment)
                                    _buildPreviewAmount(),
                                ],
                              ),
                              value: AmountType.minimum_payment,
                              groupValue: _selectedAmountType,
                              onChanged: (val) => setState(() {
                                _selectedAmountType = val!;
                                _onFormChange();
                              }),
                            ),
                            if (_selectedAmountType ==
                                AmountType.minimum_payment)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
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
                                            AmountType.minimum_payment &&
                                        (value == null ||
                                            value.isEmpty ||
                                            (double.tryParse(value) ?? 0) <=
                                                0)) {
                                      return 'Введите процент больше нуля';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            if (_selectedAmountType != AmountType.fixed)
                              FormField<DateTimeRange>(
                                initialValue: _period,
                                validator: (value) {
                                  final requiresPeriod =
                                      _selectedAmountType ==
                                          AmountType.total_debit ||
                                      _selectedAmountType ==
                                          AmountType.net_debit ||
                                      _selectedAmountType ==
                                          AmountType.minimum_payment;
                                  if (requiresPeriod && value == null) {
                                    return 'Выберите период для расчета суммы';
                                  }
                                  return null;
                                },
                                builder: (field) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ListTile(
                                        title: const Text('Период для расчета'),
                                        subtitle: field.value == null
                                            ? const Text('Не выбран')
                                            : Text(
                                                '${DateFormat('dd.MM.yy').format(field.value!.start)} - ${DateFormat('dd.MM.yy').format(field.value!.end)}',
                                              ),
                                        trailing: const Icon(Icons.date_range),
                                        onTap: () => _pickDateRange(field),
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
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.error,
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
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _submitForm,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(
                        _existingPayment == null ? 'Создать' : 'Сохранить',
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
