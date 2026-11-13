import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/validation.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/color_utils.dart';
import 'medieval.dart';

/// Marco común de los formularios: fondo de damero, título dorado y una
/// tarjeta de pergamino con el contenido.
class FormScaffold extends StatelessWidget {
  final String title;
  final Widget child;

  const FormScaffold({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: DiaperBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    tooltip: 'Volver',
                    icon: const Icon(Icons.arrow_back, color: AppColors.goldLight),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: displayStyle(size: 26, color: AppColors.goldLight),
                ),
                const SizedBox(height: 12),
                const OrnamentDivider(width: 200),
                const SizedBox(height: 22),
                FadeSlideIn(
                  child: OrnateCard(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Campo de dinero: solo números con hasta dos decimales (punto o coma).
class MoneyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool allowEmpty;
  final bool autofocus;

  const MoneyField({
    super.key,
    required this.controller,
    this.label = 'Monto',
    this.allowEmpty = false,
    this.autofocus = false,
  });

  static final formatter = FilteringTextInputFormatter.allow(
    RegExp(r'^\d{0,9}([.,]\d{0,2})?'),
  );

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 20),
      decoration: InputDecoration(
        labelText: label,
        hintText: '0.00',
        prefixText: '\$ ',
      ),
      inputFormatters: [formatter],
      validator: (value) {
        final text = value?.trim() ?? '';
        if (text.isEmpty) return allowEmpty ? null : 'Campo requerido';
        return validateMoney(parseMoney(text), allowZero: allowEmpty);
      },
    );
  }
}

/// Campo de texto corto obligatorio.
class NameField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool autofocus;

  const NameField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      maxLength: maxTextLength,
      textCapitalization: TextCapitalization.sentences,
      style: const TextStyle(fontSize: 20),
      inputFormatters: [
        FilteringTextInputFormatter.deny(RegExp(r'[\x00-\x1F\x7F]')),
      ],
      decoration: InputDecoration(labelText: label, hintText: hint),
      validator: validateText,
    );
  }
}

/// Selector de dos o más opciones en forma de pestañas.
class ChoiceBar<T> extends StatelessWidget {
  final Map<T, String> options;
  final Map<T, IconData> icons;
  final T value;
  final ValueChanged<T> onChanged;

  const ChoiceBar({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.icons = const {},
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<T>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          backgroundColor: AppColors.vellum,
          foregroundColor: AppColors.inkSoft,
          selectedBackgroundColor: AppColors.bark,
          selectedForegroundColor: AppColors.vellum,
          side: const BorderSide(color: AppColors.goldDeep),
          textStyle: const TextStyle(
            fontFamily: bodyFont,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        segments: [
          for (final entry in options.entries)
            ButtonSegment(
              value: entry.key,
              label: Text(entry.value),
              icon: icons[entry.key] == null ? null : Icon(icons[entry.key]),
            ),
        ],
        selected: {value},
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}

/// Selector Banco / Efectivo.
class MethodBar extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const MethodBar({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ChoiceBar<String>(
      options: const {PayMethod.bank: 'Banco', PayMethod.cash: 'Efectivo'},
      icons: const {
        PayMethod.bank: Icons.account_balance,
        PayMethod.cash: Icons.payments_outlined,
      },
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Interruptor con título y explicación.
class OptionSwitch extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const OptionSwitch({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      activeColor: AppColors.vellum,
      activeTrackColor: AppColors.forest,
      inactiveThumbColor: AppColors.inkSoft,
      inactiveTrackColor: AppColors.parchment,
      title: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(fontSize: 15, color: AppColors.inkSoft),
            ),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Botón de texto para borrar, al pie de un formulario de edición.
class DeleteLink extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const DeleteLink({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(foregroundColor: AppColors.crimson),
      icon: const Icon(Icons.delete_outline),
      label: Text(label),
      onPressed: onPressed,
    );
  }
}

/// Pide confirmación antes de borrar algo.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.crimson,
            foregroundColor: AppColors.vellum,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Eliminar'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Aviso breve al pie de la pantalla.
void showNotice(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.crimson : AppColors.forest,
        duration: const Duration(seconds: 2),
      ),
    );
}
