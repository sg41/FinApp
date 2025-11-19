// lib/widgets/scheduled_payment_form/_debtor_account_selector_card.dart

import 'package:flutter/material.dart';
import '../../models/account.dart';
import '../../utils/formatting.dart';

enum SortType { name, balance }

class DebtorAccountSelectorCard extends StatefulWidget {
  final List<Account> availableAccounts;
  final int? selectedDebtorAccountId;
  final ValueChanged<int?> onChanged;

  const DebtorAccountSelectorCard({
    super.key,
    required this.availableAccounts,
    required this.selectedDebtorAccountId,
    required this.onChanged,
  });

  @override
  State<DebtorAccountSelectorCard> createState() =>
      _DebtorAccountSelectorCardState();
}

class _DebtorAccountSelectorCardState extends State<DebtorAccountSelectorCard> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isDropdownOpen = false;

  SortType _currentSortType = SortType.name;
  bool _isAscending = true;

  @override
  void dispose() {
    // ИСПРАВЛЕНИЕ: Удаляем оверлей напрямую, не вызывая setState
    _overlayEntry?.remove();
    _overlayEntry = null;
    super.dispose();
  }

  void _toggleDropdown() {
    if (_isDropdownOpen) {
      _closeDropdown();
    } else {
      _openDropdown();
    }
  }

  void _closeDropdown() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) {
      setState(() {
        _isDropdownOpen = false;
      });
    }
  }

  void _openDropdown() {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            // Прозрачный фон для закрытия при клике вне списка
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeDropdown,
                child: Container(color: Colors.transparent),
              ),
            ),
            // Сам список
            Positioned(
              width: size.width,
              child: CompositedTransformFollower(
                link: _layerLink,
                showWhenUnlinked: false,
                offset: Offset(0.0, size.height + 4.0),
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.white,
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: _buildDropdownContent(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
    setState(() {
      _isDropdownOpen = true;
    });
  }

  Widget _buildDropdownContent() {
    return StatefulBuilder(
      builder: (context, setStateOverlay) {
        final list = List<Account>.from(widget.availableAccounts);
        list.sort((a, b) {
          int result;
          if (_currentSortType == SortType.name) {
            result = a.nickname.compareTo(b.nickname);
            if (result == 0) result = a.bankName.compareTo(b.bankName);
          } else {
            final balA =
                double.tryParse(a.availableBalance?.amount ?? '0') ?? 0.0;
            final balB =
                double.tryParse(b.availableBalance?.amount ?? '0') ?? 0.0;
            result = balA.compareTo(balB);
          }
          return _isAscending ? result : -result;
        });

        void changeSort(SortType type) {
          setStateOverlay(() {
            if (_currentSortType == type) {
              _isAscending = !_isAscending;
            } else {
              _currentSortType = type;
              _isAscending = type == SortType.name;
            }
          });
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- ПАНЕЛЬ СОРТИРОВКИ ---
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Сортировка:',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  Row(
                    children: [
                      _SortButton(
                        icon: Icons.sort_by_alpha,
                        isActive: _currentSortType == SortType.name,
                        isAscending: _isAscending,
                        onTap: () => changeSort(SortType.name),
                      ),
                      const SizedBox(width: 8),
                      _SortButton(
                        icon: Icons.attach_money,
                        isActive: _currentSortType == SortType.balance,
                        isAscending: _isAscending,
                        onTap: () => changeSort(SortType.balance),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // --- СПИСОК ---
            Flexible(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (ctx, index) {
                  final account = list[index];
                  final isSelected =
                      account.id == widget.selectedDebtorAccountId;

                  return InkWell(
                    onTap: () {
                      widget.onChanged(account.id);
                      _closeDropdown();
                    },
                    child: Container(
                      color: isSelected ? Colors.blue.withOpacity(0.08) : null,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: _buildSingleLineRow(
                        context,
                        account,
                        showArrow: false,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Account? selectedAccount;
    if (widget.selectedDebtorAccountId != null) {
      try {
        selectedAccount = widget.availableAccounts.firstWhere(
          (a) => a.id == widget.selectedDebtorAccountId,
        );
      } catch (e) {
        // ignore
      }
    }

    return CompositedTransformTarget(
      link: _layerLink,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: _isDropdownOpen ? Colors.blue : Colors.grey.shade400,
            width: _isDropdownOpen ? 1.5 : 1.0,
          ),
          borderRadius: BorderRadius.circular(4.0),
        ),
        color: Colors.white,
        child: InkWell(
          onTap: _toggleDropdown,
          borderRadius: BorderRadius.circular(4.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 12.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Переводить со счета',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 4),
                if (selectedAccount != null)
                  _buildSingleLineRow(context, selectedAccount, showArrow: true)
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        'Выберите счет',
                        style: TextStyle(fontSize: 16, color: Colors.black54),
                      ),
                      Icon(Icons.arrow_drop_down, color: Colors.black54),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSingleLineRow(
    BuildContext context,
    Account account, {
    required bool showArrow,
  }) {
    final balance = account.availableBalance;
    final balanceText = balance != null
        ? (num.tryParse(balance.amount) ?? 0.0).toFormattedCurrency(
            balance.currency,
          )
        : 'Баланс н/д';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: RichText(
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: DefaultTextStyle.of(context).style,
              children: [
                TextSpan(
                  text: account.nickname,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
                TextSpan(
                  text:
                      '  •  ${account.bankName.toUpperCase()} ${account.bankClientId} ${account.apiAccountId}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          balanceText,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.green.shade700,
          ),
        ),
        if (showArrow) ...[
          const SizedBox(width: 8),
          Icon(
            _isDropdownOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
            color: Colors.black54,
          ),
        ],
      ],
    );
  }
}

class _SortButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final bool isAscending;
  final VoidCallback onTap;

  const _SortButton({
    required this.icon,
    required this.isActive,
    required this.isAscending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? Colors.blue.shade200 : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? Colors.blue : Colors.grey.shade500,
            ),
            if (isActive) ...[
              const SizedBox(width: 2),
              Icon(
                isAscending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 12,
                color: Colors.blue,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
