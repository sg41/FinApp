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

// Импорт виджетов формы
import '../widgets/scheduled_payment_form/_debtor_account_selector_card.dart';
import '../widgets/scheduled_payment_form/_creditor_account_card.dart'; // <-- Новый импорт
import '../widgets/scheduled_payment_form/_date_and_recurrence_card.dart';
import '../widgets/scheduled_payment_form/_payment_amount_card.dart';

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
        if (mounted) _fetchInitialData();
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
    _percentageController.dispose();
    _recurrenceIntervalController.dispose();
    super.dispose();
  }

  void _onFormChange() {
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

  Future<void> _fetchTurnover() async {
    if (_creditorAccount == null || _period == null) return;
    setState(() {
      _isCalculatingPreview = true;
      _previewAmountText = null;
    });
    final provider = Provider.of<ScheduledPaymentProvider>(
      context,
      listen: false,
    );
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

  void _recalculatePreviewText() {
    if (!mounted) return;

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
                    // --- КАРТОЧКА "ОТКУДА" (Debtor) ---
                    Consumer<ScheduledPaymentProvider>(
                      builder: (context, provider, child) {
                        return DebtorAccountSelectorCard(
                          availableAccounts: provider.allUserAccounts
                              .where((acc) => acc.id != _creditorAccount?.id)
                              .toList(),
                          selectedDebtorAccountId: _selectedDebtorAccountId,
                          onChanged: (value) {
                            setState(() {
                              _selectedDebtorAccountId = value;
                            });
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),

                    // --- КАРТОЧКА "КУДА" (Creditor) ---
                    if (_creditorAccount != null)
                      CreditorAccountCard(account: _creditorAccount!),
                    if (_creditorAccount != null) const SizedBox(height: 16),

                    // --- КАРТОЧКА "КОГДА" (Date) ---
                    DateAndRecurrenceCard(
                      nextPaymentDate: _nextPaymentDate,
                      onDateChanged: (date) =>
                          setState(() => _nextPaymentDate = date),
                      isRecurring: _isRecurring,
                      onIsRecurringChanged: (value) =>
                          setState(() => _isRecurring = value),
                      recurrenceIntervalController:
                          _recurrenceIntervalController,
                      selectedRecurrenceType: _selectedRecurrenceType,
                      onRecurrenceTypeChanged: (value) =>
                          setState(() => _selectedRecurrenceType = value),
                    ),
                    const SizedBox(height: 16),

                    // --- КАРТОЧКА "СКОЛЬКО" (Amount) ---
                    PaymentAmountCard(
                      selectedAmountType: _selectedAmountType,
                      onAmountTypeChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedAmountType = value;
                            _onFormChange();
                          });
                        }
                      },
                      fixedAmountController: _fixedAmountController,
                      percentageController: _percentageController,
                      period: _period,
                      onPeriodChanged: (range) {
                        setState(() {
                          _period = range;
                          _onFormChange();
                        });
                      },
                      isCalculatingPreview: _isCalculatingPreview,
                      previewAmountText: _previewAmountText,
                      onRecalculatePreview: _recalculatePreviewText,
                    ),
                    const SizedBox(height: 24),

                    // --- КНОПКА СОХРАНИТЬ ---
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
