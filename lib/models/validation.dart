/// Reglas de validación compartidas por los modelos y la base de datos.
library;

const double maxMoney = 999999999.99;
const int maxTextLength = 60;

/// De dónde sale o a dónde entra el dinero.
abstract final class PayMethod {
  static const String bank = 'bank';
  static const String cash = 'cash';
  static const List<String> values = [bank, cash];

  static String label(String method) => method == cash ? 'Efectivo' : 'Banco';
}

/// Valida un monto. Devuelve el mensaje de error o null si es válido.
String? validateMoney(double? value, {bool allowZero = false}) {
  if (value == null || value.isNaN || value.isInfinite) {
    return 'Ingresa un número válido';
  }
  if (value < 0) return 'No puede ser negativo';
  if (value == 0 && !allowZero) return 'El monto debe ser mayor que cero';
  if (value > maxMoney) return 'El monto es demasiado grande';
  return null;
}

/// Valida un texto corto obligatorio (nombre o descripción).
String? validateText(String? value, {int max = maxTextLength}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'Campo requerido';
  if (text.length > max) return 'Máximo $max caracteres';
  return null;
}

String? validateMethod(String? value) {
  if (!PayMethod.values.contains(value)) return 'Selecciona un método';
  return null;
}
