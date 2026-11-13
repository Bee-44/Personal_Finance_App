import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/month.dart';
import '../models/movement.dart';
import '../models/validation.dart';
import '../services/app_database.dart';
import '../theme/app_colors.dart';
import '../utils/color_utils.dart';
import '../widgets/form_widgets.dart';
import '../widgets/medieval.dart';

// Todos los formularios regresan `true` a la pantalla anterior si guardaron
// o borraron algo.

/// Crea o edita un renglón de la lista del mes.
class ItemFormScreen extends StatefulWidget {
  final int periodId;
  final BudgetItem? item;

  const ItemFormScreen({super.key, required this.periodId, this.item});

  @override
  State<ItemFormScreen> createState() => _ItemFormScreenState();
}

class _ItemFormScreenState extends State<ItemFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _amount = TextEditingController(
    text: (widget.item?.amount ?? 0) == 0
        ? ''
        : widget.item!.amount.toStringAsFixed(2),
  );
  late String _method = widget.item?.method ?? PayMethod.bank;
  late bool _recurring = widget.item?.recurring ?? true;
  late bool _envelope = widget.item?.envelope ?? false;
  bool _paid = false;
  bool _saving = false;

  bool get _isEditing => widget.item != null;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final item = BudgetItem(
      id: widget.item?.id,
      periodId: widget.periodId,
      name: _name.text.trim(),
      amount: parseMoney(_amount.text) ?? 0,
      method: _method,
      recurring: _recurring,
      envelope: _envelope,
      paid: _paid,
    );
    final db = AppDatabase.instance;
    if (_isEditing) {
      await db.updateItem(item);
    } else {
      await db.insertItem(item);
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await confirmDelete(
      context,
      title: 'Eliminar renglón',
      message: '¿Eliminar "${widget.item!.name}" de este mes?',
    );
    if (!ok) return;
    await AppDatabase.instance.deleteItem(widget.item!.id!);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return FormScaffold(
      title: _isEditing ? 'Editar Renglón' : 'Nuevo Renglón',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NameField(
              controller: _name,
              label: 'Concepto',
              hint: 'Ej. Renta, Luz, Súper',
              autofocus: !_isEditing,
            ),
            MoneyField(
              controller: _amount,
              label: 'Monto (puede quedar vacío)',
              allowEmpty: true,
            ),
            const SizedBox(height: 18),
            MethodBar(
              value: _method,
              onChanged: (v) => setState(() => _method = v),
            ),
            const SizedBox(height: 8),
            OptionSwitch(
              title: 'Se repite cada mes',
              subtitle: 'Aparecerá sin marcar en la lista del mes siguiente',
              value: _recurring,
              onChanged: (v) => setState(() => _recurring = v),
            ),
            OptionSwitch(
              title: 'Fondo para ir gastando',
              subtitle: 'Apartas el monto y anotas lo que vas gastando',
              value: _envelope,
              onChanged: (v) => setState(() => _envelope = v),
            ),
            if (!_isEditing)
              OptionSwitch(
                title: 'Ya está pagado',
                value: _paid,
                onChanged: (v) => setState(() => _paid = v),
              ),
            const SizedBox(height: 14),
            MedievalButton(
              label: 'Guardar',
              icon: Icons.check,
              expand: true,
              onPressed: _saving ? null : _save,
            ),
            if (_isEditing) ...[
              const SizedBox(height: 6),
              DeleteLink(label: 'Eliminar renglón', onPressed: _delete),
            ],
          ],
        ),
      ),
    );
  }
}

/// Crea o edita un ingreso del mes.
class IncomeFormScreen extends StatefulWidget {
  final int periodId;
  final Income? income;

  const IncomeFormScreen({super.key, required this.periodId, this.income});

  @override
  State<IncomeFormScreen> createState() => _IncomeFormScreenState();
}

