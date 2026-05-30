import 'package:flutter/services.dart';

/// Evita que el usuario escriba dos puntos (`.`) o dos comas (`,`) seguidas.
class NoConsecutiveDecimalSeparatorFormatter extends TextInputFormatter {
  const NoConsecutiveDecimalSeparatorFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.contains('..') || text.contains(',,') || text.contains('.,') || text.contains(',.')) {
      // Rechazamos si hay dos separadores iguales o una combinación inmediata entre '.' y ','.
      // La combinación '.,' o ',.' también suele ser indeseada en este campo.
      return oldValue;
    }

    return newValue;
  }
}
