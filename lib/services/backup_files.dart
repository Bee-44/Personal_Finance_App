import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Abre y guarda archivos de texto con el selector de archivos del sistema.
/// La app nunca lee ni escribe archivos por su cuenta: el usuario elige
/// cada vez cuál abrir y dónde guardar.
abstract final class BackupFiles {
  /// Tamaño máximo que se acepta al importar.
  static const int maxBytes = 2 * 1024 * 1024;

  /// Pide al usuario un archivo de texto y devuelve su contenido.
  /// Devuelve null si canceló. Lanza [FormatException] si es demasiado
  /// grande o no se pudo leer.
  static Future<String?> pickText() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Elige un archivo de texto',
      type: FileType.custom,
      allowedExtensions: const ['txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      throw const FormatException('No se pudo leer el archivo');
    }
    return decode(bytes);
  }

  /// Convierte el contenido de un archivo en texto.
  static String decode(Uint8List bytes) {
    if (bytes.length > maxBytes) {
      throw const FormatException('El archivo es demasiado grande');
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Pide al usuario dónde guardar [text]. Devuelve false si canceló.
  static Future<bool> saveText(String fileName, String text) async {
    final path = await FilePicker.saveFile(
      dialogTitle: 'Guardar respaldo',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['txt'],
      bytes: Uint8List.fromList(utf8.encode(text)),
    );
    return path != null;
  }
}
