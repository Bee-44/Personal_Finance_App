// Builds the icon sources used by flutter_launcher_icons and the in-app logo
// from the original artwork (assets/images/PennyTree.png).
//
//   dart run tool/generate_icons.dart
//   dart run flutter_launcher_icons
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final source = img.decodePng(
    File('assets/images/PennyTree.png').readAsBytesSync(),
  )!;

  // Centered square crop of the artwork.
  final side = source.width < source.height ? source.width : source.height;
  final square = img.copyCrop(
    source,
    x: (source.width - side) ~/ 2,
    y: (source.height - side) ~/ 2,
    width: side,
    height: side,
  );

  Directory('assets/icon').createSync(recursive: true);

  // App icon: the full illustration. It is also the Android adaptive
  // foreground; flutter_launcher_icons insets it so the tree stays visible.
  final icon = img.copyResize(
    square,
    width: 1024,
    height: 1024,
    interpolation: img.Interpolation.cubic,
  );
  File('assets/icon/icon.png').writeAsBytesSync(img.encodePng(icon));

  // Lightweight logo bundled with the app (cover screen).
  final logo = img.copyResize(
    square,
    width: 720,
    height: 720,
    interpolation: img.Interpolation.cubic,
  );
  File(
    'assets/images/pennytree_logo.jpg',
  ).writeAsBytesSync(img.encodeJpg(logo, quality: 88));

  stdout.writeln('Icon sources generated.');
}
