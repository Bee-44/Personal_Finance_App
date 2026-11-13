import 'package:flutter/material.dart';

import '../services/app_database.dart';
import '../theme/app_colors.dart';
import '../utils/note_import.dart';
import '../widgets/form_widgets.dart';
import '../widgets/medieval.dart';

/// Pega una lista escrita en otra app (notas, por ejemplo) y la convierte en
/// renglones del mes o en movimientos de una cuenta.
///
/// Regresa a la pantalla anterior cuántos elementos se agregaron.
class ImportScreen extends StatefulWidget {
  /// Mes al que se agregan los renglones; null si es una cuenta.
  final int? periodId;

  /// Cuenta a la que se agregan los movimientos; null si es un mes.
  final int? bookId;

  const ImportScreen.items({super.key, required int this.periodId})
    : bookId = null;

  const ImportScreen.movements({super.key, required int this.bookId})
    : periodId = null;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _text = TextEditingController();
  bool _recurring = true;
  bool _saving = false;
  int _found = 0;

  bool get _isLedger => widget.bookId != null;

  @override
  void initState() {
    super.initState();
    _text.addListener(_count);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _count() {
    final found = _isLedger
        ? parseLedger(_text.text).length
        : parseChecklist(_text.text).length;
    if (found != _found) setState(() => _found = found);
  }

  Future<void> _import() async {
    if (_saving || _found == 0) return;
    setState(() => _saving = true);
    final db = AppDatabase.instance;
    final added = _isLedger
        ? await db.importMovements(widget.bookId!, parseLedger(_text.text))
        : await db.importItems(
            widget.periodId!,
            parseChecklist(_text.text),
            recurring: _recurring,
          );
    if (mounted) Navigator.pop(context, added);
  }

  @override
  Widget build(BuildContext context) {
    final example = _isLedger
        ? '+ 300 abono\n- 75 renta'
        : '[ ] 350 súper ( -130 - 16 = 204 )\n[v] 82 préstamo';
    final what = _isLedger ? 'movimientos' : 'renglones';

    return FormScaffold(
      title: 'Pegar Lista',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isLedger
                ? 'Pega una línea por movimiento: + para abonos y - para '
                    'retiros.'
                : 'Pega una línea por renglón, empezando con su casilla. '
                    'Un paréntesis indica un fondo con sus gastos.',
            style: const TextStyle(fontSize: 17, color: AppColors.inkSoft),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 6,
            maxLines: 12,
            maxLength: 20000,
            style: const TextStyle(fontSize: 17),
            decoration: InputDecoration(
              hintText: example,
              hintMaxLines: 3,
              counterText: '',
              filled: true,
              fillColor: AppColors.parchment.withValues(alpha: 0.6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.goldDeep),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.goldDeep),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.gold, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              _found == 0
                  ? 'Aún no se reconoce ningún renglón'
                  : 'Se reconocieron $_found $what',
              key: ValueKey(_found),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: _found == 0 ? AppColors.inkSoft : AppColors.forest,
              ),
            ),
          ),
          if (!_isLedger)
            OptionSwitch(
              title: 'Se repiten cada mes',
              subtitle: 'Apágalo si son gastos solo de este mes',
              value: _recurring,
              onChanged: (v) => setState(() => _recurring = v),
            ),
          const SizedBox(height: 14),
          MedievalButton(
            label: 'Agregar',
            icon: Icons.playlist_add_check,
            expand: true,
            onPressed: _saving || _found == 0 ? null : _import,
          ),
        ],
      ),
    );
  }
}