class _IncomeFormScreenState extends State<IncomeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.income?.name ?? '');
  late final _amount = TextEditingController(
    text: widget.income?.amount.toStringAsFixed(2) ?? '',
  );
  late String _method = widget.income?.method ?? PayMethod.bank;
  late bool _recurring = widget.income?.recurring ?? true;
  bool _saving = false;

  bool get _isEditing => widget.income != null;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final income = Income(
      id: widget.income?.id,
      periodId: widget.periodId,
      name: _name.text.trim(),
      amount: parseMoney(_amount.text)!,
      method: _method,
      recurring: _recurring,
    );
    final db = AppDatabase.instance;
    if (_isEditing) {
      await db.updateIncome(income);
    } else {
      await db.insertIncome(income);
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await confirmDelete(
      context,
      title: 'Eliminar ingreso',
      message: '¿Eliminar "${widget.income!.name}" de este mes?',
    );
    if (!ok) return;
    await AppDatabase.instance.deleteIncome(widget.income!.id!);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return FormScaffold(
      title: _isEditing ? 'Editar Ingreso' : 'Nuevo Ingreso',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NameField(
              controller: _name,
              label: 'Concepto',
              hint: 'Ej. Salario, Extra',
              autofocus: !_isEditing,
            ),
            MoneyField(controller: _amount),
            const SizedBox(height: 18),
            MethodBar(
              value: _method,
              onChanged: (v) => setState(() => _method = v),
            ),
            const SizedBox(height: 8),
            OptionSwitch(
              title: 'Se repite cada mes',
              subtitle: 'Aparecerá también en el mes siguiente',
              value: _recurring,
              onChanged: (v) => setState(() => _recurring = v),
            ),
            const SizedBox(height: 14),
            MedievalButton(
              label: 'Guardar',
              icon: Icons.check,
              expand: true,
              onPressed: _saving ? null : _save,
            ),
            if (_isEditing) ...[
              const SizedBox(height: 6),
              DeleteLink(label: 'Eliminar ingreso', onPressed: _delete),
            ],
          ],
        ),
      ),
    );
  }
}

/// Crea o edita un abono o retiro de una cuenta.
class MovementFormScreen extends StatefulWidget {
  final int bookId;
  final Movement? movement;

  const MovementFormScreen({super.key, required this.bookId, this.movement});

  @override
  State<MovementFormScreen> createState() => _MovementFormScreenState();
}

class _MovementFormScreenState extends State<MovementFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _description = TextEditingController(
    text: widget.movement?.description ?? '',
  );
  late final _amount = TextEditingController(
    text: widget.movement?.amount.abs().toStringAsFixed(2) ?? '',
  );
  late bool _isIncome = widget.movement?.isIncome ?? false;
  late String _method = widget.movement?.method ?? PayMethod.bank;
  late DateTime _date = widget.movement?.date ?? DateTime.now();
  bool _saving = false;

  bool get _isEditing => widget.movement != null;

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final value = parseMoney(_amount.text)!;
    final movement = Movement(
      id: widget.movement?.id,
      bookId: widget.bookId,
      amount: _isIncome ? value : -value,
      description: _description.text.trim(),
      date: _date,
      method: _method,
    );
    final db = AppDatabase.instance;
    if (_isEditing) {
      await db.updateMovement(movement);
    } else {
      await db.insertMovement(movement);
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await confirmDelete(
      context,
      title: 'Eliminar movimiento',
      message: '¿Eliminar "${widget.movement!.description}"?',
    );
    if (!ok) return;
    await AppDatabase.instance.deleteMovement(widget.movement!.id!);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return FormScaffold(
      title: _isEditing ? 'Editar Movimiento' : 'Nuevo Movimiento',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChoiceBar<bool>(
              options: const {false: 'Retiro', true: 'Abono'},
              icons: const {false: Icons.remove, true: Icons.add},
              value: _isIncome,
              onChanged: (v) => setState(() => _isIncome = v),
            ),
            const SizedBox(height: 6),
            MoneyField(controller: _amount, autofocus: !_isEditing),
            NameField(controller: _description, label: 'Descripción'),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Fecha: ${DateFormat('dd/MM/yyyy').format(_date)}',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
                PressScale(
                  scale: 0.85,
                  child: IconButton(
                    tooltip: 'Elegir fecha',
                    icon: const Icon(
                      Icons.calendar_month,
                      color: AppColors.goldDeep,
                    ),
                    onPressed: _pickDate,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            MethodBar(
              value: _method,
              onChanged: (v) => setState(() => _method = v),
            ),
            const SizedBox(height: 22),
            MedievalButton(
              label: 'Guardar',
              icon: Icons.check,
              expand: true,
              onPressed: _saving ? null : _save,
            ),
            if (_isEditing) ...[
              const SizedBox(height: 6),
              DeleteLink(label: 'Eliminar movimiento', onPressed: _delete),
            ],
          ],
        ),
      ),
    );
  }
}
