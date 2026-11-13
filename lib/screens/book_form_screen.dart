import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/book.dart';
import '../services/app_database.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/color_utils.dart';
import '../widgets/form_widgets.dart';
import '../widgets/medieval.dart';

/// Pantalla para crear un libro o editar su nombre y color.
/// Al guardar regresa `true` a la pantalla anterior.
class BookFormScreen extends StatefulWidget {
  final Book? book;

  const BookFormScreen({super.key, this.book});

  @override
  State<BookFormScreen> createState() => _BookFormScreenState();
}

class _BookFormScreenState extends State<BookFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late Color _color;
  late String _kind = widget.book?.kind ?? BookKind.monthly;
  bool _saving = false;
  String? _nameError;

  bool get _isEditing => widget.book != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.book?.name ?? '');
    _color = widget.book?.color ?? Book.palette.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _nameError = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final db = AppDatabase.instance;
    final name = _nameController.text.trim();
    final id = widget.book?.id;

    if (await db.bookNameExists(name, exceptId: id)) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _nameError = 'Ya existe un libro con ese nombre';
      });
      return;
    }

    if (id == null) {
      await db.insertBook(name: name, color: _color.toARGB32(), kind: _kind);
    } else {
      await db.updateBook(id, name: name, color: _color.toARGB32());
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Editar Libro' : 'Nuevo Libro')),
      body: ParchmentBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  // Vista previa del libro; cambia de color con suavidad.
                  Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [_color, darken(_color, 0.3)],
                        ),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: AppColors.gold, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.ink.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.history_edu,
                        size: 54,
                        color: AppColors.goldLight,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  OrnateCard(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _nameController,
                          autofocus: !_isEditing,
                          maxLength: Book.maxNameLength,
                          textCapitalization: TextCapitalization.sentences,
                          style: const TextStyle(fontSize: 20),
                          inputFormatters: [
                            // Sin saltos de línea ni caracteres de control.
                            FilteringTextInputFormatter.deny(
                              RegExp(r'[\x00-\x1F\x7F]'),
                            ),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Nombre del libro',
                            hintText: 'Ej. Casa, Negocio, Viaje',
                            errorText: _nameError,
                          ),
                          validator: Book.validateName,
                          onFieldSubmitted: (_) => _save(),
                        ),
                        // El tipo solo se elige al crear el libro.
                        if (!_isEditing) ...[
                          const SizedBox(height: 10),
                          Text('Tipo de libro', style: displayStyle(size: 16)),
                          const SizedBox(height: 12),
                          ChoiceBar<String>(
                            options: const {
                              BookKind.monthly: 'Mensual',
                              BookKind.ledger: 'Cuenta',
                            },
                            icons: const {
                              BookKind.monthly: Icons.checklist,
                              BookKind.ledger: Icons.savings_outlined,
                            },
                            value: _kind,
                            onChanged: (v) => setState(() => _kind = v),
                          ),
                          const SizedBox(height: 8),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(
                              _kind == BookKind.monthly
                                  ? 'Ingresos y una lista de gastos para marcar. '
                                      'Cada mes se copian los recurrentes.'
                                  : 'Abonos y retiros con saldo corrido, sin '
                                      'cortes por mes. Ideal para ahorros.',
                              key: ValueKey(_kind),
                              style: const TextStyle(
                                fontSize: 16,
                                color: AppColors.inkSoft,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Text('Color del libro', style: displayStyle(size: 16)),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 14,
                          runSpacing: 14,
                          children: [
                            for (final color in Book.palette)
                              _ColorDot(
                                color: color,
                                selected:
                                    color.toARGB32() == _color.toARGB32(),
                                onTap: () => setState(() => _color = color),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  MedievalButton(
                    label: _isEditing ? 'Guardar cambios' : 'Crear libro',
                    icon: Icons.check,
                    expand: true,
                    onPressed: _saving ? null : _save,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sello de cera de un color; el elegido crece y se rodea de oro.
class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Color',
      child: PressScale(
        scale: 0.88,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedScale(
            scale: selected ? 1.12 : 1,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.35, -0.4),
                  colors: [color, darken(color, 0.3)],
                ),
                border: Border.all(
                  color: selected ? AppColors.gold : AppColors.parchmentDeep,
                  width: selected ? 3 : 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.ink.withValues(alpha: selected ? 0.35 : 0.15),
                    blurRadius: selected ? 8 : 3,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: const Icon(Icons.check, color: AppColors.goldLight),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
