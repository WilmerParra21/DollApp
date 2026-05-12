import 'package:flutter/material.dart';

class QuickActionChip extends StatelessWidget {
  const QuickActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isSelected = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ActionChip(
      onPressed: onTap,
      avatar: Icon(
        icon,
        size: 18,
        color: isSelected ? colorScheme.onPrimary : colorScheme.primary,
      ),
      label: Text(label),
      labelStyle: TextStyle(
        color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      backgroundColor: isSelected ? colorScheme.primary : colorScheme.surface,
      side: BorderSide(
        color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    );
  }
}
