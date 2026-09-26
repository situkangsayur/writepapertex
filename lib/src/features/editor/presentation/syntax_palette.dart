import 'package:flutter/material.dart';

import '../domain/latex_syntax.dart';

/// Sekumpulan warna untuk bagian-bagian LaTeX.
///
/// Tiap palet menyediakan dua rupa — terang dan gelap — karena warna yang
/// terbaca di atas kertas putih menghilang di atas latar gelap, dan sebuah
/// tablet berpindah di antara keduanya sepanjang hari.
@immutable
class SyntaxPalette {
  const SyntaxPalette({
    required this.id,
    required this.name,
    required this.description,
    required this.light,
    required this.dark,
  });

  final String id;
  final String name;
  final String description;
  final Map<SyntaxKind, Color> light;
  final Map<SyntaxKind, Color> dark;

  Color colorFor(SyntaxKind kind, Brightness brightness) {
    final table = brightness == Brightness.dark ? dark : light;
    return table[kind] ?? table[SyntaxKind.text]!;
  }

  /// Palet tanpa warna, untuk yang lebih suka teks hitam putih.
  static const SyntaxPalette none = SyntaxPalette(
    id: 'polos',
    name: 'Tanpa warna',
    description: 'semuanya sewarna, seperti mesin tik',
    light: <SyntaxKind, Color>{SyntaxKind.text: Color(0xFF1B1C18)},
    dark: <SyntaxKind, Color>{SyntaxKind.text: Color(0xFFE3E3DC)},
  );

  /// Warna redam yang pantas untuk membaca lama.
  static const SyntaxPalette calm = SyntaxPalette(
    id: 'tenang',
    name: 'Tenang',
    description: 'warna redam, enak dipandang lama',
    light: <SyntaxKind, Color>{
      SyntaxKind.text: Color(0xFF1B1C18),
      SyntaxKind.comment: Color(0xFF6B7A63),
      SyntaxKind.command: Color(0xFF2F6B4F),
      SyntaxKind.sectioning: Color(0xFF1B5E3F),
      SyntaxKind.environment: Color(0xFF8A5A00),
      SyntaxKind.reference: Color(0xFF6B4EA8),
      SyntaxKind.math: Color(0xFF9A4A1E),
      SyntaxKind.delimiter: Color(0xFF7A7F74),
    },
    dark: <SyntaxKind, Color>{
      SyntaxKind.text: Color(0xFFE3E3DC),
      SyntaxKind.comment: Color(0xFF93A48C),
      SyntaxKind.command: Color(0xFF7FD1A6),
      SyntaxKind.sectioning: Color(0xFF9FE3BF),
      SyntaxKind.environment: Color(0xFFE8B964),
      SyntaxKind.reference: Color(0xFFC4B1F5),
      SyntaxKind.math: Color(0xFFF0A882),
      SyntaxKind.delimiter: Color(0xFF9AA093),
    },
  );

  /// Warna kuat, untuk layar terang benderang atau mata yang lelah.
  static const SyntaxPalette vivid = SyntaxPalette(
    id: 'tegas',
    name: 'Tegas',
    description: 'kontras tinggi, jelas di bawah matahari',
    light: <SyntaxKind, Color>{
      SyntaxKind.text: Color(0xFF000000),
      SyntaxKind.comment: Color(0xFF4F7A2E),
      SyntaxKind.command: Color(0xFF0B4FD0),
      SyntaxKind.sectioning: Color(0xFF7A1FA2),
      SyntaxKind.environment: Color(0xFFB35C00),
      SyntaxKind.reference: Color(0xFF00727A),
      SyntaxKind.math: Color(0xFFC1121F),
      SyntaxKind.delimiter: Color(0xFF555555),
    },
    dark: <SyntaxKind, Color>{
      SyntaxKind.text: Color(0xFFF5F5F5),
      SyntaxKind.comment: Color(0xFF8FD35A),
      SyntaxKind.command: Color(0xFF7FB2FF),
      SyntaxKind.sectioning: Color(0xFFDDA0FF),
      SyntaxKind.environment: Color(0xFFFFB454),
      SyntaxKind.reference: Color(0xFF5FE0E8),
      SyntaxKind.math: Color(0xFFFF8A8A),
      SyntaxKind.delimiter: Color(0xFFAAAAAA),
    },
  );

  /// Nuansa kertas tua: sedikit warna, banyak ketenangan.
  static const SyntaxPalette sepia = SyntaxPalette(
    id: 'kertas',
    name: 'Kertas',
    description: 'nuansa kertas tua, warnanya sedikit',
    light: <SyntaxKind, Color>{
      SyntaxKind.text: Color(0xFF3B3228),
      SyntaxKind.comment: Color(0xFF9A8C78),
      SyntaxKind.command: Color(0xFF8B5E3C),
      SyntaxKind.sectioning: Color(0xFF6B3E26),
      SyntaxKind.environment: Color(0xFF7A6A3A),
      SyntaxKind.reference: Color(0xFF5B6B8C),
      SyntaxKind.math: Color(0xFF8C4A4A),
      SyntaxKind.delimiter: Color(0xFFA89880),
    },
    dark: <SyntaxKind, Color>{
      SyntaxKind.text: Color(0xFFE8DCC8),
      SyntaxKind.comment: Color(0xFFA2957F),
      SyntaxKind.command: Color(0xFFD7A878),
      SyntaxKind.sectioning: Color(0xFFEFC79A),
      SyntaxKind.environment: Color(0xFFCFC08A),
      SyntaxKind.reference: Color(0xFFA8B8D8),
      SyntaxKind.math: Color(0xFFD99A9A),
      SyntaxKind.delimiter: Color(0xFFB0A28C),
    },
  );

  static const List<SyntaxPalette> all = <SyntaxPalette>[calm, vivid, sepia, none];

  /// Palet dengan id itu, atau yang pertama kalau namanya tidak dikenali.
  static SyntaxPalette byId(String? id) =>
      all.firstWhere((palette) => palette.id == id, orElse: () => calm);
}

/// Gaya tulisan untuk sebuah jenis, di atas gaya dasar editor.
TextStyle styleFor(SyntaxKind kind, SyntaxPalette palette, Brightness brightness) {
  final color = palette.colorFor(kind, brightness);
  return switch (kind) {
    // Komentar dimiringkan, bukan hanya diberi warna: itu satu-satunya
    // pembedaan yang tetap terbaca oleh yang tidak membedakan warna.
    SyntaxKind.comment => TextStyle(color: color, fontStyle: FontStyle.italic),
    SyntaxKind.sectioning => TextStyle(color: color, fontWeight: FontWeight.w700),
    _ => TextStyle(color: color),
  };
}
